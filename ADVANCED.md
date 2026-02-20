# Advanced Multiplayer Topics

## Performance Tuning

### Network Sync Rate

The frequency at which players sync their position to others. Default is 0.1 seconds (10 updates/sec).

```gdscript
# In multiplayer_controller.gd
@export var sync_rate: float = 0.1

# Presets:
# 0.033 → 30 updates/sec (very responsive but high bandwidth)
# 0.05  → 20 updates/sec (balanced)
# 0.1   → 10 updates/sec (default, good for most games)
# 0.2   → 5 updates/sec (low bandwidth, more noticeable lag)
```

**Impact:**
- Lower sync_rate = more responsive but more bandwidth
- Higher sync_rate = less bandwidth but more noticeable latency
- Good sweet spot: 0.05-0.1 for most games

### Interpolation Smoothness

The speed at which remote players smoothly move to their new position.

```gdscript
# In multiplayer_controller.gd, sync_transform()
global_position = global_position.lerp(new_position, 0.3)

# The 0.3 is the interpolation factor
# 0.3 = 30% of the way to new position each sync
# 
# Adjust based on:
# - Higher value (0.5+) = snappier but might be jerky
# - Lower value (0.1-0.2) = smoother but slower to reach target
```

### Sync Threshold

Only sends position/rotation if change exceeds threshold (saves bandwidth).

```gdscript
# In multiplayer_controller.gd, handle_sync()

# Current thresholds:
if global_position.distance_to(last_synced_position) > 0.1 or \
   abs(look_rotation.x - last_synced_rotation.x) > 0.05 or \
   abs(look_rotation.y - last_synced_rotation.y) > 0.05:
    sync_transform.rpc(...)

# Adjust these values:
# 0.1 position, 0.05 rotation = default (good balance)
# 0.05 position, 0.02 rotation = sync more often (more responsive)
# 0.2 position, 0.1 rotation = sync less often (saves bandwidth)
```

## Adding Features

### Player Names

```gdscript
# 1. Modify MultiplayerController to store name
class_name MultiplayerController
extends CharacterBody3D

@export var player_name: String = "Player"

# 2. Modify spawn_player in multiplayer_manager.gd
@rpc("reliable", "call_local")
func spawn_player(name: String = "") -> void:
    if not is_server:
        return
    
    var player := player_scene.instantiate() as MultiplayerController
    player.name = "Player_%d" % multiplayer.get_unique_id()
    player.player_name = name if name else "Player_%d" % multiplayer.get_unique_id()
    # ... rest of spawn code
    
    # Sync name to all clients
    update_player_name.rpc(player.name, player.player_name)

@rpc
func update_player_name(node_name: String, display_name: String) -> void:
    var player = get_tree().root.find_child(node_name, true, false)
    if player:
        player.player_name = display_name

# 3. Update UI to show names
# Add Label3D above each player showing their name
```

### Health System

```gdscript
# In multiplayer_controller.gd
extends CharacterBody3D

const MAX_HEALTH: int = 100
var health: int = MAX_HEALTH

signal health_changed(old_health: int, new_health: int)

func take_damage(amount: int) -> void:
    if not is_multiplayer_authority():
        return
    
    var old_health = health
    health = max(0, health - amount)
    
    if health != old_health:
        sync_health.rpc(health)
        health_changed.emit(old_health, health)

@rpc
func sync_health(new_health: int) -> void:
    health = new_health

func die() -> void:
    if not is_multiplayer_authority():
        return
    
    # Hide player, disable collision
    visible = false
    collider.disabled = true
    
    # After 3 seconds, respawn
    await get_tree().create_timer(3.0).timeout
    respawn()

func respawn() -> void:
    health = MAX_HEALTH
    visible = true
    collider.disabled = false
    global_position = get_spawn_point()  # Implement get_spawn_point()
```

### Chat System

