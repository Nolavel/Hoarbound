extends Control
## Standalone visual sandbox: one FULLSCREEN overlay, not cards or gameplay.
var _overlay: EdgeGlowOverlay
var _elapsed: float = 0.0
var _phase: int = -1
var _label: Label
func _ready() -> void:
    var back := ColorRect.new()
    back.color = Color(0.20, 0.23, 0.24)
    add_child(back)
    back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _overlay = EdgeGlowOverlay.new()
    add_child(_overlay)
    _overlay.set_hub_active(true)
    _label = Label.new()
    _label.position = Vector2(32, 245)
    _label.add_theme_font_size_override(&"font_size", 22)
    add_child(_label)
func _process(delta: float) -> void:
    _elapsed += delta
    var phase: int = int(floor(fmod(_elapsed, 8.0) / 2.0))
    if phase == _phase:
        return
    _phase = phase
    _overlay.set_action_active(phase != 0)
    match phase:
        0: _label.text = "HUB / idle"
        1: _label.text = "HUB / item selected"
        2:
            _label.text = "HUB / transfer succeeded"
            _overlay.show_result(true)
        3:
            _label.text = "HUB / transfer rejected"
            _overlay.show_result(false)
