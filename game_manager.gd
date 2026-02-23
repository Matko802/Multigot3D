class_name GameManager
extends Node

## GameManager - Handles multiplayer networking using GD-Sync.
## Uses GDSync.multiplayer_instantiate for automatic node replication across clients.

const PLAYER_SCENE_PATH: String = "res://proto_controller.tscn"

@onready var players_container: Node3D = $"../Players"

# Pending action state (host/join after connection completes)
var _pending_action: String = ""
var _pending_lobby_name: String = ""
var _pending_local: bool = false
var _local_username: String = "Player"

# Track our own spawned node so we don't double-spawn
var _local_player_spawned: bool = false

# Track whether we are the original host of the lobby
var _is_host: bool = false
var _host_client_id: int = -1

# Singleplayer mode
var _is_singleplayer: bool = false

signal connection_status_changed(status: String)

func _ready() -> void:
	_setup_input_map()

	# Connect GDSync signals
	GDSync.connected.connect(_on_connected)
	GDSync.connection_failed.connect(_on_connection_failed)
	GDSync.lobby_created.connect(_on_lobby_created)
	GDSync.lobby_creation_failed.connect(_on_lobby_creation_failed)
	GDSync.lobby_joined.connect(_on_lobby_joined)
	GDSync.lobby_join_failed.connect(_on_lobby_join_failed)
	GDSync.client_joined.connect(_on_client_joined)
	GDSync.client_left.connect(_on_client_left)
	GDSync.disconnected.connect(_on_disconnected)
	GDSync.kicked.connect(_on_kicked)
	GDSync.host_changed.connect(_on_host_changed)

	print("[GameManager] Ready")


# ── Public API ──────────────────────────────────────────────────────────────

func host_game(lobby_name: String, player_name: String, local: bool = false) -> void:
	_local_username = player_name
	_pending_lobby_name = lobby_name
	_pending_action = "host"
	_pending_local = local

	connection_status_changed.emit("Connecting...")

	if GDSync.is_active() and GDSync.get_client_id() >= 0:
		# Already connected and handshake complete — go straight to lobby creation
		_process_pending_action()
	elif GDSync.is_active():
		# Connection in progress — wait for connected signal (pending action will fire then)
		pass
	else:
		if local:
			GDSync.start_local_multiplayer()
		else:
			GDSync.start_multiplayer()


func join_game(lobby_name: String, player_name: String, local: bool = false) -> void:
	_local_username = player_name
	_pending_lobby_name = lobby_name
	_pending_action = "join"
	_pending_local = local

	connection_status_changed.emit("Connecting...")

	if GDSync.is_active() and GDSync.get_client_id() >= 0:
		# Already connected and handshake complete
		_process_pending_action()
	elif GDSync.is_active():
		# Connection in progress — wait for connected signal (pending action will fire then)
		pass
	else:
		if local:
			GDSync.start_local_multiplayer()
		else:
			GDSync.start_multiplayer()


func start_singleplayer(player_name: String) -> void:
	_local_username = player_name
	_is_singleplayer = true
	_local_player_spawned = false

	# Stop any active multiplayer connection so it doesn't interfere
	if GDSync.is_active():
		GDSync.stop_multiplayer()

	_cleanup_players()
	_spawn_singleplayer()
	connection_status_changed.emit("Singleplayer")


func disconnect_game() -> void:
	if _is_singleplayer:
		_is_singleplayer = false
		_cleanup_players()
		_local_player_spawned = false
		connection_status_changed.emit("Disconnected")
		# Re-establish background connection for lobby browsing
		GDSync.start_multiplayer()
		return

	# Leave lobby first so server knows, then stop multiplayer
	if GDSync.is_active() and is_in_lobby():
		GDSync.lobby_leave()
	GDSync.stop_multiplayer()
	_cleanup_players()
	_local_player_spawned = false
	_is_host = false
	_host_client_id = -1
	connection_status_changed.emit("Disconnected")

	# Re-establish background connection for lobby browsing (non-LAN only)
	if not _pending_local:
		GDSync.start_multiplayer()


func get_player_count() -> int:
	return players_container.get_child_count()


func is_in_lobby() -> bool:
	return GDSync.is_active() and GDSync.lobby_get_name() != ""


func is_in_game() -> bool:
	return _is_singleplayer or is_in_lobby()


# ── Internal ────────────────────────────────────────────────────────────────

func _process_pending_action() -> void:
	if _pending_action == "":
		return

	# Always set username before creating/joining
	GDSync.player_set_username(_local_username)

	if _pending_action == "host":
		connection_status_changed.emit("Creating lobby...")
		GDSync.lobby_create(_pending_lobby_name, "", true, 0)
	elif _pending_action == "join":
		connection_status_changed.emit("Joining lobby...")
		GDSync.lobby_join(_pending_lobby_name)

	_pending_action = ""