```gdscript
# Create chat_system.gd
class_name ChatSystem
extends CanvasLayer

var messages: Array[String] = []
const MAX_MESSAGES: int = 10

@onready var chat_label: Label = $VBoxContainer/ChatLabel
@onready var input_field: LineEdit = $VBoxContainer/InputField

func _ready() -> void:
    input_field.text_submitted.connect(_on_message_submitted)

func _on_message_submitted(text: String) -> void:
    if text.is_empty():
        return
    
    # Get player name
    var root = get_tree().root.get_child(0)
    var player = root.find_child("Player_%d" % multiplayer.get_unique_id())
    var player_name = player.player_name if player else "Unknown"
    
    # Send message to all players
    add_message.rpc(player_name, text)
    input_field.clear()

@rpc
func add_message(player_name: String, text: String) -> void:
    messages.append("[%s] %s" % [player_name, text])
    
    # Keep only last 10 messages
    if messages.size() > MAX_MESSAGES:
        messages.pop_front()
    
    # Update display
    chat_label.text = "\n".join(messages)
```

### Player List / Lobby

```gdscript
# Add to MultiplayerManager
class_name MultiplayerManager
extends Node

var players_info: Dictionary = {}  # peer_id -> player_data

func _on_peer_connected(peer_id: int) -> void:
    print("Peer connected: ", peer_id)
    if is_server:
        spawn_player.rpc_id(peer_id)
        update_player_list.rpc()

func _on_peer_disconnected(peer_id: int) -> void:
    print("Peer disconnected: ", peer_id)
    if peer_id in players_info:
        players_info.erase(peer_id)
    update_player_list.rpc()

@rpc
func update_player_list() -> void:
    var player_count = get_tree().get_nodes_in_group("players").size()
    print("Players connected: ", player_count)
    # Update UI with current player list
```

## Debugging Network Issues

### Enable Debug Output

```gdscript
# Add to MultiplayerManager._ready()

# Enable network debug logging
multiplayer.debug_peer_packets = true

# Create custom log function
func log_network_event(message: String) -> void:
    print("[NETWORK] ", message)
    # Can also write to file for later analysis
```

### Monitor Bandwidth

```gdscript
# Track sync messages
var sync_count: int = 0
var sync_bytes: int = 0

@rpc("unreliable")
func sync_transform(new_position: Vector3, new_look_rotation: Vector2) -> void:
    sync_count += 1
    sync_bytes += 20  # Approximate size
    
    if is_multiplayer_authority():
        return
    
    global_position = global_position.lerp(new_position, 0.3)
    # ... rest of sync

func print_bandwidth_stats() -> void:
    var bytes_per_sec = sync_bytes
    var mbps = (bytes_per_sec * 8.0) / 1_000_000.0
    print("Syncs: ", sync_count, " | Bandwidth: ", bytes_per_sec, " bytes/s | ", mbps, " Mbps")
    sync_count = 0
    sync_bytes = 0
```

### Check Latency

```gdscript
# In multiplayer_controller.gd
var ping_time: float = 0.0

func calculate_ping() -> void:
    ping_time = Time.get_ticks_msec()
    ping_request.rpc_id(1)  # Send to server

@rpc
func ping_request() -> void:
    if is_multiplayer_authority():
        ping_response.rpc_id(multiplayer.get_remote_sender_id())

@rpc
func ping_response() -> void:
    var latency_ms = Time.get_ticks_msec() - ping_time
    print("Latency: ", latency_ms, "ms")
```

## Optimizations

### Only Sync When Moving

```gdscript
# Enhanced sync logic
var last_position: Vector3
var is_moving: bool = false

func _physics_process(delta: float) -> void:
    # ... normal physics
    move_and_slide()
    
    # Check if actually moving
    is_moving = global_position.distance_to(last_position) > 0.01
    last_position = global_position
    
    if is_moving:
        handle_sync()

func handle_sync() -> void:
    if not is_moving:
        return  # Don't sync if not moving
    
    # Only sync if enough time has passed
    sync_timer += get_physics_process_delta_time()
    if sync_timer >= sync_rate:
        sync_timer = 0.0
        sync_transform.rpc(global_position, look_rotation)
```

