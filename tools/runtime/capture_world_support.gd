class_name CaptureWorldSupport
extends RefCounted
## Shared by the runtime capture tools: ground height from whichever world is loaded, and a wait until the
## streamed chunk at a point is live and the streamer is quiet (Reality streams; the legacy island does not).

## Frames the streamer must stay quiet, with live ground at the point, before a capture may run.
const QUIET_FRAMES: int = 30
const MAX_WAIT_FRAMES: int = 6000


## The node answering get_height(x, z): Reality's ground, else the legacy IslandTerrain; null when neither.
static func ground_of(scene: Node) -> Node:
	var reality: Node = scene.find_child("RealityGround", true, false)
	if reality != null:
		return reality
	return scene.find_child("IslandTerrain", true, false)


## Ground height at x/z, or 0 when the world has no height source (or no live ground there yet).
static func height(scene: Node, x: float, z: float) -> float:
	var ground: Node = ground_of(scene)
	if ground is KeyWestRealityGround:
		return (ground as KeyWestRealityGround).get_height(x, z)
	if ground is IslandTerrain:
		return maxf((ground as IslandTerrain).get_height(x, z), 0.0)
	return 0.0


## True when the ground at x/z is live and no streamer is loading; always true on a world without Reality ground.
static func is_settled(scene: Node, xz: Vector2) -> bool:
	var ground := ground_of(scene) as KeyWestRealityGround
	if ground == null:
		return true
	for streaming: Node in scene.find_children("*", "StreamingSystem", true, false):
		if not (streaming as StreamingSystem)._transient.is_empty():
			return false
	return ground.has_ground_at(xz.x, xz.y)


## Puts `player` over x/z and waits until that chunk is live and every streamer is quiet. True at once on a
## world without Reality ground; false after MAX_WAIT_FRAMES.
static func wait_streamed(tree: SceneTree, scene: Node, player: Node3D, xz: Vector2) -> bool:
	var ground := ground_of(scene) as KeyWestRealityGround
	if ground == null:
		return true
	player.global_position = Vector3(xz.x, player.global_position.y, xz.y)
	var quiet: int = 0
	for i: int in range(MAX_WAIT_FRAMES):
		quiet = quiet + 1 if is_settled(scene, xz) else 0
		if quiet >= QUIET_FRAMES:
			return true
		await tree.process_frame
	return false
