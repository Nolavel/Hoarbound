extends SceneTree

## Writes a SceneParity snapshot of a scene, or of a script's code-built tree.
## Run: godot --headless --path . --script res://tools/scene_parity/snapshot.gd -- <res://x.tscn|res://x.gd> <out.json> [node path]
## With a node path the snapshot is of that node inside the instantiated scene (e.g. a stove in a shelter).


func _process(_delta: float) -> bool:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: -- <scene or script> <out.json>")
		quit(1)
		return true
	var node: Node3D
	if args[0].ends_with(".tscn"):
		node = (load(args[0]) as PackedScene).instantiate() as Node3D
	else:
		node = (load(args[0]) as GDScript).new() as Node3D
	root.add_child(node)
	if args.size() > 2:
		node = node.get_node(NodePath(args[2])) as Node3D
	var entries: Array = SceneParity.snapshot(node)
	SceneParity.save(entries, args[1])
	print("SCENE_PARITY snapshot %d visuals -> %s" % [entries.size(), args[1]])
	quit(0)
	return true
