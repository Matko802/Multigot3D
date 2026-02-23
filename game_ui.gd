class_name GameUI
extends CanvasLayer

## UI layer for main menu, in-game HUD, and reticle.

@onready var main_menu: Control = $MainMenu
@onready var game_hud: Control = $GameHUD
@onready var reticle: Control = $Reticle

@onready var host_button: Button = $MainMenu/PlayMenu/CenterContainer/PlayPanel/Content/TabContainer/Multiplayer/HostButton
@onready var host_lan_button: Button = $MainMenu/PlayMenu/CenterContainer/PlayPanel/Content/TabContainer/Multiplayer/HostLANButton
@onready var join_button: Button = $MainMenu/PlayMenu/CenterContainer/PlayPanel/Content/TabContainer/Multiplayer/LobbyControl/JoinSelectedButton
@onready var ip_input: LineEdit = $MainMenu/PlayMenu/CenterContainer/PlayPanel/Content/TabContainer/Multiplayer/IPInput
@onready var name_input: LineEdit = $MainMenu/PlayMenu/CenterContainer/PlayPanel/Content/NameInput
@onready var player_count_label: Label = $GameHUD/VBoxContainer/PlayerCountLabel
@onready var disconnect_button: Button = $GameHUD/VBoxContainer/DisconnectButton
@onready var name_label: Label = $GameHUD/VBoxContainer/NameLabel
@onready var status_label: Label = $MainMenu/PlayMenu/CenterContainer/PlayPanel/Content/TabContainer/Multiplayer/StatusLabel
@onready var lobby_list: ItemList = $MainMenu/PlayMenu/CenterContainer/PlayPanel/Content/TabContainer/Multiplayer/LobbyList
@onready var refresh_button: Button = $MainMenu/PlayMenu/CenterContainer/PlayPanel/Content/TabContainer/Multiplayer/LobbyControl/RefreshButton

@onready var player_list: Control = $PlayerList

@onready var settings_button: Button = %SettingsButton
@onready var pause_menu: Control = %PauseMenu
@onready var pause_container: Control = $PauseMenu/PauseContainer
@onready var pause_panel: PanelContainer = $PauseMenu/PauseContainer/PanelContainer
@onready var resume_button: Button = %ResumeButton
@onready var pause_settings_button: Button = %PauseSettingsButton
@onready var quit_button: Button = %QuitButton
@onready var settings_menu: Control = $SettingsMenu

@onready var singleplayer_button: Button = $MainMenu/PlayMenu/CenterContainer/PlayPanel/Content/TabContainer/Singleplayer/SingleplayerButton

@onready var start_screen: Control = $MainMenu/StartScreen
@onready var play_menu: Control = $MainMenu/PlayMenu
@onready var play_button: Button = $MainMenu/StartScreen/PlayButton
@onready var desktop_quit_button: Button = $MainMenu/StartScreen/DesktopQuitButton
@onready var back_button: Button = $MainMenu/PlayMenu/CenterContainer/PlayPanel/Content/BackButton
@onready var web_warning: Label = $WebWarning
@onready var map_option_button: OptionButton = $MainMenu/PlayMenu/CenterContainer/PlayPanel/Content/TabContainer/Multiplayer/MapOptionButton

var game_manager: GameManager
var _pending_refresh: bool = false
var _auto_refresh_timer: Timer
const AUTO_REFRESH_INTERVAL: float = 5.0

# Track UI state to prevent race conditions
var _transitioning: bool = false
var _is_currently_in_game: bool = false

# Settings persistence
const SETTINGS_FILE_PATH: String = "user://settings.cfg"
const SETTINGS_SECTION: String = "player"
const SETTING_NAME_KEY: String = "name"

# DPI Scaling
var _base_dpi: float = 96.0
var _screen_dpi: float = 96.0

