class_name ProtoController
extends CharacterBody3D

## First-person character controller with GD-Sync multiplayer support.
## Ownership is determined by GDSync.is_gdsync_owner(self).
## PropertySynchronizer (child node) handles syncing position, rotation, player_name, sync_anim_state.

# ── Exports ─────────────────────────────────────────────────────────────────

@export var can_move: bool = true
@export var has_gravity: bool = true
@export var can_jump: bool = true
@export var can_sprint: bool = false
@export var can_freefly: bool = false

@export_group("Speeds")
@export var look_speed: float = 0.0025
@export var base_speed: float = 7.0
@export var jump_velocity: float = 4.5
@export var sprint_speed: float = 10.0
@export var freefly_speed: float = 25.0

@export_group("Input Actions")
@export var input_left: String = "move_left"
@export var input_right: String = "move_right"
@export var input_forward: String = "move_foward"
@export var input_back: String = "move_backward"
@export var input_jump: String = "jump"
@export var input_sprint: String = "sprint"
@export var input_freefly: String = "freefly"

# Synced via PropertySynchronizer
@export var player_name: String = "Player":
	set(value):
		player_name = value
		_update_name_label()

@export var sync_anim_state: String = "idle"
@export var sync_head_tilt: float = 0.0:
	set(value):
		sync_head_tilt = value
		if is_node_ready() and head:
			var head_basis := head.transform.basis
			head_basis = Basis.IDENTITY
			head_basis = head_basis.rotated(Vector3.RIGHT, value)
			head.transform.basis = head_basis




# ── Internal State ──────────────────────────────────────────────────────────

var mouse_captured: bool = false
var look_rotation: Vector2 = Vector2.ZERO
var move_speed: float = 0.0
var freeflying: bool = false
var _is_local: bool = false

# Footstep
var footstep_timer: float = 0.0
var footstep_interval: float = 0.4
var footstep_sounds: Array[AudioStream] = []

# ── Node References ─────────────────────────────────────────────────────────

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var collider: CollisionShape3D = $Collider
@onready var step_audio: AudioStreamPlayer3D = $StepAudio
@onready var name_label_3d: Label3D = $NameLabel3D

var anim_player: AnimationPlayer
var playermodel: Node3D
var skeleton: Skeleton3D
var head_bone_idx: int = -1

# Settings
var sensitivity_modifier: float = 1.0
var invert_y: bool = false
const SETTINGS_FILE_PATH: String = "user://game_settings.cfg"

# ── Lifecycle ───────────────────────────────────────────────────────────────

func _ready() -> void:
	add_to_group("player_controllers")
	_load_settings()
	_load_footstep_sounds()

	# Check if we're in singleplayer mode
	var is_singleplayer_mode: bool = has_meta("singleplayer")

	# Only use GDSync features if NOT in singleplayer mode
	if not is_singleplayer_mode:
		# Expose the footstep RPC so remote clients can hear steps
		GDSync.expose_func(_play_footstep_remote)

		# Wait one frame so GDSync owner metadata propagates from the server
		await get_tree().process_frame

		_is_local = GDSync.is_gdsync_owner(self)

		# Listen for ownership changes (e.g. if host migrates ownership)
		GDSync.connect_gdsync_owner_changed(self, _on_owner_changed)
	else:
		# In singleplayer mode, we are always the local player
		_is_local = true

	_setup_for_ownership()
	_update_name_label()
	_find_anim_player()
	
	var model := get_node_or_null("playermodel")
	if model:
		skeleton = _find_skeleton(model)
		if skeleton:
			head_bone_idx = _find_head_bone_index(skeleton)
	
	# Ensure we process after animations to override head bone
	process_priority = 100
	
	# Apply loaded settings
	apply_loaded_settings()

func apply_loaded_settings() -> void:
	var config = ConfigFile.new()
	var err = config.load(SETTINGS_FILE_PATH)
	if err == OK:
		# These are usually applied by the settings menu when it loads, 
		# but if we spawn late, we need to grab them.
		if config.has_section("settings"):
			update_sensitivity(config.get_value("settings", "sensitivity", 1.0))
			update_invert_y(config.get_value("settings", "invert_y", false))
			update_fov(config.get_value("settings", "fov", 75.0))
			update_base_speed(config.get_value("settings", "speed", 7.0))
			# Nametags are updated via group call usually, but we can check
			var show_tags = config.get_value("settings", "show_nametags", true)
			update_nametags_visibility(show_tags)


