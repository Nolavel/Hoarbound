// Hoarbound Jenova spike: the scene logic and the GPU shader source both live here.
// Godot still compiles the embedded shader source with its shader compiler; there is
// intentionally no .gdshader and no gameplay GDScript in this lab.

#include <Godot/godot.hpp>
#include <Godot/classes/h_slider.hpp>
#include <Godot/classes/label.hpp>
#include <Godot/classes/mesh_instance3d.hpp>
#include <Godot/classes/node.hpp>
#include <Godot/classes/shader.hpp>
#include <Godot/classes/shader_material.hpp>
#include <Godot/variant/callable.hpp>
#include <Godot/variant/string.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;
using namespace jenova::sdk;

JENOVA_CLASS_NAME("Hoarbound Frost Window")

namespace FrostLab
{
    Node* self = nullptr;
    MeshInstance3D* glass = nullptr;
    HSlider* slider = nullptr;
    Label* value_label = nullptr;
    Ref<Shader> shader;
    Ref<ShaderMaterial> material;
    double elapsed = 0.0;
    double amount = 0.0;
    bool syncing_slider = false;
}

// Edge-grown frost with value-noise breakup. Keeping the shader source in this C++
// file is deliberate: this spike tests Jenova as the single authoring surface.
static const char* kFrostShader = R"JENOVA_SHADER(
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_alpha_prepass;

uniform float frost_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 frost_tint : source_color = vec4(0.88, 0.94, 0.98, 1.0);
uniform vec4 glass_tint : source_color = vec4(0.62, 0.76, 0.86, 1.0);

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float value_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0));
    float d = hash21(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
    float sum = 0.0;
    float amp = 0.5;
    mat2 rot = mat2(vec2(0.80, -0.60), vec2(0.60, 0.80));
    for (int i = 0; i < 5; i++) {
        sum += value_noise(p) * amp;
        p = rot * p * 2.03 + vec2(13.7, 9.2);
        amp *= 0.5;
    }
    return sum;
}

void fragment() {
    // Distance from the nearest pane edge: 0 at frame, 0.5 at pane centre.
    float edge = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));

    // Large-scale organic front plus smaller crystalline breakup.
    float broad = fbm(UV * vec2(5.5, 4.2));
    float fine = value_noise(UV * vec2(36.0, 28.0));
    float reach = mix(-0.085, 0.565, frost_amount);
    float noisy_edge = edge + (broad - 0.5) * 0.105 + (fine - 0.5) * 0.022;
    float frost = 1.0 - smoothstep(reach - 0.055, reach + 0.020, noisy_edge);
    frost *= smoothstep(0.0, 0.035, frost_amount);

    // Thin white crystalline veins become visible near the advancing front.
    float front_band = 1.0 - smoothstep(0.015, 0.090, abs(noisy_edge - reach));
    float crystals = smoothstep(0.68, 0.92, value_noise(UV * 74.0 + broad * 7.0));
    float vein = front_band * crystals * frost;

    vec3 base = mix(glass_tint.rgb, frost_tint.rgb, frost);
    base = mix(base, vec3(1.0), vein * 0.52);
    ALBEDO = base;

    // Clear glass stays readable. At maximum, frost is effectively opaque so the
    // coloured geometry behind the pane disappears.
    float frost_alpha = clamp(frost * 0.95 + vein * 0.15, 0.0, 1.0);
    ALPHA = mix(0.095, 0.995, frost_alpha);
    ROUGHNESS = mix(0.18, 0.96, frost);
}
)JENOVA_SHADER";

static void ApplyFrost(double value)
{
    FrostLab::amount = std::clamp(value, 0.0, 1.0);

    if (FrostLab::material.is_valid())
    {
        FrostLab::material->set_shader_parameter("frost_amount", FrostLab::amount);
    }

    if (FrostLab::slider != nullptr)
    {
        FrostLab::syncing_slider = true;
        FrostLab::slider->set_value(FrostLab::amount);
        FrostLab::syncing_slider = false;
    }

    if (FrostLab::value_label != nullptr)
    {
        const int percent = static_cast<int>(std::round(FrostLab::amount * 100.0));
        FrostLab::value_label->set_text(String("FROST  ") + String::num_int64(percent) + "%");
    }
}

JENOVA_SCRIPT_BEGIN

JENOVA_PROPERTY(double, freeze_duration, 6.5, Hint:PROPERTY_HINT_RANGE, HintString:"4.0,10.0,0.1")
JENOVA_PROPERTY(bool, auto_play, true)

void SetFrostAmount(double value)
{
    auto_play = false;
    ApplyFrost(value);
}

void RestartFrostDemo()
{
    FrostLab::elapsed = 0.0;
    auto_play = true;
    ApplyFrost(0.0);
}

void OnSliderChanged(double value)
{
    if (FrostLab::syncing_slider) return;
    SetFrostAmount(value);
}

void OnReady(Caller* instance)
{
    FrostLab::self = GetSelf<Node>(instance);
    FrostLab::glass = FrostLab::self->get_node<MeshInstance3D>("Window/Glass");
    FrostLab::slider = FrostLab::self->get_node<HSlider>("UI/Panel/FrostSlider");
    FrostLab::value_label = FrostLab::self->get_node<Label>("UI/Panel/Value");

    FrostLab::shader.instantiate();
    FrostLab::shader->set_code(String(kFrostShader));
    FrostLab::material.instantiate();
    FrostLab::material->set_shader(FrostLab::shader);
    FrostLab::glass->set_material_override(FrostLab::material);

    FrostLab::slider->set_min(0.0);
    FrostLab::slider->set_max(1.0);
    FrostLab::slider->set_step(0.001);
    FrostLab::slider->connect("value_changed", Callable(FrostLab::self, "OnSliderChanged"));

    FrostLab::elapsed = 0.0;
    ApplyFrost(0.0);
    Output("[jenova-frost] C++ controller ready; shader source created from Jenova script.");
}

void OnProcess(Caller* instance, double delta)
{
    (void)instance;
    if (!auto_play) return;

    const double duration = std::max(0.1, freeze_duration);
    FrostLab::elapsed += delta;
    ApplyFrost(std::min(FrostLab::elapsed / duration, 1.0));

    if (FrostLab::elapsed >= duration)
    {
        auto_play = false;
        Output("[jenova-frost] C++ frost pass reached 100%% in %.2f seconds.", duration);
    }
}

void OnDestroy(Caller* instance)
{
    (void)instance;
    FrostLab::material.unref();
    FrostLab::shader.unref();
    FrostLab::glass = nullptr;
    FrostLab::slider = nullptr;
    FrostLab::value_label = nullptr;
    FrostLab::self = nullptr;
}

JENOVA_SCRIPT_END
