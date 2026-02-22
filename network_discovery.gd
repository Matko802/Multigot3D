class_name NetworkDiscovery
extends Node

signal server_found(ip: String, port: int, info: Dictionary)

const BROADCAST_PORT: int = 8910
const BROADCAST_INTERVAL: float = 1.0

var broadcast_timer: Timer
var udp_peer: PacketPeerUDP = null
var is_broadcasting: bool = false
var is_listening: bool = false
var server_info: Dictionary = {}

func _ready() -> void:
	# UDP is not available in web browsers — disable network discovery entirely
	if OS.has_feature("web"):
		set_process(false)
		return

	broadcast_timer = Timer.new()
	broadcast_timer.wait_time = BROADCAST_INTERVAL
	broadcast_timer.timeout.connect(_broadcast)
	add_child(broadcast_timer)
	
	udp_peer = PacketPeerUDP.new()
	if udp_peer:
		udp_peer.set_broadcast_enabled(true)

func _process(_delta: float) -> void:
	if is_listening:
		while udp_peer.get_available_packet_count() > 0:
			var packet = udp_peer.get_packet()
			var sender_ip = udp_peer.get_packet_ip()
			# sender_port is the random port they sent from, not necessarily the game port.
			
			var data_str = packet.get_string_from_utf8()
			if data_str.begins_with("GAME_SERVER:"):
				var json_str = data_str.trim_prefix("GAME_SERVER:")
				var json = JSON.new()
				if json.parse(json_str) == OK:
					var info = json.data
					if info is Dictionary:
						# Extract game port
						var game_port = info.get("port", 0)
						if game_port > 0:
							server_found.emit(sender_ip, game_port, info)

func start_broadcasting(server_name: String, game_port: int) -> void:
	if OS.has_feature("web") or is_broadcasting:
		return
	
	stop_listening() # Ensure we aren't listening
	
	server_info = {
		"Name": server_name,
		"port": game_port,
		"PlayerCount": 0,
		"PlayerLimit": 8
	}
	
	is_broadcasting = true
	broadcast_timer.start()
	print("[NetworkDiscovery] Started broadcasting on port ", BROADCAST_PORT)

func stop_broadcasting() -> void:
	if is_broadcasting:
		broadcast_timer.stop()
		is_broadcasting = false
		print("[NetworkDiscovery] Stopped broadcasting")

func start_listening() -> void:
	if OS.has_feature("web") or is_listening:
		return
		
	stop_broadcasting()
	
	# Close existing peer if any to reset binding
	udp_peer.close()
	var err = udp_peer.bind(BROADCAST_PORT)
	if err != OK:
		push_warning("[NetworkDiscovery] Failed to bind UDP socket on port " + str(BROADCAST_PORT) + ". Error: " + str(err) + " (This is normal if another game instance is running)")
		return
		
	is_listening = true
	print("[NetworkDiscovery] Started listening on port ", BROADCAST_PORT)

func stop_listening() -> void:
	if is_listening:
		udp_peer.close()
		is_listening = false
		print("[NetworkDiscovery] Stopped listening")

func _broadcast() -> void:
	if not is_broadcasting:
		return
	
	var msg = "GAME_SERVER:" + JSON.stringify(server_info)
	var packet = msg.to_utf8_buffer()
	
	udp_peer.set_dest_address("255.255.255.255", BROADCAST_PORT)
	var err = udp_peer.put_packet(packet)
	if err != OK:
		# push_warning("Broadcast failed: " + str(err))
		pass
