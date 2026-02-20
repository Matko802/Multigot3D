# Multiplayer Architecture

## System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         Main Scene                              │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ Scene Root (Node3D)                                        │ │
│  │  ├─ World Environment, Lights, CSG Geometry              │ │
│  │  ├─ MultiplayerManager (Node)                            │ │
│  │  │   ├─ MultiplayerSpawner                               │ │
│  │  │   │   └─ [Player instances spawn here]                │ │
│  │  │   └─ MultiplayerSynchronizer                          │ │
│  │  └─ MultiplayerUI (CanvasLayer)                          │ │
│  │       ├─ MainMenu (Control)                              │ │
│  │       └─ GameUI (Control)                                │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## Data Flow

### Hosting a Game

```
┌─────────────────────────────────────────────────────────────┐
│ Player clicks "Host Game"                                   │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│ MultiplayerUI._on_host_pressed()                            │
│ → multiplayer_manager.host_game()                           │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│ MultiplayerManager.host_game()                              │
│ ✓ Creates ENetMultiplayerPeer server (port 9999)           │
│ ✓ Sets as multiplayer.multiplayer_peer                     │
│ ✓ Calls spawn_player.rpc_id(1)                             │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│ spawn_player() RPC executes                                  │
│ ✓ Instantiates MultiplayerController scene                 │
│ ✓ Sets position to spawn point                             │
│ ✓ Sets multiplayer authority (ownership)                   │
│ ✓ Adds to MultiplayerSpawner                               │
│ ✓ Emits player_spawned signal                              │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│ Game Running                                                 │
│ ✓ Host player can move and look around                      │
│ ✓ Waiting for clients to join...                            │
└─────────────────────────────────────────────────────────────┘
```

### Joining a Game

```
┌─────────────────────────────────────────────────────────────┐
│ Player enters IP and clicks "Join Game"                     │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│ MultiplayerUI._on_join_pressed()                            │
│ → multiplayer_manager.join_game("192.168.1.100")           │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│ MultiplayerManager.join_game()                              │
│ ✓ Creates ENetMultiplayerPeer client                       │
│ ✓ Connects to server at given IP:PORT                      │
│ ✓ Sets as multiplayer.multiplayer_peer                     │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
        ┌────────┴────────┐
        │                 │
        ▼                 ▼
 ┌──────────────┐  ┌──────────────┐
 │ Connection   │  │  Connection  │
 │ Successful   │  │  Failed      │
 └──────┬───────┘  └──────┬───────┘
        │                 │
        ▼                 ▼
  ✓_on_connected    ✗_on_connection_failed
        │                 │
        ▼                 ▼
   [Proceed to       [Show error,
    spawn player]    retry joining]
        │
        ▼
┌─────────────────────────────────────────────────────────────┐
│ Server receives connection → _on_peer_connected()           │
│ ✓ Server calls spawn_player.rpc_id(new_peer_id)            │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│ Client receives spawn_player() call                          │
│ ✓ Instantiates own MultiplayerController                   │
│ ✓ Sets up as client-controlled player                      │
│ ✓ Ready to receive input from local keyboard/mouse         │
└─────────────────────────────────────────────────────────────┘
```

## Real-Time Synchronization

### Position/Rotation Sync Loop

```
Every Frame (60 FPS)
│
├─ [Authority Player Only]
│  │
│  ├─ _physics_process(delta)
│  │  ├─ Handle input
│  │  ├─ Update velocity
│  │  ├─ move_and_slide()
│  │  └─ Call handle_sync()
│  │
│  └─ handle_sync()
│     └─ Every 0.1 seconds:
│        ├─ Check if position/rotation changed enough
│        └─ If changed:
│           └─ sync_transform.rpc(position, look_rotation)
│
└─ [All Clients]
   │
   └─ sync_transform() RPC received (unreliable)
      ├─ If NOT authority:
      │  ├─ Lerp position (smooth interpolation)
      │  ├─ Update look_rotation
      │  └─ Update transform
      └─ If IS authority:
         └─ Ignore (already moved)
```

## Authority & Ownership System

```
┌──────────────────────────────────────────┐
│ Player 1 (Peer ID: 1 - Server)           │
│                                          │
│  ┌────────────────────────────────────┐ │
│  │ MultiplayerController (Player_1)   │ │
│  │ ├─ Authority: 1 (owns itself)      │ │
│  │ ├─ can_move: true                  │ │
│  │ ├─ Receives input: YES             │ │
│  │ └─ Updates position locally: YES   │ │
│  └────────────────────────────────────┘ │
│                                          │
│  ┌────────────────────────────────────┐ │
│  │ MultiplayerController (Player_2)   │ │
│  │ ├─ Authority: 2 (owned by client)  │ │
│  │ ├─ can_move: false                 │ │
│  │ ├─ Receives input: NO (disabled)   │ │
│  │ └─ Updates from RPC: YES           │ │
│  └────────────────────────────────────┘ │
│                                          │
└──────────────────────────────────────────┘

┌──────────────────────────────────────────┐
│ Player 2 (Peer ID: 2 - Client)           │
│                                          │
│  ┌────────────────────────────────────┐ │
│  │ MultiplayerController (Player_1)   │ │
│  │ ├─ Authority: 1 (owned by server)  │ │
│  │ ├─ can_move: false                 │ │
│  │ ├─ Receives input: NO (disabled)   │ │
│  │ └─ Updates from RPC: YES           │ │
│  └────────────────────────────────────┘ │
│                                          │
│  ┌────────────────────────────────────┐ │
│  │ MultiplayerController (Player_2)   │ │
│  │ ├─ Authority: 2 (owns itself)      │ │
│  │ ├─ can_move: true                  │ │
│  │ ├─ Receives input: YES             │ │
│  │ └─ Updates position locally: YES   │ │
│  └────────────────────────────────────┘ │
│                                          │
└──────────────────────────────────────────┘
```

