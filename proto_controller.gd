# ProtoController v1.0 by Brackeys
# CC0 License
# Intended for rapid prototyping of first-person games.
# Happy prototyping!

extends CharacterBody3D

## Can we move around?
@export var can_move : bool = true
## Are we affected by gravity?
@export var has_gravity : bool = true
## Can we press to jump?
@export var can_jump : bool = true
## Can we hold to run?
@export var can_sprint : bool = false
## Can we press to enter freefly mode (noclip)?
@export var can_freefly : bool = false

@export_group("Speeds")
## Look around rotation speed.
@export var look_speed : float = 0.0025
## Normal speed.
@export var base_speed : float = 7.0
## Speed of jump.
@export var jump_velocity : float = 4.5
## How fast do we run?
@export var sprint_speed : float = 10.0
## How fast do we freefly?
@export var freefly_speed : float = 25.0
## Acceleration/Deceleration
@export var acceleration : float = 35.0
@export var friction : float = 35.0

@export_group("Input Actions")
## Name of Input Action to move Left.
@export var input_left : String = "ui_left"
## Name of Input Action to move Right.
@export var input_right : String = "ui_right"
## Name of Input Action to move Forward.
@export var input_forward : String = "ui_up"
## Name of Input Action to move Backward.
@export var input_back : String = "ui_down"
## Name of Input Action to Jump.
@export var input_jump : String = "ui_accept"
## Name of Input Action to Sprint.
@export var input_sprint : String = "sprint"
## Name of Input Action to toggle freefly mode.
@export var input_freefly : String = "freefly"

var mouse_captured : bool = false
var look_rotation : Vector2
var move_speed : float = 0.0
var freeflying : bool = false

# Player name (replicated across network)
@export var player_name: String = "Player":
	set(value):
		player_name = value
		_update_name_label()

# Footstep variables
var footstep_timer : float = 0.0
var footstep_interval : float = 0.4
var footstep_sounds : Array[AudioStream] = []

## IMPORTANT REFERENCES
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var collider: CollisionShape3D = $Collider
@onready var step_audio: AudioStreamPlayer3D = $StepAudio
@onready var name_label_3d: Label3D = $NameLabel3D

var anim_player: AnimationPlayer
@export var sync_anim_state: String = "idle"

func _enter_tree() -> void:
	var id = str(name).to_int()
	if id > 0:
		set_multiplayer_authority(id)

func _ready() -> void:
	_load_footstep_sounds()
	
	# Set camera active only for local player
	if camera:
		camera.current = is_multiplayer_authority()
	
	# Local player visual adjustments
	if is_multiplayer_authority():
		var model = get_node_or_null("playermodel")
		if model:
			# Move model backward locally so camera is in front of face
			model.position.z = 0.462
		
		# Hide name label for self so it doesn't obstruct view
		if name_label_3d:
			name_label_3d.visible = false

	# Capture mouse automatically for our player
	if not multiplayer.has_multiplayer_peer() or is_multiplayer_authority():
		call_deferred("capture_mouse")
	
	check_input_mappings()
	_update_name_label()
	
	# Find AnimationPlayer
	var model = get_node_or_null("playermodel")
	if model:
		anim_player = _find_animation_player(model)
		if anim_player:
			if anim_player.has_animation("walking"):
				anim_player.get_animation("walking").loop_mode = Animation.LOOP_LINEAR
			if anim_player.has_animation("idle"):
				anim_player.get_animation("idle").loop_mode = Animation.LOOP_LINEAR

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var res = _find_animation_player(child)
		if res: return res
	return null

func _load_footstep_sounds() -> void:
	var paths = [
		"res://textures/Sounds/block_breaking/grass1.ogg",
		"res://textures/Sounds/block_breaking/grass2.ogg",
		"res://textures/Sounds/block_breaking/grass3.ogg",
		"res://textures/Sounds/block_breaking/grass4.ogg"
	]
	for path in paths:
		if ResourceLoader.exists(path):
			footstep_sounds.append(load(path))
		else:
			push_warning("Footstep sound not found: " + path)

func _process(delta: float) -> void:
	_process_footsteps(delta)
	
	# Authority determines state
	if is_multiplayer_authority():
		_update_anim_state()
	
	# Everyone plays animation based on state
	_apply_animation()

func _update_anim_state() -> void:
	# Use local velocity for authority
	var h_vel = Vector3(velocity.x, 0, velocity.z).length()
	
	if not is_on_floor():
		sync_anim_state = "jumping"
	elif h_vel > 0.1:
		sync_anim_state = "walking"
	else:
		sync_anim_state = "idle"

func _apply_animation() -> void:
	if not anim_player: return
	
	if sync_anim_state == "jumping":
		if anim_player.current_animation != "jumping":
			if anim_player.has_animation("jumping"):
				anim_player.play("jumping")
	elif sync_anim_state == "walking":
		if anim_player.current_animation != "walking":
			if anim_player.has_animation("walking"):
				anim_player.play("walking")
	else:
		# idle
		if anim_player.current_animation != "idle":
			if anim_player.has_animation("idle"):
				anim_player.play("idle")
			else:
				if anim_player.is_playing():
					anim_player.stop()

