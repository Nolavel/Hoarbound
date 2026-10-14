#ifndef HOARBOUND_FROST_CONTROLLER_H
#define HOARBOUND_FROST_CONTROLLER_H

#include "frost_progression.hpp"

#include <godot_cpp/classes/h_slider.hpp>
#include <godot_cpp/classes/label.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/shader.hpp>
#include <godot_cpp/classes/shader_material.hpp>

namespace godot {

class HoarboundFrostController : public Node {
	GDCLASS(HoarboundFrostController, Node)

protected:
	static void _bind_methods();

public:
	HoarboundFrostController();

	void _process(double delta) override;
	void bind_scene(Node *root);

	void set_freeze_duration(double duration_seconds);
	double get_freeze_duration() const;
	void set_auto_play(bool enabled);
	bool get_auto_play() const;
	void set_frost_amount(double amount);
	double get_frost_amount() const;
	void restart_frost_demo();

private:
	void render_frost(double amount);
	void on_slider_changed(double value);

	hoarbound::frost::FrostProgression progression_;
	MeshInstance3D *glass_ = nullptr;
	HSlider *slider_ = nullptr;
	Label *value_label_ = nullptr;
	Ref<Shader> shader_;
	Ref<ShaderMaterial> material_;
	bool auto_play_ = true;
	bool syncing_slider_ = false;
};

} // namespace godot

#endif // HOARBOUND_FROST_CONTROLLER_H
