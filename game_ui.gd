class_name GameUI
extends CanvasLayer

## UI layer for main menu, in-game HUD, and reticle.

@onready var main_menu: Control = $MainMenu
@onready var game_hud: Control = $GameHUD
@onready var reticle: Control = $Reticle

@onready var host_button: Button = $MainMenu/VBoxContainer/HostButton
@onready var host_lan_button: Button = $MainMenu/VBoxContainer/HostLANButton
@onready var join_button: Button = $MainMenu/VBoxContainer/LobbyControl/JoinSelectedButton
@onready var ip_input: LineEdit = $MainMenu/VBoxContainer/IPInput
@onready var name_input: LineEdit = $MainMenu/VBoxContainer/NameInput
@onready var player_count_label: Label = $GameHUD/VBoxContainer/PlayerCountLabel
@onready var disconnect_button: Button = $GameHUD/VBoxContainer/DisconnectButton
@onready var name_label: Label = $GameHUD/VBoxContainer/NameLabel
@onready var player_list_display: ItemList = $GameHUD/VBoxContainer/PlayerList
@onready var status_label: Label = $MainMenu/VBoxContainer/StatusLabel
@onready var lobby_list: ItemList = $MainMenu/VBoxContainer/LobbyList
@onready var refresh_button: Button = $MainMenu/VBoxContainer/LobbyControl/RefreshButton

@onready var settings_button: Button = %SettingsButton
@onready var pause_menu: Control = %PauseMenu
@onready var resume_button: Button = %ResumeButton
@onready var pause_settings_button: Button = %PauseSettingsButton
@onready var quit_button: Button = %QuitButton
@onready var settings_menu: Control = $SettingsMenu

var game_manager: GameManager
var _pending_refresh: bool = false
var _auto_refresh_timer: Timer
const AUTO_REFRESH_INTERVAL: float = 5.0

# Settings persistence
const SETTINGS_FILE_PATH: String = "user://settings.cfg"
const SETTINGS_SECTION: String = "player"
const SETTING_NAME_KEY: String = "name"

func _ready() -> void:
	game_manager = get_node("../GameManager") as GameManager

	host_button.pressed.connect(_on_host_pressed)
	if host_lan_button:
		host_lan_button.pressed.connect(_on_host_lan_pressed)
	join_button.pressed.connect(_on_join_pressed)
	disconnect_button.pressed.connect(_on_disconnect_pressed)
	refresh_button.pressed.connect(_on_refresh_pressed)
	lobby_list.item_activated.connect(_on_lobby_activated)
	
	settings_button.pressed.connect(_on_settings_pressed)
	resume_button.pressed.connect(_on_resume_pressed)
	pause_settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_disconnect_pressed)
	settings_menu.close_requested.connect(_on_settings_closed)

	game_manager.connection_status_changed.connect(_on_connection_status_changed)
	GDSync.lobbies_received.connect(_on_lobbies_received)
	GDSync.connected.connect(_on_gdsync_connected_for_refresh)
	
	GDSync.client_joined.connect(_on_client_joined_hud)
	GDSync.client_left.connect(_on_client_left_hud)
	GDSync.player_data_changed.connect(_on_player_data_changed_hud)

	# Auto-refresh timer: periodically refreshes lobbies while on the main menu
	_auto_refresh_timer = Timer.new()
	_auto_refresh_timer.wait_time = AUTO_REFRESH_INTERVAL
	_auto_refresh_timer.timeout.connect(_on_auto_refresh_timeout)
	add_child(_auto_refresh_timer)

	show_menu()
	
	# Load saved name or default
	_load_settings()

	# Auto-connect on startup so lobby list is ready immediately
	_start_auto_connect()


