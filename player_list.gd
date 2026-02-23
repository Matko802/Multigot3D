class_name PlayerList
extends Control

@onready var item_list: ItemList = %ItemList
@onready var title_label: Label = %TitleLabel

func _ready() -> void:
	# Hide by default
	visible = false
	
	# Connect to GDSync signals
	if GDSync:
		GDSync.client_joined.connect(_on_client_joined)
		GDSync.client_left.connect(_on_client_left)
		GDSync.player_data_changed.connect(_on_player_data_changed)
		GDSync.lobby_joined.connect(_on_lobby_joined)
		GDSync.disconnected.connect(_on_disconnected)

	# Initial update
	update_list()

func update_list() -> void:
	if not item_list:
		return
		
	item_list.clear()
	
	# Check if we are connected/in a lobby
	if not GDSync.is_active():
		item_list.add_item("Not connected")
		return
		
	var clients: Array = GDSync.lobby_get_all_clients()
	if clients.is_empty():
		# Might be in singleplayer or not in lobby yet
		# Check if singleplayer logic from GameManager applies, but usually GDSync handles local ID
		# If singleplayer via GameManager, we might not have GDSync lobby clients if local multiplayer isn't started
		# But let's assume standard GDSync usage.
		
		# If we are just connected but not in a lobby
		if GDSync.get_client_id() != -1:
			# Show self if nothing else
			_add_client_to_list(GDSync.get_client_id())
		else:
			item_list.add_item("No players")
		return

	# Sort clients for consistent ordering
	clients.sort()
	
	for client_id in clients:
		_add_client_to_list(client_id)
	
	if title_label:
		title_label.text = "Players (%d)" % clients.size()

func _add_client_to_list(client_id: int) -> void:
	var username: String = GDSync.player_get_username(client_id)
	if username == "":
		username = "Player " + str(client_id)
	
	var own_id: int = GDSync.get_client_id()
	if client_id == own_id:
		username += " (You)"
	
	if client_id == GDSync.get_host():
		username += " [HOST]"
		
	item_list.add_item(username)

func _on_client_joined(_client_id: int) -> void:
	update_list()

func _on_client_left(_client_id: int) -> void:
	update_list()

func _on_player_data_changed(_client_id: int, key: String, _value: Variant) -> void:
	if key == "Username":
		update_list()

func _on_lobby_joined(_lobby_name: String) -> void:
	update_list()

func _on_disconnected() -> void:
	update_list()
