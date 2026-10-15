class_name RenderLayers
extends RefCounted
## Reserved 3D render layers; names match [layer_names] in project.godot.
## Every system that owns a special layer takes its mask from here.

## Layer 18: fullscreen passes on the player camera (painterly wash); other cameras in the world leave it out.
const SCREEN_PASS: int = 1 << 17
## Layer 19: geometry that presses snow, seen only by the snow contact camera.
const SNOW_CONTACT: int = 1 << 18
## Layer 20: dev map labels, seen only by the dev diorama camera.
const DEV_MAP_LABEL: int = 1 << 19
## Every reserved special layer; ordinary cameras leave these out.
const RESERVED: int = SNOW_CONTACT | DEV_MAP_LABEL
