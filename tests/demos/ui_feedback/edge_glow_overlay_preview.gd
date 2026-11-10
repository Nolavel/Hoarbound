extends Control

## Isolated preview: three states over local cards. No gameplay data is faked.
## The red card is a simulated presenter event, not an inventory integration.

var _refused_card: EdgeGlowOverlay
var _elapsed: float = 0.0


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    var background := ColorRect.new()
    background.color = Color(0.16, 0.18, 0.19)
    background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(background)

    var snow := ColorRect.new()
    snow.color = Color(0.83, 0.84, 0.83)
    snow.position = Vector2(608.0, 0.0)
    snow.size = Vector2(352.0, 540.0)
    snow.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(snow)

    var title := Label.new()
    title.text = "ISSUE #282  /  LOCAL TRANSPARENT EDGE GLOW"
    title.position = Vector2(43.0, 54.0)
    title.add_theme_font_size_override(&"font_size", 20)
    title.add_theme_color_override(&"font_color", Color(1.0, 0.96, 0.86))
    title.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(title)

    _make_card(Vector2(44.0, 202.0), "UNSELECTED", EdgeGlowOverlay.STATE_UNSELECTED)
    _make_card(Vector2(348.0, 202.0), "HELD  /  INACTIVE", EdgeGlowOverlay.STATE_HELD)
    _refused_card = _make_card(Vector2(652.0, 202.0), "REJECTED  /  EVENT", EdgeGlowOverlay.STATE_UNSELECTED)
    _refused_card.show_refusal()


func _make_card(position_on_screen: Vector2, title: String, state: int) -> EdgeGlowOverlay:
    var card := ColorRect.new()
    card.position = position_on_screen
    card.size = Vector2(264.0, 142.0)
    card.color = Color(0.17, 0.19, 0.22, 1.0)
    card.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(card)

    var label := Label.new()
    label.position = Vector2(14.0, 53.0)
    label.text = title
    label.add_theme_font_size_override(&"font_size", 16)
    label.add_theme_color_override(&"font_color", Color(0.95, 0.94, 0.88))
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    card.add_child(label)

    var overlay := EdgeGlowOverlay.new()
    overlay.name = "EdgeGlowOverlay"
    card.add_child(overlay)
    overlay.set_feedback_state(state)
    return overlay


func _process(delta: float) -> void:
    _elapsed += maxf(delta, 0.0)
    if _elapsed >= 2.5 and _refused_card != null:
        _elapsed = 0.0
        _refused_card.show_refusal()