### Batch Sync Data

Instead of separate syncs, combine multiple values:

```gdscript
@rpc("unreliable")
func sync_full_state(position: Vector3, look_rotation: Vector2, velocity: Vector3, is_jumping: bool) -> void:
    if is_multiplayer_authority():
        return
    
    global_position = global_position.lerp(position, 0.3)
    # ... other updates
    
    # This sends once instead of multiple RPC calls
```

## Security Considerations

### Input Validation

Always validate input on server before accepting it:

```gdscript
@rpc
func take_damage(amount: int) -> void:
    # Only server should process damage
    if not is_server:
        return
    
    # Validate damage amount
    if amount < 0 or amount > 100:
        print("Invalid damage amount: ", amount)
        return
    
    # Apply damage
    health -= amount
```

### Prevent Cheating

```gdscript
# Don't trust client for position
# Only accept input locally
func _physics_process(delta: float) -> void:
    if is_multiplayer_authority():
        # Process movement locally
        process_movement()
        handle_sync()  # Tell others where we are

# Server validates damage
@rpc
func request_attack(target_id: int, damage: int) -> void:
    if not is_server:
        return
    
    # Validate:
    # 1. Is attacker still alive?
    # 2. Is target in range?
    # 3. Did they have a weapon?
    # 4. Is damage amount reasonable?
    
    if validate_attack(target_id, damage):
        target.take_damage(damage)
```

## Testing Strategies

### Local Network Testing

```bash
# Terminal 1 - Server
godot --path=. &

# Terminal 2 - Client
GODOT_OVERRIDE_PEERS=localhost:9999 godot --path=. &
```

### Automated Testing

```gdscript
# test_multiplayer.gd
extends Node

func test_host_game() -> void:
    var manager = get_node("Main/MultiplayerManager")
    manager.host_game()
    
    await get_tree().create_timer(0.1).timeout
    assert(manager.is_server)
    print("✓ Host game test passed")

func test_player_spawn() -> void:
    var players = get_tree().get_nodes_in_group("players")
    assert(players.size() > 0)
    print("✓ Player spawn test passed")

func test_position_sync() -> void:
    var player = get_tree().get_nodes_in_group("players")[0]
    var initial_pos = player.global_position
    
    player.global_position = Vector3(10, 5, 10)
    await get_tree().create_timer(0.2).timeout
    
    assert(player.global_position != initial_pos)
    print("✓ Position sync test passed")
```

## Server Best Practices

### Server-Side Game Logic

Keep important logic on the server:
- Health/Damage calculations
- Resource/Item management
- World state changes
- Score/Win conditions

```gdscript
# Bad - client decides its own health
func take_damage(amount: int) -> void:
    health -= amount  # Cheatable!

# Good - server decides health
@rpc
func request_take_damage(attacker_id: int, amount: int) -> void:
    if not is_server:
        return
    
    # Validate attack
    var attacker = get_player(attacker_id)
    if is_in_range(attacker, self):
        health -= amount
        update_health.rpc_id(multiplayer.get_unique_id(), health)
```

### Graceful Degradation

Handle disconnections smoothly:

```gdscript
func _on_peer_disconnected(peer_id: int) -> void:
    # Find and remove player
    var player_name = "Player_%d" % peer_id
    var player = get_tree().root.find_child(player_name, true, false)
    if player:
        player.queue_free()
    
    # Update all clients
    remove_player.rpc(peer_id)

@rpc
func remove_player(peer_id: int) -> void:
    var player_name = "Player_%d" % peer_id
    var player = get_tree().root.find_child(player_name, true, false)
    if player:
        player.queue_free()
```

---

**Next Steps:**
- Implement health system for combat
- Add chat for player communication
- Optimize sync rates for your game's needs
- Test with real network conditions
- Monitor bandwidth and latency

Good luck with your multiplayer game! 🎮
