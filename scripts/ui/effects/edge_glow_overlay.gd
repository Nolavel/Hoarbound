class_name EdgeGlowOverlay
extends ColorRect

## A purely visual layer on top of ONE Control/card.
## No slot, inventory, or ownership rules live here; a presenter drives it.
## Keep the archived five-color demonstration unchanged.

const GLOW_SHADER: Shader = preload("res://shaders/ui/ambient_edge_glow_overlay.gdshader")
const STATE_OFF: int = 0
const STATE_UNSELECTED: int = 1
const STATE_HELD: int = 2
const REFUSAL_SECONDS: float = 0.45
const NEUTRAL_TINT: Color = Color(0.86, 0.86, 0.82)
const HELD_TINT: Color = Color(1.0, 0.73, 0.17)
const REJECTED_TINT: Color = Color(0.98, 0.25, 0.16)

@export_range(0.04, 0.30, 0.01) var edge_width: float = 0.15
@export_range(0.0, 1.0, 0.01) var intensity: float = 1.0

var _feedback_state: int = STATE_OFF
var _feedback_enabled: bool = true
var _reduced_motion: bool = false
var _refusal_left: float = 0.0
var _clock_seconds: float = 0.0
var _shown_strength: float = 0.0
var _shader_material: ShaderMaterial


func _ready() -> void:
    # A sibling slot must never share shader state with this overlay.
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    color = Color.WHITE
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _shader_material = ShaderMaterial.new()
    _shader_material.shader = GLOW_SHADER
    material = _shader_material
    _sync_shader(NEUTRAL_TINT, 0.0)


func set_feedback_state(next_state: int) -> void:
    if next_state != STATE_OFF and next_state != STATE_UNSELECTED and next_state != STATE_HELD:
        push_warning("EdgeGlowOverlay: unknown presentation state %d" % next_state)
        return
    _feedback_state = next_state


func get_feedback_state() -> int:
    return _feedback_state


## Call this ONLY after gameplay has actually rejected a placement or action.
## The visual pulse does not change the persistent unselected/held state.
func show_refusal() -> void:
    _refusal_left = REFUSAL_SECONDS


func set_feedback_enabled(enabled: bool) -> void:
    _feedback_enabled = enabled
    if not enabled:
        _refusal_left = 0.0


func set_reduced_motion(enabled: bool) -> void:
    _reduced_motion = enabled
    if enabled:
        _clock_seconds = 0.0


func _process(delta: float) -> void:
    var elapsed: float = maxf(delta, 0.0)
    _refusal_left = maxf(0.0, _refusal_left - elapsed)
    if not _reduced_motion:
        _clock_seconds += elapsed

    var tint: Color = NEUTRAL_TINT if _feedback_state != STATE_HELD else HELD_TINT
    var target: float = 0.0
    if _feedback_enabled:
        if _feedback_state == STATE_UNSELECTED:
            target = 0.14
        elif _feedback_state == STATE_HELD:
            target = 0.38
        if _refusal_left > 0.0:
            tint = REJECTED_TINT
            target = maxf(target, 0.85 * minf(_refusal_left / 0.18, 1.0))

    # Reduced motion disables travel and the eased transition, but not feedback.
    var blend: float = 1.0 if _reduced_motion else 1.0 - exp(-elapsed / 0.08)
    _shown_strength = lerpf(_shown_strength, target, blend)
    _sync_shader(tint, _shown_strength * intensity)


func _sync_shader(tint: Color, strength: float) -> void:
    if _shader_material == null:
        return
    _shader_material.set_shader_parameter(&"glow_color", tint)
    _shader_material.set_shader_parameter(&"glow_strength", clampf(strength, 0.0, 1.0))
    _shader_material.set_shader_parameter(&"edge_width", edge_width)
    _shader_material.set_shader_parameter(&"clock_seconds", _clock_seconds)
    _shader_material.set_shader_parameter(&"motion_factor", 0.0 if _reduced_motion else 1.0)