func _spawn_singleplayer() -> void:
	if _local_player_spawned:
		return

	_local_player_spawned = true

	var player_scene: PackedScene = load(PLAYER_SCENE_PATH)
	var player: ProtoController = player_scene.instantiate() as ProtoController
	players_container.add_child(player)

	# Mark as singleplayer so the controller knows to skip GDSync ownership checks
	player.set_meta("singleplayer", true)

	# Set initial position
	player.position = Vector3(0.0, 5.0, 0.0)
	player.player_name = _local_username

	print("[GameManager] Spawned singleplayer player: ", player.name)


func _spawn_local_player() -> void:
	if _local_player_spawned:
		return

	_local_player_spawned = true

	var player_scene: PackedScene = load(PLAYER_SCENE_PATH)
	# multiplayer_instantiate handles: instantiate locally + replicate to all
	# other clients (current + future joiners via replicate_on_join=true).
	var player: ProtoController = GDSync.multiplayer_instantiate(player_scene, players_container, true, [], true) as ProtoController

	# Set GD-Sync ownership so only we control this player
	GDSync.set_gdsync_owner(player, GDSync.get_client_id())

	# Set initial position with some randomness so players don't stack
	player.position = Vector3(randf_range(-3.0, 3.0), 5.0, randf_range(-3.0, 3.0))

	# Set player_name — this gets synced via PropertySynchronizer's sync_starting_changes
	player.player_name = _local_username

	print("[GameManager] Spawned local player: ", player.name, " (client ", GDSync.get_client_id(), ")")


func _cleanup_players() -> void:
	for child in players_container.get_children():
		child.queue_free()


# ── Signal Callbacks ────────────────────────────────────────────────────────

func _on_connected() -> void:
	print("[GameManager] Connected to GD-Sync server")
	_process_pending_action()


func _on_connection_failed(error: int) -> void:
	print("[GameManager] Connection failed: ", error)
	connection_status_changed.emit("Connection failed (error %d)" % error)
	_pending_action = ""


func _on_disconnected() -> void:
	print("[GameManager] Disconnected")
	_cleanup_players()
	_local_player_spawned = false
	connection_status_changed.emit("Disconnected")


func _on_lobby_created(lobby_name: String) -> void:
	print("[GameManager] Lobby created: ", lobby_name)
	_is_host = true
	_host_client_id = GDSync.get_client_id()
	# Always auto-join the lobby we just created
	GDSync.lobby_join(lobby_name)


func _on_lobby_creation_failed(lobby_name: String, error: int) -> void:
	print("[GameManager] Lobby creation failed: ", lobby_name, " error: ", error)
	connection_status_changed.emit("Lobby creation failed (error %d)" % error)


func _on_lobby_joined(lobby_name: String) -> void:
	print("[GameManager] Joined lobby: ", lobby_name)
	connection_status_changed.emit("Playing in: " + lobby_name)
	# Spawn our own player
	_spawn_local_player()


func _on_lobby_join_failed(lobby_name: String, error: int) -> void:
	print("[GameManager] Lobby join failed: ", lobby_name, " error: ", error)
	connection_status_changed.emit("Join failed (error %d)" % error)


func _on_client_joined(client_id: int) -> void:
	print("[GameManager] Client joined: ", client_id)
	# Remote players are spawned automatically by GDSync's multiplayer_instantiate
	# replication system (replicate_on_join=true). No manual action needed.


func _on_client_left(client_id: int) -> void:
	print("[GameManager] Client left: ", client_id)

	# If the original host left, disconnect everyone from the lobby
	if client_id == _host_client_id:
		print("[GameManager] Host left the lobby — disconnecting all players.")
		connection_status_changed.emit("Host left the lobby")
		disconnect_game()
		return

	# Find and free any player whose gdsync owner matches the departed client.
	# Nodes are named by GDID (not client_id), so we check ownership.
	for child in players_container.get_children():
		if GDSync.get_gdsync_owner(child) == client_id:
			child.queue_free()
			print("[GameManager] Removed player node for client: ", client_id)


func _on_host_changed(is_host: bool, new_host_id: int) -> void:
	print("[GameManager] Host changed: is_host=", is_host, " new_host_id=", new_host_id)
	_is_host = is_host
	_host_client_id = new_host_id


func _on_kicked() -> void:
	print("[GameManager] Kicked from lobby")
	_cleanup_players()
	_local_player_spawned = false
	connection_status_changed.emit("Kicked from lobby")


# ── Input Map Setup ─────────────────────────────────────────────────────────

func _setup_input_map() -> void:
	var inputs: Dictionary = {
		"move_foward": [KEY_W, KEY_UP],
		"move_backward": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE],
		"sprint": [KEY_SHIFT],
		"freefly": [KEY_F],
	}

	for action: String in inputs:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		# Set deadzone (safe even if action already existed)
		InputMap.action_set_deadzone(action, 0.2)
		for key: int in inputs[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key as Key
			# Check if this exact event is already bound
			var already_bound: bool = false
			for existing_ev: InputEvent in InputMap.action_get_events(action):
				if existing_ev is InputEventKey and existing_ev.physical_keycode == ev.physical_keycode:
					already_bound = true
					break
			if not already_bound:
				InputMap.action_add_event(action, ev)