func _ready() -> void:
	# Try to find GameManager - works for both main.tscn and Baseplate.tscn layouts
	game_manager = get_node_or_null("../GameManager") as GameManager
	if not game_manager:
		# Fallback: search the tree for GameManager
		game_manager = get_tree().root.find_child("GameManager", true, false) as GameManager
	
	if not game_manager:
		push_error("[GameUI] Failed to find GameManager in scene!")
		return
	
	# Initialize DPI scaling
	_calculate_screen_dpi()
	_apply_dpi_scaling_to_pause_menu()
	_apply_dpi_scaling_to_game_hud()

	if map_option_button:
		map_option_button.clear()
		map_option_button.add_item("Testing Map")
		map_option_button.set_item_metadata(0, "res://main.tscn")
		map_option_button.add_item("Baseplate Map")
		map_option_button.set_item_metadata(1, "res://Baseplate.tscn")
		# Move to index 1 (after lobby name input) if possible
		var mp_container = map_option_button.get_parent()
		if mp_container and mp_container.get_child_count() > 1:
			mp_container.move_child(map_option_button, 1)

	host_button.pressed.connect(_on_host_pressed)
	if host_lan_button:
		host_lan_button.pressed.connect(_on_host_lan_pressed)
	join_button.pressed.connect(_on_join_pressed)
	disconnect_button.pressed.connect(_on_disconnect_pressed)
	refresh_button.pressed.connect(_on_refresh_pressed)
	lobby_list.item_activated.connect(_on_lobby_activated)
	
	singleplayer_button.pressed.connect(_on_singleplayer_pressed)
	
	play_button.pressed.connect(_on_play_pressed)
	desktop_quit_button.pressed.connect(_on_desktop_quit_pressed)
	back_button.pressed.connect(_on_back_pressed)
	
	settings_button.pressed.connect(_on_settings_pressed)
	resume_button.pressed.connect(_on_resume_pressed)
	pause_settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_disconnect_pressed)
	settings_menu.close_requested.connect(_on_settings_closed)
	
	# Connect to window resizing to recalculate DPI on orientation/resolution changes
	get_window().size_changed.connect(_on_window_resized)

	game_manager.connection_status_changed.connect(_on_connection_status_changed)
	GDSync.lobbies_received.connect(_on_lobbies_received)
	GDSync.connected.connect(_on_gdsync_connected_for_refresh)
	
	GDSync.player_data_changed.connect(_on_player_data_changed_hud)

	# Auto-refresh timer: periodically refreshes lobbies while on the main menu
	_auto_refresh_timer = Timer.new()
	_auto_refresh_timer.wait_time = AUTO_REFRESH_INTERVAL
	_auto_refresh_timer.timeout.connect(_on_auto_refresh_timeout)
	add_child(_auto_refresh_timer)

	# Check initial state (fix for scene transitions where signals are missed)
	if game_manager.is_in_game():
		show_game()
		if status_label and GDSync.lobby_get_name() != "":
			status_label.text = "Playing in: " + GDSync.lobby_get_name()
	else:
		show_menu()
	
	# Show web warning if running in a browser
	if OS.has_feature("web"):
		web_warning.visible = true
		# Disable multiplayer buttons on web since they won't work
		host_button.disabled = true
		host_button.tooltip_text = "Not available in web builds"
		if host_lan_button:
			host_lan_button.disabled = true
			host_lan_button.tooltip_text = "Not available in web builds"
		join_button.disabled = true
		join_button.tooltip_text = "Not available in web builds"
		refresh_button.disabled = true
		refresh_button.tooltip_text = "Not available in web builds"
	
	# Load saved name or default
	_load_settings()

	# Auto-connect on startup so lobby list is ready immediately (skip on web)
	# Only if not already in game
	if not game_manager.is_in_game() and not OS.has_feature("web"):
		_start_auto_connect()


func _process(_delta: float) -> void:
	# Safety check for GameManager
	if not game_manager:
		return
	
	# If we're currently in-game (based on our own tracking), handle game logic
	if _is_currently_in_game:
		if Input.is_action_just_pressed("ui_cancel"):
			if settings_menu.visible:
				# settings_menu.close() handles saving and emitting close_requested
				# which triggers _on_settings_closed to restore menus
				settings_menu.close() 
			else:
				_toggle_pause()
		
		# Tab key to show/hide player list (held down shows list, like Minecraft)
		if Input.is_action_pressed("ui_focus_next"):  # Tab key
			if player_list:
				player_list.visible = true
		else:
			# Tab released - hide player list
			if player_list:
				player_list.visible = false
		
		# Hide player list when pause menu or settings are open
		if pause_menu.visible or settings_menu.visible:
			game_hud.visible = false
			reticle.visible = false
			if player_list:
				player_list.visible = false
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
		# Not in game — show menu if not already visible
		if not main_menu.visible and not settings_menu.visible:
			show_menu()
		
		# Hide player list overlay when not in game
		if player_list:
			player_list.visible = false
		
		# Ensure all game elements are hidden
		game_hud.visible = false
		reticle.visible = false
		pause_menu.visible = false
		
		# Allow toggling settings in main menu via ESC?
		if Input.is_action_just_pressed("ui_cancel") and settings_menu.visible:
			settings_menu.close()

