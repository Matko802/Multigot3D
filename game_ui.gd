class_name GameUI
extends CanvasLayer

## Simple multiplayer UI that works with GameManager

var game_manager: GameManager

@onready var main_menu: Control = $MainMenu
@onready var game_hud: Control = $GameHUD
@onready var reticle: Control = $Reticle

@onready var host_button: Button = $MainMenu/VBoxContainer/HostButton
@onready var join_button: Button = $MainMenu/VBoxContainer/LobbyControl/JoinSelectedButton
@onready var ip_input: LineEdit = $MainMenu/VBoxContainer/IPInput
@onready var name_input: LineEdit = $MainMenu/VBoxContainer/NameInput
@onready var player_count_label: Label = $GameHUD/VBoxContainer/PlayerCountLabel
@onready var disconnect_button: Button = $GameHUD/VBoxContainer/DisconnectButton
@onready var name_label: Label = $GameHUD/VBoxContainer/NameLabel
@onready var status_label: Label = $MainMenu/VBoxContainer/StatusLabel

# Lobby UI
@onready var lobby_list: ItemList = $MainMenu/VBoxContainer/LobbyList
@onready var refresh_button: Button = $MainMenu/VBoxContainer/LobbyControl/RefreshButton

func _ready() -> void:
	# Wait a frame for GameManager to be ready
	await get_tree().process_frame
	
	# Get reference to GameManager (current scene root has node named GameManager)
	game_manager = $"../GameManager"
	if game_manager == null:
		push_error("[GameUI] GameManager node not found at ../GameManager")
		return
	
	# Connect signals
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	disconnect_button.pressed.connect(_on_disconnect_pressed)
	
	if refresh_button:
		refresh_button.pressed.connect(_on_refresh_pressed)
	if lobby_list:
		lobby_list.item_selected.connect(_on_lobby_selected)
		lobby_list.item_activated.connect(_on_lobby_activated)
	
	game_manager.connection_state_changed.connect(_on_connection_state_changed)
	game_manager.player_connected.connect(_on_player_connected)
	game_manager.player_disconnected.connect(_on_player_disconnected)
	game_manager.server_found.connect(_on_server_found)
	
	if game_manager.multiplayer_spawner:
		game_manager.multiplayer_spawner.spawned.connect(_on_player_spawned)
	
	# Default IP
	ip_input.text = "127.0.0.1"
	
	# Default player name
	name_input.text = "Player_%d" % (randi() % 1000)
	
	# Start with menu
	show_menu()

func _process(_delta: float) -> void:
	if game_manager and game_manager.is_in_game():
		# Sync GameHUD visibility with mouse mode (Pause Menu behavior)
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			game_hud.visible = false
			if reticle: reticle.visible = true
		else:
			game_hud.visible = true
			if reticle: reticle.visible = false
			
		# Update UI
		if game_hud.visible:
			player_count_label.text = "Players: %d" % game_manager.get_player_count()

func show_menu() -> void:
	main_menu.visible = true
	game_hud.visible = false
	if reticle: reticle.visible = false
	
	# Start listening for servers
	if game_manager:
		game_manager.start_discovery_listening()
		_on_refresh_pressed() # Clear and refresh

func show_game() -> void:
	main_menu.visible = false
	_update_player_name_display()

## Update the player name display in the HUD
func _update_player_name_display() -> void:
	var my_peer_id = game_manager.get_my_peer_id()
	var my_player = game_manager.players_container.get_node_or_null(str(my_peer_id))
	
	if my_player:
		name_label.text = "Name: " + my_player.player_name
	else:
		name_label.text = "Name: ---"

## Set player name
func set_player_name(new_name: String) -> void:
	var my_peer_id = game_manager.get_my_peer_id()
	var my_player = game_manager.players_container.get_node_or_null(str(my_peer_id))
	
	if my_player and not new_name.is_empty():
		my_player.set_player_name(new_name)
		_update_player_name_display()

func _on_host_pressed() -> void:
	status_label.text = "Hosting..."
	if game_manager.host_game():
		# Wait a frame for player to be spawned
		await get_tree().process_frame
		if not name_input.text.is_empty():
			set_player_name(name_input.text)
		show_game()
	else:
		status_label.text = "Failed to host!"

func _on_join_pressed() -> void:
	var ip: String = ip_input.text.strip_edges()
	var port: int = 9999 # Default if manual entry
	
	# Try to parse port from IP string (e.g. 127.0.0.1:1234)
	if ":" in ip:
		var parts = ip.split(":")
		ip = parts[0]
		port = parts[1].to_int()
	
	if ip.is_empty():
		ip = "127.0.0.1"
	
	status_label.text = "Connecting..."
	if not game_manager.join_game(ip, port):
		status_label.text = "Failed to connect!"


func _on_disconnect_pressed() -> void:
	if game_manager:
		game_manager.disconnect_game()
	show_menu()

func _on_connection_state_changed(state: int) -> void:
	match state:
		GameManager.ConnectionState.DISCONNECTED:
			status_label.text = ""
			show_menu()
		GameManager.ConnectionState.HOSTING:
			status_label.text = "Hosting..."
			show_game()
		GameManager.ConnectionState.CONNECTED:
			status_label.text = ""
			show_game()

func _on_player_connected(peer_id: int) -> void:
	print("[UI] Player connected: ", peer_id)

func _on_player_disconnected(peer_id: int) -> void:
	print("[UI] Player disconnected: ", peer_id)

func _on_player_spawned(node: Node) -> void:
	if node is CharacterBody3D and node.name == str(game_manager.get_my_peer_id()):
		if not name_input.text.is_empty():
			set_player_name(name_input.text)
			print("[UI] Set local player name to: ", name_input.text)

# Lobby Functions

func _on_refresh_pressed() -> void:
	if lobby_list:
		lobby_list.clear()
	
	status_label.text = "Searching..."
	
	# Restart listening to handle cases where binding failed previously (e.g. localhost conflict)
	if game_manager:
		game_manager.start_discovery_listening()

func _on_server_found(ip: String, port: int, info: Dictionary) -> void:
	if status_label.text == "Searching...":
		status_label.text = ""
		
	if not lobby_list:
		return
		
	var key = ip + ":" + str(port)
	# Check for duplicates
	for i in lobby_list.item_count:
		if lobby_list.get_item_metadata(i) == key:
			return
			
	var server_name = info.get("name", "Unknown Server")
	var text = "%s (%s:%d)" % [server_name, ip, port]
	var idx = lobby_list.add_item(text)
	lobby_list.set_item_metadata(idx, key)

func _on_lobby_selected(index: int) -> void:
	var key = lobby_list.get_item_metadata(index)
	# Update IP input for clarity
	ip_input.text = key

func _on_lobby_activated(index: int) -> void:
	_on_lobby_selected(index)
	_on_join_pressed()
