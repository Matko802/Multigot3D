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


# ── Lifecycle ───────────────────────────────────────────────────────────────

func _ready() -> void:
	_load_footstep_sounds()

	# Expose the footstep RPC so remote clients can hear steps
	GDSync.expose_func(_play_footstep_remote)

	# Wait one frame so GDSync owner metadata propagates from the server
	await get_tree().process_frame

	_is_local = GDSync.is_gdsync_owner(self)

	# Listen for ownership changes (e.g. if host migrates ownership)
	GDSync.connect_gdsync_owner_changed(self, _on_owner_changed)

	_setup_for_ownership()
	_update_name_label()
	_find_anim_player()


func _setup_for_ownership() -> void:
	if _is_local:
		# This is OUR player — enable camera, capture mouse, hide own name label
		if camera:
			camera.current = true
		if name_label_3d:
			name_label_3d.visible = false

		# Offset local model slightly so camera doesn't clip into it
		var local_model := get_node_or_null("playermodel")
		if local_model:
			local_model.position.z = 0.462

		call_deferred("capture_mouse")
	else:
		# Remote player — disable camera, show name label
		if camera:
			camera.current = false
		if name_label_3d:
			name_label_3d.visible = true


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
	look_rotation.x -= rot_input.y * look_speed
	look_rotation.x = clampf(look_rotation.x, deg_to_rad(-85.0), deg_to_rad(85.0))
	look_rotation.y -= rot_input.x * look_speed

	transform.basis = Basis()
	rotate_y(look_rotation.y)

	head.transform.basis = Basis()
	head.rotate_x(look_rotation.x)


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