func _toggle_pause() -> void:
	if pause_menu.visible:
		pause_menu.visible = false
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		get_tree().call_group("player_controllers", "capture_mouse")
	else:
		pause_menu.visible = true
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_settings_pressed() -> void:
	settings_menu.open()
	main_menu.visible = false
	pause_menu.visible = false

func _on_settings_closed() -> void:
	if _is_currently_in_game:
		pause_menu.visible = true
	else:
		main_menu.visible = true

func _on_resume_pressed() -> void:
	pause_menu.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	get_tree().call_group("player_controllers", "capture_mouse")

# ── UI State ────────────────────────────────────────────────────────────────

func show_menu() -> void:
	_is_currently_in_game = false  # Track that we're back in menu
	main_menu.visible = true
	start_screen.visible = true
	play_menu.visible = false
	game_hud.visible = false
	reticle.visible = false
	pause_menu.visible = false
	settings_menu.visible = false
	# Show web warning only on main menu
	if web_warning and OS.has_feature("web"):
		web_warning.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# Resume auto-refresh when back on the menu
	if _auto_refresh_timer and GDSync.is_active() and GDSync.get_client_id() >= 0:
		_refresh_lobbies()
		_auto_refresh_timer.start()

func _on_play_pressed() -> void:
	start_screen.visible = false
	play_menu.visible = true

func _on_back_pressed() -> void:
	start_screen.visible = true
	play_menu.visible = false

func _on_desktop_quit_pressed() -> void:
	get_tree().quit()


func show_game() -> void:
	print("[GameUI] show_game() called")
	_is_currently_in_game = true  # Track that we're in game - this must be set FIRST
	
	# Ensure menu is completely hidden
	main_menu.visible = false
	pause_menu.visible = false
	settings_menu.visible = false
	
	# Show game HUD and reticle
	game_hud.visible = true
	reticle.visible = false
	
	# Hide web warning when in-game
	if web_warning:
		web_warning.visible = false
	
	# Stop auto-refresh while in-game
	if _auto_refresh_timer:
		_auto_refresh_timer.stop()
	
	if name_label:
		name_label.text = "Name: " + name_input.text
	
	if player_list:
		player_list.visible = false
	
	# Force mouse mode for gameplay
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	get_tree().call_group("player_controllers", "capture_mouse")
	
	print("[GameUI] Game UI shown - main_menu.visible=", main_menu.visible, ", game_hud.visible=", game_hud.visible)



# ── Button Callbacks ────────────────────────────────────────────────────────

func _on_singleplayer_pressed() -> void:
	_save_settings()
	var player_name: String = name_input.text.strip_edges()
	if player_name == "":
		player_name = "Player" + str(randi() % 1000)
	game_manager.start_singleplayer(player_name)


func _on_host_pressed() -> void:
	_save_settings()
	var lobby_name: String = ip_input.text.strip_edges()
	if lobby_name == "":
		lobby_name = "Lobby" + str(randi() % 100)
	
	var map_path: String = "res://main.tscn"
	if map_option_button and map_option_button.selected != -1:
		map_path = map_option_button.get_item_metadata(map_option_button.selected)
		
	game_manager.host_game(lobby_name, name_input.text.strip_edges(), false, map_path)


func _on_host_lan_pressed() -> void:
	_save_settings()
	var lobby_name: String = ip_input.text.strip_edges()
	if lobby_name == "":
		lobby_name = "LAN_Lobby" + str(randi() % 100)
	
	var map_path: String = "res://main.tscn"
	if map_option_button and map_option_button.selected != -1:
		map_path = map_option_button.get_item_metadata(map_option_button.selected)
		
	game_manager.host_game(lobby_name, name_input.text.strip_edges(), true, map_path)


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
	print("[GameUI] Connection status changed: ", status)
	if status_label:
		status_label.text = status
	if "Playing" in status or "Singleplayer" in status:
		print("[GameUI] Detected 'Playing' or 'Singleplayer' - showing game")
		show_game()
	elif "Disconnected" in status or "failed" in status.to_lower() or "Kicked" in status:
		print("[GameUI] Detected disconnect - showing menu")
		show_menu()
	else:
		print("[GameUI] Status doesn't match any transition condition: ", status)


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

