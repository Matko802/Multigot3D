# Multiplayer Setup Guide

## Overview
Your game now has full multiplayer support using Godot's built-in networking system (ENet). Players can host a game and others can join to play together with real-time synchronization.

## How It Works

### Components
1. **MultiplayerManager** (res://multiplayer_manager.gd)
   - Handles hosting and joining games
   - Manages player spawning
   - Tracks connected players

2. **MultiplayerController** (res://multiplayer_controller.gd)
   - The networked player controller
   - Syncs position and rotation every 0.1 seconds
   - Only allows input for the local player (authority)
   - Interpolates remote player positions for smooth movement

3. **MultiplayerUI** (res://multiplayer_ui.gd)
   - Menu to host or join a game
   - Displays player count during gameplay
   - Allows disconnecting

## Usage

### Hosting a Game
1. Start the game
2. Click "Host Game" button
3. Game will listen on port 9999 for incoming connections
4. Your player will spawn automatically

### Joining a Game
1. Start the game
2. Enter the server IP address (leave blank or type "localhost" for local testing)
3. Click "Join Game" button
4. Wait for connection to establish
5. Your player will spawn automatically

### Local Testing (Two Instances)
To test multiplayer locally:
1. Run the game normally (this becomes the server)
2. Click "Host Game"
3. Run the game again in another window/terminal
4. Click "Join Game" with IP = "localhost"
5. Both players should appear and can see each other move

## Network Synchronization

### Position & Rotation Sync
- **Rate**: Every 0.1 seconds (configurable via `sync_rate`)
- **Method**: RPC calls using `sync_transform`
- **Interpolation**: Client-side lerp for smooth movement
- **Threshold**: Only syncs if position changes > 0.1 units or rotation > 0.05 radians

### Player Spawning
- Server spawns all players at designated spawn points
- Spawned players are added to the "players" group
- Each player is assigned authority to themselves (ownership)

## Customization

### Change Port
Edit `multiplayer_manager.gd`:
```gdscript
const PORT: int = 9999  # Change this value
```

### Change Max Players
Edit `multiplayer_manager.gd`:
```gdscript
const MAX_PLAYERS: int = 4  # Change this value
```

### Change Sync Rate
Edit `multiplayer_controller.gd`:
```gdscript
@export var sync_rate: float = 0.1  # Lower = more frequent updates
```

### Add Spawn Points
Edit `multiplayer_manager.gd` in `spawn_player()` function:
```gdscript
var spawn_points := [
    Vector3(0, 5, -10),
    Vector3(10, 5, 0),
    # Add more spawn points here
]
```

## Debugging

Watch the console for connection messages:
- ✓ Server created
- ✓ Client connected
- ✓ Player spawned
- ✗ Connection errors

## Known Limitations
- No persistence (state resets on reconnection)
- No player names yet (can be added as a feature)
- Network bandwidth not optimized for very large player counts
- No voice chat or other advanced networking features

## Future Enhancements
Consider adding:
- Player names and identification
- Chat system
- Player health/damage
- Weapons and combat
- Dynamic spawn points
- Matchmaking system
- Server authentication
- Data persistence

## Troubleshooting

### "Connection failed!" error
- Check firewall settings (port 9999 may be blocked)
- Verify IP address is correct
- Ensure server is running first

### Other players not appearing
- Check network connectivity
- Verify both clients connected (check player count)
- Look at console for any error messages

### Stuttery movement
- Check network latency
- Adjust sync_rate (lower value = more updates but more bandwidth)
- Check for packet loss

## Technical Details

### Authority System
- Each player has authority over themselves
- Only the authority can process input
- Other clients see remote transforms via RPC sync

### RPC Methods Used
- `spawn_player()`: Spawned on all clients when players join
- `sync_transform()`: Called unreliably every 0.1s to update positions

### Network State
- Uses ENetMultiplayerPeer for reliable/unreliable communication
- Server is always peer ID 1
- Clients get unique peer IDs (2, 3, 4...)
- Players named "Player_<peer_id>"

Enjoy multiplayer!
