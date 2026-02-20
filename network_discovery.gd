class_name NetworkDiscovery
extends Node

## Handles LAN discovery using UDP broadcasting
## Broadcasts server presence and listens for other servers

signal server_found(ip: String, port: int, info: Dictionary)

const BROADCAST_PORT: int = 8910 # The port used for discovery packets
const BROADCAST_INTERVAL: float = 1.0

var _udp_peer: PacketPeerUDP
var _broadcast_timer: Timer
var _is_broadcasting: bool = false
var _is_listening: bool = false
var _server_info: Dictionary = {}

func _ready() -> void:
	_broadcast_timer = Timer.new()
	_broadcast_timer.wait_time = BROADCAST_INTERVAL
	_broadcast_timer.timeout.connect(_broadcast_presence)
	add_child(_broadcast_timer)
	
	# Initial peer setup not strictly needed if we create on demand
	_udp_peer = PacketPeerUDP.new()
	_udp_peer.set_broadcast_enabled(true)

func _process(_delta: float) -> void:
	if _is_listening and _udp_peer and _udp_peer.is_bound():
		_listen_for_packets()

## Start broadcasting presence to LAN
func start_broadcasting(server_name: String, game_port: int) -> void:
	stop_listening() # Ensure we aren't listening and peer is closed/reset
	stop_broadcasting() # Reset if already broadcasting
	
	# Re-create peer to ensure clean state
	_udp_peer = PacketPeerUDP.new()
	_udp_peer.set_broadcast_enabled(true)
	# No need to bind for sending

	_server_info = {
		"name": server_name,
		"port": game_port
	}
	_udp_peer.set_dest_address("255.255.255.255", BROADCAST_PORT)
	_is_broadcasting = true
	_broadcast_timer.start()
	print("[NetworkDiscovery] Started broadcasting server '", server_name, "' on game port ", game_port)

## Stop broadcasting
func stop_broadcasting() -> void:
	_is_broadcasting = false
	_broadcast_timer.stop()
	if _udp_peer:
		_udp_peer.close()
		_udp_peer = null
	print("[NetworkDiscovery] Stopped broadcasting")

## Start listening for other servers
func start_listening() -> void:
	stop_broadcasting() # Ensure we aren't broadcasting
	stop_listening() # Reset if already listening

	# Re-create peer for listening
	_udp_peer = PacketPeerUDP.new()
	_udp_peer.set_broadcast_enabled(true)
		
	var err = _udp_peer.bind(BROADCAST_PORT)
	if err != OK:
		if err == ERR_ALREADY_IN_USE or err == ERR_UNAVAILABLE:
			push_warning("[NetworkDiscovery] Port %d unavailable (likely in use). Discovery listening disabled. (Ignore if running multiple instances)" % BROADCAST_PORT)
		else:
			push_error("[NetworkDiscovery] Failed to bind to broadcast port: %d" % err)
		return
		
	_is_listening = true
	print("[NetworkDiscovery] Started listening on port ", BROADCAST_PORT)

## Stop listening
func stop_listening() -> void:
	_is_listening = false
	if _udp_peer:
		_udp_peer.close()
		_udp_peer = null
	print("[NetworkDiscovery] Stopped listening")

func _broadcast_presence() -> void:
	if not _is_broadcasting or not _udp_peer:
		return
	
	var json_str = JSON.stringify(_server_info)
	var packet = json_str.to_utf8_buffer()
	
	# Ensure destination is set
	_udp_peer.set_dest_address("255.255.255.255", BROADCAST_PORT)
	
	var err = _udp_peer.put_packet(packet)
	if err != OK:
		push_warning("[NetworkDiscovery] Failed to broadcast: ", err)

func _listen_for_packets() -> void:
	if not _udp_peer:
		return
		
	while _udp_peer.get_available_packet_count() > 0:
		var packet = _udp_peer.get_packet()
		var packet_ip = _udp_peer.get_packet_ip()
		var packet_str = packet.get_string_from_utf8()
		
		# Ignore empty packets
		if packet_str.is_empty():
			continue

		var json = JSON.new()
		var error = json.parse(packet_str)
		
		if error == OK:
			var data = json.data
			if data is Dictionary and data.has("port"):
				# Emit signal
				server_found.emit(packet_ip, int(data["port"]), data)
		else:
			print("[NetworkDiscovery] Received invalid packet: ", packet_str)
