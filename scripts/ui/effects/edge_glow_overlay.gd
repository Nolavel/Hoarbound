class_name EdgeGlowOverlay
extends ColorRect

## One full-screen Hub signal, owned by the UI presentation layer.
## A presenter enables it ONLY for Tab-Hub / open pack at a container.
## It owns no item, inventory or transfer state.
const GLOW_SHADER: Shader = preload("res://shaders/ui/ambient_edge_glow_overlay.gdshader")
const STATE_IDLE: int = 0
const STATE_ACTIVE: int = 1
const RESULT_SECONDS: float = 0.65
const NEUTRAL_TINT: Color = Color(0.75, 0.76, 0.74)
const ACTIVE_TINT: Color = Color(1.0, 0.67, 0.12)
const SUCCESS_TINT: Color = Color(0.22, 0.87, 0.40)
const REJECTED_TINT: Color = Color(0.98, 0.19, 0.15)

@export_range(0.025, 0.25, 0.005) var edge_width: float = 0.115
@export_range(0.0, 1.0, 0.01) var intensity: float = 1.0

var _state: int = STATE_IDLE
var _hub_active: bool = false
var _reduced_motion: bool = false
var _result_left: float = 0.0
var _result_success: bool = false
var _clock: float = 0.0
var _strength: float = 0.0
var _shader_material: ShaderMaterial

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    color = Color.WHITE
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _shader_material = ShaderMaterial.new()
    _shader_material.shader = GLOW_SHADER
    material = _shader_material
    visible = _hub_active
    _sync_shader(NEUTRAL_TINT, 0.0)

func set_hub_active(active: bool) -> void:
    _hub_active = active
    visible = active
    if not active:
        _result_left = 0.0
        _state = STATE_IDLE
        _strength = 0.0
        _sync_shader(NEUTRAL_TINT, 0.0)

func set_action_active(active: bool) -> void:
    _state = STATE_ACTIVE if active else STATE_IDLE

func get_feedback_state() -> int:
    return _state

## Call after the authoritative transfer/use result. Never on hover alone.
func show_result(success: bool) -> void:
    if not _hub_active:
        return
    _result_success = success
    _result_left = RESULT_SECONDS

func set_reduced_motion(enabled: bool) -> void:
    _reduced_motion = enabled
    if enabled:
        _clock = 0.0

func _process(delta: float) -> void:
    if not _hub_active:
        return
    var dt: float = maxf(delta, 0.0)
    if not _reduced_motion:
        _clock += dt
    _result_left = maxf(0.0, _result_left - dt)
    var tint: Color = ACTIVE_TINT if _state == STATE_ACTIVE else NEUTRAL_TINT
    var target: float = 0.32 if _state == STATE_ACTIVE else 0.085
    if _state == STATE_ACTIVE and not _reduced_motion:
        target *= 0.92 + 0.08 * sin(_clock * 2.0)
    if _result_left > 0.0:
        tint = SUCCESS_TINT if _result_success else REJECTED_TINT
        target = 0.72 * minf(_result_left / 0.27, 1.0)
    var blend: float = 1.0 if _reduced_motion else 1.0 - exp(-dt / 0.065)
    _strength = lerpf(_strength, target, blend)
    _sync_shader(tint, _strength * intensity)

func _sync_shader(tint: Color, strength: float) -> void:
    if _shader_material == null:
        return
    _shader_material.set_shader_parameter(&"glow_color", tint)
    _shader_material.set_shader_parameter(&"glow_strength", clampf(strength, 0.0, 1.0))
    _shader_material.set_shader_parameter(&"edge_width", edge_width)
    _shader_material.set_shader_parameter(&"clock_seconds", _clock)
    _shader_material.set_shader_parameter(&"motion_factor", 0.0 if _reduced_motion else 1.0)
