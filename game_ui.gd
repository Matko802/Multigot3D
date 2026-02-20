class_name GameUI
extends CanvasLayer

## Simple multiplayer UI that works with GameManager

var game_manager: GameManager

@onready var main_menu: Control = $MainMenu
@onready var game_hud: Control = $GameHUD

@onready var host_button: Button = $MainMenu/VBoxContainer/HostButton
@onready var join_button: Button = $MainMenu/VBoxContainer/JoinButton
@onready var ip_input: LineEdit = $MainMenu/VBoxContainer/IPInput
@onready var name_input: LineEdit = $MainMenu/VBoxContainer/NameInput
@onready var player_count_label: Label = $GameHUD/VBoxContainer/PlayerCountLabel
@onready var disconnect_button: Button = $GameHUD/VBoxContainer/DisconnectButton
@onready var name_label: Label = $GameHUD/VBoxContainer/NameLabel
@onready var status_label: Label = $MainMenu/VBoxContainer/StatusLabel

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
	
	game_manager.connection_state_changed.connect(_on_connection_state_changed)
	game_manager.player_connected.connect(_on_player_connected)
	game_manager.player_disconnected.connect(_on_player_disconnected)
	
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
		else:
			game_hud.visible = true
			
		# Update UI
		if game_hud.visible:
			player_count_label.text = "Players: %d" % game_manager.get_player_count()

func show_menu() -> void:
	main_menu.visible = true
	game_hud.visible = false

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
	if ip.is_empty():
		ip = "127.0.0.1"
	
	status_label.text = "Connecting..."
	if not game_manager.join_game(ip):
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