## Network Communication Protocol

### RPC Messages

#### spawn_player()
```
Direction:  Server → All Clients
Reliability: Reliable
Parameters: None
Effect:     Instantiate player controller on all clients
Ownership:  Set by server to requesting peer
```

#### sync_transform(position, look_rotation)
```
Direction:  Authority → All Other Clients  
Reliability: Unreliable (fast, may drop)
Parameters: Vector3 position, Vector2 look_rotation
Frequency:  ~10 Hz (every 0.1 seconds)
Throttle:   Only sends if position change > 0.1 or rotation > 0.05
Effect:     Remote clients interpolate to new position/rotation
```

### Built-in Signals

```
multiplayer.peer_connected(peer_id)
└─ Fired when new player connects to server
   Action: spawn_player.rpc_id(peer_id)

multiplayer.peer_disconnected(peer_id)
└─ Fired when player leaves
   Action: Find and remove player node

multiplayer.connected_to_server()
└─ Fired when client connects to server
   Action: Request spawn via rpc()

multiplayer.connection_failed()
└─ Fired when client fails to connect
   Action: Show error, allow retry

multiplayer.server_disconnected()
└─ Fired when server closes connection
   Action: End game, return to menu
```

## Performance Characteristics

### Bandwidth Usage (per player, per second)
```
sync_transform (unreliable RPC):
├─ Position (Vector3): 12 bytes
├─ Look Rotation (Vector2): 8 bytes
├─ RPC header: ~20 bytes
├─ Frequency: 10 Hz (0.1s)
└─ Total: ~400 bytes/sec per player

Each additional connected player:
├─ Outgoing: +400 bytes/sec
└─ Incoming: +400 bytes/sec

Example with 4 players:
├─ Total upstream: ~1,200 bytes/sec (9.6 kbps)
└─ Total downstream: ~1,200 bytes/sec (9.6 kbps)
```

### Latency Impact
```
Network Latency → Interpolation Time → Smooth Movement

Low Latency (< 50ms):
├─ Sync arrives very quickly
├─ Lerp has short distance
└─ Smooth, responsive movement

High Latency (100-200ms):
├─ Sync arrives slower
├─ Lerp covers larger distance
└─ Noticeable but playable delay

Very High Latency (> 500ms):
├─ Jerky movement between updates
├─ Players appear to teleport
└─ Consider increasing sync_rate
```

## Scene Hierarchy at Runtime

### After 2 Players Connected

```
Main (Node3D)
├─ WorldEnvironment
├─ DirectionalLight3D
├─ CSGCombiner3D (World Geometry)
├─ AudioStreamPlayer3D (x2)
├─ MultiplayerManager (Node)
│  ├─ MultiplayerSpawner
│  │  ├─ Player_1 (CharacterBody3D) ← Me (Authority)
│  │  │  ├─ Mesh (visible)
│  │  │  ├─ Collider (active)
│  │  │  └─ Head
│  │  │     └─ Camera3D (controls view)
│  │  │
│  │  └─ Player_2 (CharacterBody3D) ← Other Player
│  │     ├─ Mesh (visible)
│  │     ├─ Collider (collision only)
│  │     └─ Head (rotates with RPC updates)
│  │        └─ Camera3D (disabled)
│  │
│  └─ MultiplayerSynchronizer
│
└─ MultiplayerUI (CanvasLayer)
   ├─ MainMenu (hidden)
   └─ GameUI (visible)
      └─ VBoxContainer
         ├─ PlayerCountLabel ("Players: 2")
         └─ DisconnectButton
```

## Connection States

```
┌─────────────────────────────────────────┐
│ Host State Machine                      │
├─────────────────────────────────────────┤
│                                         │
│  DISCONNECTED                           │
│      │                                  │
│      │ click "Host Game"                │
│      ▼                                  │
│  HOSTING → (waiting for clients)        │
│      │                                  │
│      ├─ Client connects                 │
│      │  └─ Spawn Player                │
│      │                                  │
│      └─ click "Disconnect"              │
│         └─ back to DISCONNECTED         │
│                                         │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│ Client State Machine                    │
├─────────────────────────────────────────┤
│                                         │
│  DISCONNECTED                           │
│      │                                  │
│      │ click "Join Game"                │
│      ▼                                  │
│  CONNECTING (waiting for server)        │
│      │                                  │
│      ├─ Connection Success              │
│      │  └─ CONNECTED → Spawn Player    │
│      │                                  │
│      └─ Connection Failed               │
│         └─ back to DISCONNECTED         │
│                                         │
│ OR click "Disconnect" anytime           │
│    └─ back to DISCONNECTED             │
│                                         │
└─────────────────────────────────────────┘
```

---

This architecture ensures:
✓ **Scalability** - Easily add more players
✓ **Responsiveness** - Only authority processes input
✓ **Smoothness** - Lerp interpolation between updates
✓ **Efficiency** - Only syncs when needed, uses unreliable RPC
✓ **Reliability** - Important messages (spawn) are guaranteed delivery
