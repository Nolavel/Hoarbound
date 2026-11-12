class_name TpsRigFrame
extends RefCounted

## One frame of the TPS rig as the behaviours build it, in order: each reads what the ones
## before it left and writes its own share. TpsCamera turns the result into the camera.

var delta: float = 0.0
## Henry's safe point: casts start here so they never begin inside a wall.
var safe: Vector3 = Vector3.ZERO
## Orbit centre: followed feet, raised to the shoulder joints.
var pivot: Vector3 = Vector3.ZERO
## Where the player looks, and where the camera body orbits (the same on the direct rig).
var view_yaw: float = 0.0
var view_pitch: float = 0.0
var orbit_yaw: float = 0.0
var orbit_pitch: float = 0.0
## Boom length asked for before walls, metres.
var want: float = 0.0
## Lateral offset of the shoulder point from the pivot, metres.
var side: float = 0.0
var right: Vector3 = Vector3.RIGHT
var back: Vector3 = Vector3.BACK
## Shoulder point after walls, and the camera position on the boom from it.
var shoulder: Vector3 = Vector3.ZERO
var camera: Vector3 = Vector3.ZERO
var view: Basis = Basis.IDENTITY