func _process_footsteps(delta: float) -> void:
	# Only authority processes footsteps to avoid double playback
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return
	
	if is_on_floor() and velocity.length() > 2.0:
		var current_interval = footstep_interval
		if velocity.length() > base_speed + 1.0:
			current_interval = footstep_interval * 0.7
		footstep_timer -= delta
		if footstep_timer <= 0:
			footstep_timer = current_interval
			if multiplayer.has_multiplayer_peer():
				_play_footstep_rpc.rpc()
			else:
				_play_footstep_rpc()
	else:
		footstep_timer = 0.05

@rpc("call_local", "reliable")
func _play_footstep_rpc() -> void:
	if footstep_sounds.is_empty() or not step_audio:
		print("[Player ", name, "] No sounds or audio player!")
		return
	var random_sound = footstep_sounds.pick_random()
	step_audio.stream = random_sound
	step_audio.pitch_scale = randf_range(0.9, 1.1)
	step_audio.volume_db = -10.0
	step_audio.play()
	print("[Player ", name, "] Playing footstep. Authority: ", is_multiplayer_authority())

func _input(event: InputEvent) -> void:
	# Only process input for the player we control (skip check if no multiplayer active)
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return
	
	# Look around
	if mouse_captured and event is InputEventMouseMotion:
		rotate_look(event.relative)

func _unhandled_input(event: InputEvent) -> void:
	# Only process input for the player we control (skip check if no multiplayer active)
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return
	
	# Mouse capturing
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			capture_mouse()
			
	if event is InputEventKey:
		if event.keycode == KEY_ESCAPE and event.pressed:
			release_mouse()
			
	# Toggle freefly mode
	if can_freefly and event.is_action_pressed(input_freefly):
		if not freeflying:
			enable_freefly()
		else:
			disable_freefly()

func _physics_process(delta: float) -> void:
	# Only process input for the player we control (skip check if no multiplayer active)
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return
	
	# If freeflying, handle freefly and nothing else
	if can_freefly and freeflying:
		var input_dir := Input.get_vector(input_left, input_right, input_forward, input_back)
		var motion := (head.global_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		motion *= freefly_speed * delta
		move_and_collide(motion)
		return
	
	# Apply gravity to velocity
	if has_gravity:
		if not is_on_floor():
			velocity += get_gravity() * delta

	# Apply jumping
	if can_jump:
		if Input.is_action_just_pressed(input_jump) and is_on_floor():
			velocity.y = jump_velocity

	# Modify speed based on sprinting
	if can_sprint and Input.is_action_pressed(input_sprint):
			move_speed = sprint_speed
	else:
		move_speed = base_speed

	# Apply desired movement to velocity
	if can_move:
		var input_dir := Input.get_vector(input_left, input_right, input_forward, input_back)
		var move_dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		
		# Instant movement (no smoothing)
		if move_dir:
			velocity.x = move_dir.x * move_speed
			velocity.z = move_dir.z * move_speed
		else:
			velocity.x = 0
			velocity.z = 0
	else:
		velocity.x = 0
		velocity.z = 0
	
	# Use velocity to actually move
	move_and_slide()


## Rotate us to look around.
## Base of controller rotates around y (left/right). Head rotates around x (up/down).
## Modifies look_rotation based on rot_input, then resets basis and rotates by look_rotation.
func rotate_look(rot_input : Vector2):
	# Only rotate if we have authority (or no multiplayer)
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return
	
	look_rotation.x -= rot_input.y * look_speed
	look_rotation.x = clamp(look_rotation.x, deg_to_rad(-85), deg_to_rad(85))
	look_rotation.y -= rot_input.x * look_speed
	transform.basis = Basis()
	rotate_y(look_rotation.y)
	head.transform.basis = Basis()
	head.rotate_x(look_rotation.x)


func enable_freefly():
	collider.disabled = true
	freeflying = true
	velocity = Vector3.ZERO

func disable_freefly():
	collider.disabled = false
	freeflying = false


func capture_mouse():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	mouse_captured = true


func release_mouse():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	mouse_captured = false


## Checks if some Input Actions haven't been created.
## Disables functionality accordingly.
## Update the name label above the player
func _update_name_label() -> void:
	if name_label_3d:
		name_label_3d.text = player_name

## Set the player's name (replicated via MultiplayerSynchronizer)
func set_player_name(new_name: String) -> void:
	if is_multiplayer_authority():
		player_name = new_name

func check_input_mappings():
	if can_move and not InputMap.has_action(input_left):
		push_error("Movement disabled. No InputAction found for input_left: " + input_left)
		can_move = false
	if can_move and not InputMap.has_action(input_right):
		push_error("Movement disabled. No InputAction found for input_right: " + input_right)
		can_move = false
	if can_move and not InputMap.has_action(input_forward):
		push_error("Movement disabled. No InputAction found for input_forward: " + input_forward)
		can_move = false
	if can_move and not InputMap.has_action(input_back):
		push_error("Movement disabled. No InputAction found for input_back: " + input_back)
		can_move = false
	if can_jump and not InputMap.has_action(input_jump):
		push_error("Jumping disabled. No InputAction found for input_jump: " + input_jump)
		can_jump = false
	if can_sprint and not InputMap.has_action(input_sprint):
		push_error("Sprinting disabled. No InputAction found for input_sprint: " + input_sprint)
		can_sprint = false
	if can_freefly and not InputMap.has_action(input_freefly):
		push_error("Freefly disabled. No InputAction found for input_freefly: " + input_freefly)
		can_freefly = false
