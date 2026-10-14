#include "hoarbound_frost_controller.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cmath>

namespace godot {

namespace {

const char *FROST_SHADER = R"FROST_SHADER(
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_prepass_alpha;

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
	float edge = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float broad = fbm(UV * vec2(5.5, 4.2));
	float fine = value_noise(UV * vec2(36.0, 28.0));
	float reach = mix(-0.085, 0.565, frost_amount);
	float noisy_edge = edge + (broad - 0.5) * 0.105 + (fine - 0.5) * 0.022;
	float frost = 1.0 - smoothstep(reach - 0.055, reach + 0.020, noisy_edge);
	frost *= smoothstep(0.0, 0.035, frost_amount);

	float front_band = 1.0 - smoothstep(0.015, 0.090, abs(noisy_edge - reach));
	float crystals = smoothstep(0.68, 0.92, value_noise(UV * 74.0 + broad * 7.0));
	float vein = front_band * crystals * frost;

	vec3 base = mix(glass_tint.rgb, frost_tint.rgb, frost);
	base = mix(base, vec3(1.0), vein * 0.52);
	ALBEDO = base;
	float frost_alpha = clamp(frost * 0.95 + vein * 0.15, 0.0, 1.0);
	ALPHA = mix(0.095, 0.995, frost_alpha);
	ROUGHNESS = mix(0.18, 0.96, frost);
}
)FROST_SHADER";

} // namespace

HoarboundFrostController::HoarboundFrostController() {
	set_process(true);
}

void HoarboundFrostController::_bind_methods() {
	ClassDB::bind_method(D_METHOD("bind_scene", "root"), &HoarboundFrostController::bind_scene);
	ClassDB::bind_method(D_METHOD("set_freeze_duration", "duration_seconds"), &HoarboundFrostController::set_freeze_duration);
	ClassDB::bind_method(D_METHOD("get_freeze_duration"), &HoarboundFrostController::get_freeze_duration);
	ClassDB::bind_method(D_METHOD("set_auto_play", "enabled"), &HoarboundFrostController::set_auto_play);
	ClassDB::bind_method(D_METHOD("get_auto_play"), &HoarboundFrostController::get_auto_play);
	ClassDB::bind_method(D_METHOD("set_frost_amount", "amount"), &HoarboundFrostController::set_frost_amount);
	ClassDB::bind_method(D_METHOD("get_frost_amount"), &HoarboundFrostController::get_frost_amount);
	ClassDB::bind_method(D_METHOD("restart_frost_demo"), &HoarboundFrostController::restart_frost_demo);
	ClassDB::bind_method(D_METHOD("_on_slider_changed", "value"), &HoarboundFrostController::on_slider_changed);

	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "freeze_duration", PROPERTY_HINT_RANGE, "4.0,10.0,0.1"), "set_freeze_duration", "get_freeze_duration");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "auto_play"), "set_auto_play", "get_auto_play");
}

void HoarboundFrostController::bind_scene(Node *root) {
	if (root == nullptr) {
		UtilityFunctions::push_error("HoarboundFrostController.bind_scene requires a scene root.");
		return;
	}

	glass_ = Object::cast_to<MeshInstance3D>(root->get_node_or_null(NodePath("Window/Glass")));
	slider_ = Object::cast_to<HSlider>(root->get_node_or_null(NodePath("UI/Panel/FrostSlider")));
	value_label_ = Object::cast_to<Label>(root->get_node_or_null(NodePath("UI/Panel/Value")));
	if (glass_ == nullptr || slider_ == nullptr || value_label_ == nullptr) {
		UtilityFunctions::push_error("HoarboundFrostController could not resolve the frost lab nodes.");
		return;
	}

	shader_.instantiate();
	shader_->set_code(String(FROST_SHADER));
	material_.instantiate();
	material_->set_shader(shader_);
	glass_->set_material_override(material_);

	slider_->set_min(0.0);
	slider_->set_max(1.0);
	slider_->set_step(0.001);
	const Callable callback(this, "_on_slider_changed");
	if (!slider_->is_connected("value_changed", callback)) {
		slider_->connect("value_changed", callback);
	}

	progression_.set_duration(get_freeze_duration());
	if (auto_play_) {
		progression_.restart();
	} else {
		progression_.set_amount(0.0);
	}
	render_frost(progression_.amount());
	UtilityFunctions::print("[gdextension-frost] CORE_TRACE=", String(hoarbound::frost::reference_trace().c_str()));
	UtilityFunctions::print("[gdextension-frost] native controller ready");
}

void HoarboundFrostController::_process(double delta) {
	if (!auto_play_) {
		return;
	}

	const bool was_playing = progression_.is_auto_playing();
	progression_.set_auto_playing(true);
	progression_.advance(delta);
	auto_play_ = progression_.is_auto_playing();
	render_frost(progression_.amount());
	if (was_playing && !auto_play_ && progression_.amount() >= 1.0) {
		UtilityFunctions::print("[gdextension-frost] frost pass reached 100%");
	}
}

void HoarboundFrostController::set_freeze_duration(double duration_seconds) {
	progression_.set_duration(duration_seconds);
}

double HoarboundFrostController::get_freeze_duration() const {
	return progression_.duration();
}

void HoarboundFrostController::set_auto_play(bool enabled) {
	auto_play_ = enabled;
	progression_.set_auto_playing(enabled);
}

bool HoarboundFrostController::get_auto_play() const {
	return auto_play_;
}

void HoarboundFrostController::set_frost_amount(double amount) {
	progression_.set_amount(amount);
	auto_play_ = false;
	render_frost(progression_.amount());
}

double HoarboundFrostController::get_frost_amount() const {
	return progression_.amount();
}

void HoarboundFrostController::restart_frost_demo() {
	progression_.restart();
	auto_play_ = true;
	render_frost(progression_.amount());
}

void HoarboundFrostController::render_frost(double amount) {
	if (material_.is_valid()) {
		material_->set_shader_parameter("frost_amount", amount);
	}
	if (slider_ != nullptr) {
		syncing_slider_ = true;
		slider_->set_value(amount);
		syncing_slider_ = false;
	}
	if (value_label_ != nullptr) {
		const int percent = static_cast<int>(std::round(amount * 100.0));
		value_label_->set_text(String("FROST  ") + String::num_int64(percent) + "%");
	}
}

void HoarboundFrostController::on_slider_changed(double value) {
	if (!syncing_slider_) {
		set_frost_amount(value);
	}
}

} // namespace godot
