class_name SettingsMenu
extends Control

## Settings menu with Controls, Audio, Graphics, and Gameplay tabs.

signal close_requested

const SETTINGS_FILE_PATH: String = "user://game_settings.cfg"
const SETTINGS_SECTION: String = "settings"

# Controls
@onready var sensitivity_slider: HSlider = %SensitivitySlider
@onready var sensitivity_value: Label = %SensitivityValue
@onready var fov_slider: HSlider = %FOVSlider
@onready var fov_value: Label = %FOVValue
@onready var invert_y_toggle: CheckButton = %InvertYToggle

# Audio
@onready var master_volume_slider: HSlider = %MasterVolumeSlider
@onready var master_volume_value: Label = %MasterVolumeValue
@onready var effects_volume_slider: HSlider = %EffectsVolumeSlider
@onready var effects_volume_value: Label = %EffectsVolumeValue
@onready var mute_toggle: CheckButton = %MuteToggle

# Graphics
@onready var vsync_toggle: CheckButton = %VSyncToggle
@onready var fullscreen_button: Button = %FullscreenButton
@onready var fullscreen_mode_label: Label = %FullscreenModeLabel

# Gameplay
@onready var show_nametags_toggle: CheckButton = %ShowNametagsToggle

# Buttons
@onready var reset_button: Button = %ResetButton
@onready var back_button: Button = %BackButton

func _ready() -> void:
	_apply_dpi_scaling()
	_load_settings()
	
	# Controls
	sensitivity_slider.value_changed.connect(_on_sensitivity_changed)
	fov_slider.value_changed.connect(_on_fov_changed)
	invert_y_toggle.toggled.connect(_on_invert_y_toggled)
	
	# Audio
	master_volume_slider.value_changed.connect(_on_master_volume_changed)
	effects_volume_slider.value_changed.connect(_on_effects_volume_changed)
	mute_toggle.toggled.connect(_on_mute_toggled)
	
	# Graphics
	vsync_toggle.toggled.connect(_on_vsync_toggled)
	if fullscreen_button:
		fullscreen_button.pressed.connect(_on_fullscreen_pressed)
	
	# Gameplay
	show_nametags_toggle.toggled.connect(_on_show_nametags_toggled)
	
	# Buttons
	reset_button.pressed.connect(_on_reset_pressed)
	back_button.pressed.connect(_on_back_pressed)

func open() -> void:
	visible = true
	_load_settings() # Reload in case they changed or just to be sure state matches

func close() -> void:
	_on_back_pressed()

func _on_back_pressed() -> void:
	_save_settings()
	close_requested.emit()
	visible = false

func _on_reset_pressed() -> void:
	sensitivity_slider.value = 1.0
	_on_sensitivity_changed(1.0)
	
	fov_slider.value = 75.0
	_on_fov_changed(75.0)
	
	invert_y_toggle.button_pressed = false
	_on_invert_y_toggled(false)
	
	master_volume_slider.value = 1.0
	_on_master_volume_changed(1.0)
	
	effects_volume_slider.value = 1.0
	_on_effects_volume_changed(1.0)
	
	mute_toggle.button_pressed = false
	_on_mute_toggled(false)
	
	vsync_toggle.button_pressed = true 
	_on_vsync_toggled(true)
	
	show_nametags_toggle.button_pressed = true
	_on_show_nametags_toggled(true)
	
	_set_fullscreen_mode(0)  # Default: windowed
	
	_save_settings()

# ── Controls ────────────────────────────────────────────────────────────────

func _on_sensitivity_changed(value: float) -> void:
	sensitivity_value.text = "%.2f" % value
	get_tree().call_group("player_controllers", "update_sensitivity", value)

func _on_fov_changed(value: float) -> void:
	fov_value.text = "%d°" % int(value)
	get_tree().call_group("player_controllers", "update_fov", value)

func _on_invert_y_toggled(toggled: bool) -> void:
	get_tree().call_group("player_controllers", "update_invert_y", toggled)

# ── Audio ───────────────────────────────────────────────────────────────────

func _on_master_volume_changed(value: float) -> void:
	master_volume_value.text = "%d%%" % int(value * 100)
	var bus_idx = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus_idx, linear_to_db(value))
	if value == 0:
		AudioServer.set_bus_mute(bus_idx, true)
	elif not mute_toggle.button_pressed:
		AudioServer.set_bus_mute(bus_idx, false)

func _on_effects_volume_changed(value: float) -> void:
	effects_volume_value.text = "%d%%" % int(value * 100)
	var bus_idx = AudioServer.get_bus_index("SFX") # Assuming SFX bus exists, fallback to nothing if not
	if bus_idx == -1:
		bus_idx = AudioServer.get_bus_index("Effects")
	
	if bus_idx != -1:
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(value))

func _on_mute_toggled(toggled: bool) -> void:
	var bus_idx = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(bus_idx, toggled)

# ── Graphics ────────────────────────────────────────────────────────────────

func _on_vsync_toggled(toggled: bool) -> void:
	if toggled:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

func _on_fullscreen_pressed() -> void:
	# Cycle through modes: 0 = Windowed, 1 = Fullscreen
	var current_mode: int = _get_current_fullscreen_mode()
	var next_mode: int = (current_mode + 1) % 2
	_set_fullscreen_mode(next_mode)

