# Multiplayer Quick Start

## What Was Added

✅ **Complete multiplayer networking system** using Godot 4.6's built-in ENet
✅ **Player spawner** that creates networked player instances
✅ **Automatic synchronization** of player positions and rotations
✅ **Host/Join UI** with menus for starting games
✅ **Smooth interpolation** of remote player movement
✅ **Proper authority handling** - only you can control your own player

## Files Created/Modified

### New Files
1. **multiplayer_manager.gd** - Game session manager (host/join/spawning)
2. **multiplayer_controller.gd** - Networked player controller
3. **multiplayer_ui.gd** - Host/Join menu system
4. **multiplayer_ui.tscn** - UI scene for menus
5. **multiplayer_controller.tscn** - Player scene (uses new controller)
6. **MULTIPLAYER_GUIDE.md** - Detailed documentation
7. **MULTIPLAYER_QUICK_START.md** - This file!

### Modified Files
- **main.tscn** - Added MultiplayerManager and MultiplayerUI nodes

## How to Play

### Single Machine (2 Instances)
```bash
# Terminal 1 - Start game (becomes server)
# Click "Host Game"

# Terminal 2 - Start another instance
# Click "Join Game" → "localhost" → "Join Game"
```

### Network Play
```bash
# Server Machine
# Click "Host Game"
# Share your IP address

# Client Machine  
# Enter server's IP address
# Click "Join Game"
```

## Key Features

### 🎮 Player Control
- **Only your player responds to your input** (authority system)
- Other players are controlled by their own clients
- Your mouse/keyboard only affects your character

### 📡 Network Sync
- Position updates: Every 0.1 seconds (10 updates/sec)
- Smooth interpolation between updates
- Only sends data when player actually moves
- Uses unreliable RPC (fast, minimal overhead)

### 👥 Player Spawning
- Server spawns all players automatically
- 4 default spawn points (easily customizable)
- Each player gets unique ID and name
- Players tracked in "players" group

### 🎨 UI System
- Simple menu to host or join
- Live player count display
- Disconnect button to leave game

## Customization Examples

### Change Port (default: 9999)
Edit `multiplayer_manager.gd`:
```gdscript
const PORT: int = 9999
```

### Increase Max Players (default: 4)
Edit `multiplayer_manager.gd`:
```gdscript
const MAX_PLAYERS: int = 8
```

### Make Sync Faster/Slower (default: 0.1)
Edit `multiplayer_controller.gd`:
```gdscript
@export var sync_rate: float = 0.05  # More frequent (0.05 = 20 updates/sec)
```

### Add Custom Spawn Points
Edit `multiplayer_manager.gd` in `spawn_player()`:
```gdscript
var spawn_points := [
    Vector3(0, 5, -10),
    Vector3(10, 5, 0),
    Vector3(-10, 5, 0),
    Vector3(0, 5, 10),
    Vector3(20, 5, 20),  # Add more!
]
```

## Testing Tips

✓ Test locally first (host + join on same machine)
✓ Check console output for ✓/✗ connection messages
✓ Use "Players: X" display to confirm connected
✓ Try moving around - should see other players move
✓ Check firewall if port 9999 is blocked

## What's NOT Included (Future Enhancements)

- [ ] Player names visible above characters
- [ ] Chat system
- [ ] Combat/Damage system
- [ ] Item/Block interaction
- [ ] Voice chat
- [ ] Persistent world data
- [ ] Advanced physics replication

## Common Issues

**"Connection failed!" error**
→ Check firewall (may need to allow port 9999)
→ Verify IP address is correct
→ Make sure server started first

**Other players not visible**
→ Check "Players: X" count - should show all connected
→ Look at console for errors
→ Verify network connectivity

**Stuttering/Lag**
→ Normal with network latency
→ Adjust sync_rate if needed
→ Check network ping

## API Reference

### MultiplayerManager

```gdscript
# Start hosting
multiplayer_manager.host_game()

# Join a game
multiplayer_manager.join_game("192.168.1.100")  # IP or "localhost"

# Get all players
var players = multiplayer_manager.get_all_players()

# Signals
multiplayer_manager.player_spawned.connect(func(player): print(player.name))
multiplayer_manager.player_disconnected.connect(func(peer_id): print("Left: ", peer_id))
```

### MultiplayerController

```gdscript
# Check if this is YOUR player
if player.is_multiplayer_authority():
    print("This is the local player!")

# Sync method (called automatically)
player.sync_transform(position, look_rotation)
```

---

**Ready to play?** Start two instances and test it out! 🎮

For more details, see **MULTIPLAYER_GUIDE.md**