func _on_player_data_changed_hud(client_id: int, key: String, _value) -> void:
	if key == "Username":
		if client_id == GDSync.get_client_id() and name_label:
			name_label.text = "Name: " + GDSync.player_get_username(client_id)



# ── DPI Scaling ─────────────────────────────────────────────────────────────

func _calculate_screen_dpi() -> void:
	"""Calculate screen DPI based on screen size and resolution."""
	# Use viewport-based DPI estimation since DisplayServer.screen_get_physical_size() is not available
	_screen_dpi = _estimate_dpi_from_viewport()
	print("[GameUI] Screen DPI: %.1f" % _screen_dpi)


func _estimate_dpi_from_viewport() -> float:
	"""Estimate DPI based on viewport size if physical screen info unavailable."""
	var viewport_size: Vector2i = get_viewport().get_visible_rect().size
	# Assume typical monitor 16:9 aspect ratio at 24 inches diagonal
	var estimated_diagonal_px: float = sqrt(
		pow(viewport_size.x, 2) + pow(viewport_size.y, 2)
	)
	# Standard 24" 1080p = ~92 DPI
	if estimated_diagonal_px > 2500:
		return 110.0  # High DPI (4K or high-res display)
	elif estimated_diagonal_px > 1920:
		return 96.0   # Standard DPI
	else:
		return 72.0   # Lower DPI (smaller screens)


func _apply_dpi_scaling_to_pause_menu() -> void:
	"""Apply DPI-aware sizing to the pause menu."""
	if not pause_panel:
		return
	
	var dpi_scale: float = _screen_dpi / _base_dpi
	
	# Base size adjusted by DPI scale
	var base_width: float = 500.0
	var base_height: float = 350.0
	
	var scaled_width: float = base_width * dpi_scale
	var scaled_height: float = base_height * dpi_scale
	
	# Clamp to reasonable bounds
	scaled_width = clampf(scaled_width, 400.0, 800.0)
	scaled_height = clampf(scaled_height, 300.0, 600.0)
	
	pause_panel.custom_minimum_size = Vector2(scaled_width, scaled_height)
	
	print("[GameUI] Pause Menu Scaled to: %.0fx%.0f (DPI Scale: %.2f)" % [scaled_width, scaled_height, dpi_scale])


func _apply_dpi_scaling_to_game_hud() -> void:
	"""Apply DPI-aware sizing and positioning to GameHUD at top-left."""
	if not game_hud or not game_hud.get_child(0):
		return
	
	var vbox: VBoxContainer = game_hud.get_child(0) as VBoxContainer
	if not vbox:
		return
	
	var dpi_scale: float = _screen_dpi / _base_dpi
	
	# Base dimensions (in "logical" pixels at 96 DPI)
	var base_width: float = 350.0
	var base_height: float = 250.0
	var base_padding: float = 10.0
	
	# Scale dimensions
	var scaled_width: float = base_width * dpi_scale
	var scaled_height: float = base_height * dpi_scale
	var scaled_padding: float = base_padding * dpi_scale
	
	# Apply to VBoxContainer
	vbox.custom_minimum_size = Vector2(scaled_width, scaled_height)
	vbox.set_anchors_preset(Control.PRESET_TOP_LEFT)
	vbox.offset_left = scaled_padding
	vbox.offset_top = scaled_padding
	vbox.offset_right = scaled_width + scaled_padding
	vbox.offset_bottom = scaled_height + scaled_padding
	
	print("[GameUI] GameHUD Scaled to: %.0fx%.0f (DPI Scale: %.2f)" % [scaled_width, scaled_height, dpi_scale])


func _on_window_resized() -> void:
	"""Handle window resize events to recalculate DPI if needed."""
	_calculate_screen_dpi()
	_apply_dpi_scaling_to_pause_menu()
	_apply_dpi_scaling_to_game_hud()