func _setup_for_ownership() -> void:
	var local_model := get_node_or_null("playermodel")

	if _is_local:
		# This is OUR player — enable camera, capture mouse, hide own name label
		if camera:
			camera.current = true
		if name_label_3d:
			name_label_3d.visible = false

		# Hide player model but keep shadows for local player
		if local_model:
			_set_meshes_shadow_only(local_model, true)

		call_deferred("capture_mouse")
	else:
		# Remote player — disable camera, show name label
		if camera:
			camera.current = false
		if name_label_3d:
			name_label_3d.visible = true
		
		# Ensure model is fully visible for remote players
		if local_model:
			_set_meshes_shadow_only(local_model, false)


func _set_meshes_shadow_only(node: Node, enable: bool) -> void:
	if node is MeshInstance3D:
		if enable:
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		else:
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	
	for child in node.get_children():
		_set_meshes_shadow_only(child, enable)


func _on_owner_changed(new_owner: int) -> void:
	_is_local = (new_owner == GDSync.get_client_id())
	_setup_for_ownership()


# ── Animation ───────────────────────────────────────────────────────────────




func _find_anim_player() -> void:
	var model := get_node_or_null("playermodel")
	if model:
		anim_player = _search_animation_player(model)
		if anim_player:
			for anim_name: String in ["walking", "idle"]:
				if anim_player.has_animation(anim_name):
					anim_player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR


func _search_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result := _search_animation_player(child)
		if result:
			return result
	return null

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var result := _find_skeleton(child)
		if result:
			return result
	return null

func _find_head_bone_index(skel: Skeleton3D) -> int:
	# Try exact names
	var names = ["Head", "head", "Neck", "neck"]
	for n in names:
		var idx = skel.find_bone(n)
		if idx != -1: return idx
	
	# Try fuzzy match
	for i in skel.get_bone_count():
		var b_name = skel.get_bone_name(i)
		if "Head" in b_name or "head" in b_name:
			return i
	return -1

func _update_head_bone() -> void:
	if not skeleton or head_bone_idx == -1:
		return
	
	# Get the pose set by animation
	var current_rot = skeleton.get_bone_pose_rotation(head_bone_idx)
	
	# Apply tilt (pitch around X axis)
	var tilt = Quaternion(Vector3.RIGHT, sync_head_tilt)
	
	# Apply rotation
	skeleton.set_bone_pose_rotation(head_bone_idx, current_rot * tilt)


func _update_anim_state() -> void:
	var h_speed := Vector3(velocity.x, 0.0, velocity.z).length()
	if not is_on_floor():
		sync_anim_state = "jumping"
	elif h_speed > 0.1:
		sync_anim_state = "walking"
	else:
		sync_anim_state = "idle"


func _apply_animation() -> void:
	if not anim_player:
		return
	var target_anim: String = sync_anim_state
	if anim_player.current_animation != target_anim:
		if anim_player.has_animation(target_anim):
			anim_player.play(target_anim)
		elif target_anim == "idle" and anim_player.is_playing():
			anim_player.stop()





# ── Process ─────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _is_local:
		_update_anim_state()
		_process_footsteps(delta)
	_apply_animation()
	_update_head_bone()