func _process(_delta: float) -> void:
	if game_manager.is_in_game():
		if Input.is_action_just_pressed("ui_cancel"):
			if settings_menu.visible:
				# settings_menu.close() handles saving and emitting close_requested
				# which triggers _on_settings_closed to restore menus
				settings_menu.close() 
			else:
				_toggle_pause()
		
		if pause_menu.visible or settings_menu.visible:
			game_hud.visible = false
			reticle.visible = false
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			# In-game: toggle HUD visibility based on mouse capture
			if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
				game_hud.visible = false
				reticle.visible = true
			else:
				game_hud.visible = true
				reticle.visible = false
		player_count_label.text = "Players: %d" % game_manager.get_player_count()
	else:
		# Not in game — show menu if it's hidden
		if not main_menu.visible and not settings_menu.visible:
			show_menu()
		
		# Allow toggling settings in main menu via ESC?
		if Input.is_action_just_pressed("ui_cancel") and settings_menu.visible:
			settings_menu.close()

func _toggle_pause() -> void:
	if pause_menu.visible:
		pause_menu.visible = false
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		# Ensure the player controller recaptures the mouse
		get_tree().call_group("player_controllers", "capture_mouse")
	else:
		pause_menu.visible = true
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_settings_pressed() -> void:
	settings_menu.open()
	main_menu.visible = false
	pause_menu.visible = false

func _on_settings_closed() -> void:
	if game_manager.is_in_game():
		pause_menu.visible = true
	else:
		main_menu.visible = true

func _on_resume_pressed() -> void:
	pause_menu.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# Ensure the player controller recaptures the mouse
	get_tree().call_group("player_controllers", "capture_mouse")

# ── UI State ────────────────────────────────────────────────────────────────

func show_menu() -> void:
	main_menu.visible = true
	game_hud.visible = false
	reticle.visible = false
	pause_menu.visible = false
	settings_menu.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# Resume auto-refresh when back on the menu
	if _auto_refresh_timer and GDSync.is_active() and GDSync.get_client_id() >= 0:
		_refresh_lobbies()
		_auto_refresh_timer.start()


func show_game() -> void:
	main_menu.visible = false
	game_hud.visible = true
	reticle.visible = false
	pause_menu.visible = false
	settings_menu.visible = false
	# Stop auto-refresh while in-game
	if _auto_refresh_timer:
		_auto_refresh_timer.stop()
	
	if name_label:
		name_label.text = "Name: " + name_input.text
	_update_player_list()



# ── Button Callbacks ────────────────────────────────────────────────────────

func _on_host_pressed() -> void:
	_save_settings()
	var lobby_name: String = ip_input.text.strip_edges()
	if lobby_name == "":
		lobby_name = "Lobby" + str(randi() % 100)
	game_manager.host_game(lobby_name, name_input.text.strip_edges(), false)


func _on_host_lan_pressed() -> void:
	_save_settings()
	var lobby_name: String = ip_input.text.strip_edges()
	if lobby_name == "":
		lobby_name = "LAN_Lobby" + str(randi() % 100)
	game_manager.host_game(lobby_name, name_input.text.strip_edges(), true)


func _on_join_pressed() -> void:
	_save_settings()
	var items: PackedInt32Array = lobby_list.get_selected_items()
	var lobby_name: String = ""

	if items.size() > 0:
		lobby_name = lobby_list.get_item_metadata(items[0])
	else:
		lobby_name = ip_input.text.strip_edges()

	if lobby_name == "":
		status_label.text = "Enter a lobby name or select one from the list."
		return

	game_manager.join_game(lobby_name, name_input.text.strip_edges())


func _on_disconnect_pressed() -> void:
	game_manager.disconnect_game()
	show_menu()


func _on_refresh_pressed() -> void:
	status_label.text = "Refreshing lobbies..."
	if GDSync.is_active() and GDSync.get_client_id() >= 0:
		GDSync.get_public_lobbies()
	elif GDSync.is_active():
		# Connected but handshake not complete yet — wait for it
		_pending_refresh = true
	else:
		# Need to connect first to query lobbies
		_pending_refresh = true
		GDSync.start_multiplayer()


