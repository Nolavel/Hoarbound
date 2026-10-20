@tool
extends EditorScenePostImport
## Landmark glb post-import: opaque surfaces take the stylized shadow contract, so shells
## streamed in Reality chunks shade like the rest of the world (STYLIZED_SHADOWS.md).


func _post_import(scene: Node) -> Object:
	StylizedEnvironmentMaterial.apply_to_tree(scene)
	return scene