func _physics_process(delta: float) -> void:
	if not _is_local:
		return

	# Freefly mode
	if can_freefly and freeflying:
		var input_dir := Input.get_vector(input_left, input_right, input_forward, input_back)
		var motion := (head.global_basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
		move_and_collide(motion * freefly_speed * delta)
		return

	# Gravity
	if has_gravity and not is_on_floor():
		velocity += get_gravity() * delta

	# Jump
	if can_jump and Input.is_action_just_pressed(input_jump) and is_on_floor():
		velocity.y = jump_velocity

	# Sprint
	if can_sprint and Input.is_action_pressed(input_sprint):
		move_speed = sprint_speed
	else:
		move_speed = base_speed

	# Movement
	if can_move:
		var input_dir := Input.get_vector(input_left, input_right, input_forward, input_back)
		var move_dir := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
		if move_dir.length() > 0.01:
			velocity.x = move_dir.x * move_speed
			velocity.z = move_dir.z * move_speed
		else:
			velocity.x = 0.0
			velocity.z = 0.0
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	move_and_slide()


# ── Input ───────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not _is_local:
		return
	if mouse_captured and event is InputEventMouseMotion:
		_rotate_look(event.relative)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_local:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			capture_mouse()

	if event is InputEventKey:
		if event.keycode == KEY_ESCAPE and event.pressed:
			release_mouse()

	if can_freefly and event.is_action_pressed(input_freefly):
		freeflying = not freeflying
		collider.disabled = freeflying
		if freeflying:
			velocity = Vector3.ZERO


# ── Look ────────────────────────────────────────────────────────────────────

func _rotate_look(rot_input: Vector2) -> void:
	var effective_look_speed = look_speed * sensitivity_modifier
	var y_input = rot_input.y
	if invert_y:
		y_input = -y_input
		
	look_rotation.x -= y_input * effective_look_speed
	look_rotation.x = clampf(look_rotation.x, deg_to_rad(-85.0), deg_to_rad(85.0))
	look_rotation.y -= rot_input.x * effective_look_speed

	transform.basis = Basis.IDENTITY
	rotate_y(look_rotation.y)

	head.transform.basis = Basis.IDENTITY
	head.rotate_x(look_rotation.x)
	
	# Sync head tilt across network
	sync_head_tilt = look_rotation.x


# ── Mouse ───────────────────────────────────────────────────────────────────

func capture_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	mouse_captured = true


func release_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	mouse_captured = false


# ── Footsteps ─────────────────────────────────────��─────────────────────────

func _load_footstep_sounds() -> void:
	var paths: Array[String] = [
		"res://textures/Sounds/block_breaking/grass1.ogg",
		"res://textures/Sounds/block_breaking/grass2.ogg",
		"res://textures/Sounds/block_breaking/grass3.ogg",
		"res://textures/Sounds/block_breaking/grass4.ogg",
	]
	for path: String in paths:
		if ResourceLoader.exists(path):
			footstep_sounds.append(load(path))


func _process_footsteps(delta: float) -> void:
	if is_on_floor() and velocity.length() > 2.0:
		var interval := footstep_interval
		if velocity.length() > base_speed + 1.0:
			interval *= 0.7
		footstep_timer -= delta
		if footstep_timer <= 0.0:
			footstep_timer = interval
			# Play locally and send to remotes
			_play_footstep_local()
			# Only send remote footstep in multiplayer mode
			if GDSync.is_active():
				GDSync.call_func(_play_footstep_remote)
	else:
		footstep_timer = 0.05


func _play_footstep_local() -> void:
	if footstep_sounds.is_empty() or not step_audio:
		return
	step_audio.stream = footstep_sounds.pick_random()
	step_audio.pitch_scale = randf_range(0.9, 1.1)
	step_audio.volume_db = -10.0
	step_audio.play()


func _play_footstep_remote() -> void:
	_play_footstep_local()


# ── Name Label ──────────────────────────────────────────────────────────────

func _update_name_label() -> void:
	if name_label_3d:
		name_label_3d.text = player_name

func update_sensitivity(value: float) -> void:
	sensitivity_modifier = value

func update_invert_y(value: bool) -> void:
	invert_y = value

func update_fov(value: float) -> void:
	if camera:
		camera.fov = value

func update_base_speed(value: float) -> void:
	base_speed = value

func update_nametags_visibility(value: bool) -> void:
	# Local player always hides own nametag (handled in _setup_for_ownership)
	# This setting controls seeing OTHER players' nametags.
	if not _is_local and name_label_3d:
		name_label_3d.visible = value

func _load_settings() -> void:
	var config = ConfigFile.new()
	var err = config.load(SETTINGS_FILE_PATH)
	if err == OK:
		sensitivity_modifier = config.get_value("settings", "sensitivity", 1.0)