func _start_auto_connect() -> void:
	if not GDSync.is_active():
		status_label.text = "Connecting to server..."
		_pending_refresh = true
		GDSync.start_multiplayer()
	elif GDSync.get_client_id() >= 0:
		# Already connected — just refresh and start the timer
		_refresh_lobbies()
		_auto_refresh_timer.start()


func _on_gdsync_connected_for_refresh() -> void:
	if _pending_refresh:
		_pending_refresh = false
		GDSync.get_public_lobbies()
	# Start auto-refresh timer once connected
	if not _auto_refresh_timer.is_stopped():
		return
	_auto_refresh_timer.start()


func _on_auto_refresh_timeout() -> void:
	# Only auto-refresh while on the main menu and connected
	if main_menu.visible and GDSync.is_active() and GDSync.get_client_id() >= 0:
		GDSync.get_public_lobbies()


func _refresh_lobbies() -> void:
	if GDSync.is_active() and GDSync.get_client_id() >= 0:
		GDSync.get_public_lobbies()


func _on_lobbies_received(lobbies: Array) -> void:
	# Store currently selected lobby to restore selection after refresh
	var selected_lobby_name: String = ""
	var selected_items: PackedInt32Array = lobby_list.get_selected_items()
	if selected_items.size() > 0:
		selected_lobby_name = lobby_list.get_item_metadata(selected_items[0])

	lobby_list.clear()
	status_label.text = "Found %d lobbies" % lobbies.size()
	for lobby: Dictionary in lobbies:
		var lname: String = lobby.get("Name", "???")
		var count: int = lobby.get("PlayerCount", 0)
		var limit: int = lobby.get("PlayerLimit", 0)
		var text: String = "%s (%d/%d)" % [lname, count, limit]
		var idx: int = lobby_list.add_item(text)
		lobby_list.set_item_metadata(idx, lname)
		
		# Restore selection if it matches
		if lname == selected_lobby_name:
			lobby_list.select(idx)


func _on_lobby_activated(index: int) -> void:
	var lobby_name: String = lobby_list.get_item_metadata(index)
	game_manager.join_game(lobby_name, name_input.text.strip_edges())


func _on_connection_status_changed(status: String) -> void:
	status_label.text = status
	if "Playing" in status:
		show_game()
	elif "Disconnected" in status or "failed" in status.to_lower() or "Kicked" in status:
		show_menu()


# ── Settings Persistence ────────────────────────────────────────────────────

func _save_settings() -> void:
	var config = ConfigFile.new()
	config.set_value(SETTINGS_SECTION, SETTING_NAME_KEY, name_input.text.strip_edges())
	var err = config.save(SETTINGS_FILE_PATH)
	if err != OK:
		print("[GameUI] Failed to save settings: ", err)
	else:
		print("[GameUI] Saved settings to ", SETTINGS_FILE_PATH)

func _load_settings() -> void:
	var config = ConfigFile.new()
	var err = config.load(SETTINGS_FILE_PATH)
	if err == OK:
		var saved_name = config.get_value(SETTINGS_SECTION, SETTING_NAME_KEY, "")
		if saved_name != "":
			name_input.text = saved_name
			return
	
	# Default if load fails or no name saved
	name_input.text = "Player" + str(randi() % 1000)

func _on_client_joined_hud(_client_id: int) -> void:
	_update_player_list()

func _on_client_left_hud(_client_id: int) -> void:
	_update_player_list()

func _on_player_data_changed_hud(client_id: int, key: String, _value) -> void:
	if key == "Username":
		_update_player_list()
		if client_id == GDSync.get_client_id() and name_label:
			name_label.text = "Name: " + GDSync.player_get_username(client_id)

func _update_player_list() -> void:
	if not player_list_display: return
	player_list_display.clear()
	var clients: Array = GDSync.lobby_get_all_clients()
	for client_id: int in clients:
		var username: String = GDSync.player_get_username(client_id)
		if username == "":
			username = "Player " + str(client_id)
		player_list_display.add_item(username)