func _get_current_fullscreen_mode() -> int:
	var mode: DisplayServer.WindowMode = DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		return 1
	else:
		return 0

func _update_fullscreen_mode_label() -> void:
	"""Update the label to reflect current fullscreen state without changing window mode."""
	if not fullscreen_mode_label:
		return
	
	var mode: int = _get_current_fullscreen_mode()
	match mode:
		0:
			fullscreen_mode_label.text = "Windowed"
		1:
			fullscreen_mode_label.text = "Fullscreen"

func _set_fullscreen_mode(mode: int) -> void:
	"""Actually change the fullscreen mode and update the label."""
	if not fullscreen_mode_label:
		return
	
	match mode:
		0:  # Windowed
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			fullscreen_mode_label.text = "Windowed"
		1:  # Fullscreen
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
			fullscreen_mode_label.text = "Fullscreen"

# ── Gameplay ────────────────────────────────────────────────────────────────

func _on_show_nametags_toggled(toggled: bool) -> void:
	get_tree().call_group("player_controllers", "update_nametags_visibility", toggled)

# ── Persistence ─────────────────────────────────────────────────────────────

func _save_settings() -> void:
	var config = ConfigFile.new()
	
	config.set_value(SETTINGS_SECTION, "sensitivity", sensitivity_slider.value)
	config.set_value(SETTINGS_SECTION, "fov", fov_slider.value)
	config.set_value(SETTINGS_SECTION, "invert_y", invert_y_toggle.button_pressed)
	
	config.set_value(SETTINGS_SECTION, "master_volume", master_volume_slider.value)
	config.set_value(SETTINGS_SECTION, "effects_volume", effects_volume_slider.value)
	config.set_value(SETTINGS_SECTION, "mute", mute_toggle.button_pressed)
	
	config.set_value(SETTINGS_SECTION, "vsync", vsync_toggle.button_pressed)
	
	config.set_value(SETTINGS_SECTION, "fullscreen_mode", _get_current_fullscreen_mode())
	
	config.set_value(SETTINGS_SECTION, "show_nametags", show_nametags_toggle.button_pressed)
	
	var err = config.save(SETTINGS_FILE_PATH)
	if err != OK:
		print("[SettingsMenu] Failed to save settings: ", err)

func _load_settings() -> void:
	await get_tree().process_frame
	if not is_node_ready():
		return
	
	var config = ConfigFile.new()
	var err = config.load(SETTINGS_FILE_PATH)
	if err == OK:
		if sensitivity_slider: sensitivity_slider.value = config.get_value(SETTINGS_SECTION, "sensitivity", 1.0)
		if fov_slider: fov_slider.value = config.get_value(SETTINGS_SECTION, "fov", 75.0)
		if invert_y_toggle: invert_y_toggle.button_pressed = config.get_value(SETTINGS_SECTION, "invert_y", false)
		
		if master_volume_slider: master_volume_slider.value = config.get_value(SETTINGS_SECTION, "master_volume", 1.0)
		if effects_volume_slider: effects_volume_slider.value = config.get_value(SETTINGS_SECTION, "effects_volume", 1.0)
		if mute_toggle: mute_toggle.button_pressed = config.get_value(SETTINGS_SECTION, "mute", false)
		
		if vsync_toggle: vsync_toggle.button_pressed = config.get_value(SETTINGS_SECTION, "vsync", true)
		
		# Update fullscreen mode label to match current state (don't change window mode)
		if fullscreen_mode_label:
			_update_fullscreen_mode_label()
		
		if show_nametags_toggle: show_nametags_toggle.button_pressed = config.get_value(SETTINGS_SECTION, "show_nametags", true)
		
		# Apply immediately
		if sensitivity_slider: _on_sensitivity_changed(sensitivity_slider.value)
		if fov_slider: _on_fov_changed(fov_slider.value)
		if invert_y_toggle: _on_invert_y_toggled(invert_y_toggle.button_pressed)
		if master_volume_slider: _on_master_volume_changed(master_volume_slider.value)
		if effects_volume_slider: _on_effects_volume_changed(effects_volume_slider.value)
		if mute_toggle: _on_mute_toggled(mute_toggle.button_pressed)
		if vsync_toggle: _on_vsync_toggled(vsync_toggle.button_pressed)
		if show_nametags_toggle: _on_show_nametags_toggled(show_nametags_toggle.button_pressed)

# ── DPI Scaling ─────────────────────────────────────────────────────────────

func _apply_dpi_scaling() -> void:
	# Use get_viewport() which is more reliable in Godot 4.2+
	# This will ensure proper scaling based on viewport size
	pass  # Scaling is now handled by the scene layout itself

# Helper to find nodes recursively
func _find_node_by_type(node: Node, type_name: String) -> Node:
	if node.get_class() == type_name:
		return node
	for child in node.get_children():
		var found = _find_node_by_type(child, type_name)
		if found:
			return found
	return null

# Helper to collect all containers recursively
func _collect_containers(node: Node, containers: Array[Node]) -> void:
	if node is HBoxContainer or node is VBoxContainer:
		containers.append(node)
	
	for child in node.get_children():
		_collect_containers(child, containers)
