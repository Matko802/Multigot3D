class_name GameManager
extends Node

## GameManager - Handles multiplayer networking
## Using MultiplayerSpawner for automatic node replication

const PORT: int = 9999
const MAX_PLAYERS: int = 8
const SERVER_ADDRESS: String = "127.0.0.1"

## Reference to the player scene
const PLAYER_SCENE_PATH: String = "res://proto_controller.tscn"
var player_scene: PackedScene

## Current connection state
enum ConnectionState {
	DISCONNECTED,
	HOSTING,
	JOINING,
	CONNECTED
}

var connection_state: ConnectionState = ConnectionState.DISCONNECTED

## Signals for UI updates
signal connection_state_changed(state: ConnectionState)
signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_failed(reason: String)
signal server_disconnected()

@onready var players_container: Node = $"../Players"
@onready var multiplayer_spawner: MultiplayerSpawner = $"../MultiplayerSpawner"

func _ready() -> void:
	# Load player scene
	player_scene = load(PLAYER_SCENE_PATH)
	
	# Configure MultiplayerSpawner if nodes exist
	if multiplayer_spawner and players_container:
		multiplayer_spawner.spawn_path = players_container.get_path()
		multiplayer_spawner.add_spawnable_scene(PLAYER_SCENE_PATH)
	else:
		push_error("[GameManager] Missing Players container or MultiplayerSpawner!")
	
	# Setup multiplayer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	
	_setup_input_map()
	
	print("[GameManager] Ready")

func _setup_input_map() -> void:
	# Define default inputs if they are missing
	var inputs = {
		"move_forward": [KEY_W, KEY_UP],
		"move_backward": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE],
		"sprint": [KEY_SHIFT],
		"freefly": [KEY_F]
	}
	
	for action in inputs:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			for key in inputs[action]:
				var ev = InputEventKey.new()
				ev.physical_keycode = key
				InputMap.action_add_event(action, ev)
				print("[GameManager] Added input action: ", action, " with key: ", key)


## Start hosting a game (becomes server)
func host_game() -> bool:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS)
	
	if err != OK:
		push_error("[GameManager] Failed to host: ", err)
		connection_failed.emit("Failed to create server")
		return false
	
	multiplayer.multiplayer_peer = peer
	connection_state = ConnectionState.HOSTING
	connection_state_changed.emit(connection_state)
	
	print("[GameManager] Hosting on port ", PORT)
	
	# Spawn the host player immediately (Server only)
	_spawn_player(1)
	
	return true

## Join an existing game
func join_game(address: String = SERVER_ADDRESS) -> bool:
	if address.is_empty():
		address = SERVER_ADDRESS
		
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, PORT)
	
	if err != OK:
		push_error("[GameManager] Failed to join: ", err)
		connection_failed.emit("Failed to connect to server")
		return false
	
	multiplayer.multiplayer_peer = peer
	connection_state = ConnectionState.JOINING
	connection_state_changed.emit(connection_state)
	
	print("[GameManager] Joining ", address, ":", PORT)
	return true

## Disconnect from current game
func disconnect_game() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	
	# Clear all players from scene locally
	# Since we disconnected, MultiplayerSpawner won't sync deletions, so we must clean up manually
	for child in players_container.get_children():
		child.queue_free()
	
	connection_state = ConnectionState.DISCONNECTED
	connection_state_changed.emit(connection_state)
	print("[GameManager] Disconnected")

## Spawn a player for a specific peer (Server Only)
## MultiplayerSpawner will automatically replicate this to all clients
func _spawn_player(peer_id: int) -> void:
	if not is_server():
		return
		
	# Check if player already exists
	if players_container.has_node(str(peer_id)):
		return
		
	var player := player_scene.instantiate()
	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id)
	players_container.add_child(player, true) # true = force readable name
	
	# Set spawn position
	var spawn_pos := _get_next_spawn_position(players_container.get_child_count() - 1)
	player.global_position = spawn_pos
	
	print("[GameManager] Spawned player ", peer_id, " at ", spawn_pos)

## Get spawn position for player index
func _get_next_spawn_position(index: int) -> Vector3:
	var spawn_points := [
		Vector3(0, 2, 0),
		Vector3(5, 2, 0),
		Vector3(-5, 2, 0),
		Vector3(0, 2, 5),
		Vector3(0, 2, -5),
		Vector3(5, 2, 5),
		Vector3(-5, 2, 5),
		Vector3(5, 2, -5),
	]
	return spawn_points[index % spawn_points.size()]

## Get player count
func get_player_count() -> int:
	return players_container.get_child_count()

## Check if we are the server
func is_server() -> bool:
	return multiplayer.is_server()

## Check if we are in a game
func is_in_game() -> bool:
	return connection_state == ConnectionState.HOSTING or connection_state == ConnectionState.CONNECTED

## Get our peer ID
func get_my_peer_id() -> int:
	return multiplayer.get_unique_id()

# ==================== Multiplayer Signal Callbacks ====================

func _on_peer_connected(peer_id: int) -> void:
	print("[GameManager] Peer connected: ", peer_id)
	player_connected.emit(peer_id)
	
	# Server handles spawning the new player
	if is_server():
		_spawn_player(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	print("[GameManager] Peer disconnected: ", peer_id)
	player_disconnected.emit(peer_id)
	
	# Server handles removing the player
	if is_server():
		var player = players_container.get_node_or_null(str(peer_id))
		if player:
			player.queue_free()

func _on_connected_to_server() -> void:
	connection_state = ConnectionState.CONNECTED
	connection_state_changed.emit(connection_state)
	print("[GameManager] Connected to server")
	# Client doesn't need to request spawn; server does it automatically on connect

func _on_connection_failed() -> void:
	connection_state = ConnectionState.DISCONNECTED
	connection_state_changed.emit(connection_state)
	connection_failed.emit("Connection failed")
	print("[GameManager] Connection failed")

func _on_server_disconnected() -> void:
	connection_state = ConnectionState.DISCONNECTED
	connection_state_changed.emit(connection_state)
	server_disconnected.emit()
	print("[GameManager] Server disconnected")
	
	# Clean up players
	for child in players_container.get_children():
		child.queue_free()
