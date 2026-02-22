tool
extends EditorScript

func _run():
	print("NEVER: ", SceneReplicationConfig.REPLICATION_MODE_NEVER)
	print("SPAWN: ", SceneReplicationConfig.REPLICATION_MODE_SPAWN)
	print("ON_CHANGE: ", SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
