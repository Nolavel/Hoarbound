class_name ContainerFraming
extends Resource

## How the open pack at a container is framed (owner-authored in tests/scenes/container_framing_stage.tscn):
## the view, the pack and Henry, relative to the container's front, for the pack on its right.

const PATH: String = "res://data/items/container_framing.tres"

## Relative to the front: origin at the middle of the shelves' open face, +X its right as one looks in, +Y up,
## +Z out of it. The camera's own -Z looks; the pack's -Z is its opening; Henry is his visual (feet, facing +Z).
@export var camera: Transform3D = Transform3D.IDENTITY
@export_range(10.0, 90.0, 0.5) var camera_fov: float = 34.0
@export var pack: Transform3D = Transform3D.IDENTITY
@export var henry: Transform3D = Transform3D.IDENTITY
## Off: Henry is hidden while the pack is open there.
@export var show_henry: bool = true


## The authored framing, or null when none is saved.
static func load_saved() -> ContainerFraming:
	return load(PATH) as ContainerFraming if ResourceLoader.exists(PATH) else null


## `local` (relative to the front, pack on the right) for the pack on `side` (-1 left: mirrored across the front).
static func on_side(local: Transform3D, side: float) -> Transform3D:
	if side >= 0.0:
		return local
	var flip := Basis.from_scale(Vector3(-1.0, 1.0, 1.0))
	return Transform3D(flip * local.basis * flip, local.origin * Vector3(-1.0, 1.0, 1.0))


## The container's front as a transform (world): origin, right, up and out (ItemContainer.front).
static func front_of(container: ItemContainer) -> Transform3D:
	var face: Array = container.front()
	return Transform3D(Basis(face[2], Vector3.UP, face[1]), face[0])
