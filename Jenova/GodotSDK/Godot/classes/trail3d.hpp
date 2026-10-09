/**************************************************************************/
/*  trail3d.hpp                                                           */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

// THIS FILE IS GENERATED. EDITS WILL BE LOST.

#pragma once

#include <Godot/classes/line3d.hpp>
#include <Godot/classes/ref.hpp>
#include <Godot/variant/color.hpp>

#include <Godot/core/class_db.hpp>

#include <type_traits>

namespace godot {

class Curve;
class Gradient;
class ShaderMaterial;

class Trail3D : public Line3D {
	GDEXTENSION_CLASS(Trail3D, Line3D)

public:
	enum LimitMode {
		LIMIT_MODE_LIFETIME = 0,
		LIMIT_MODE_MAX_LENGTH = 1,
		LIMIT_MODE_MAX = 2,
	};

	void set_width(float p_width);
	float get_width() const;
	void set_width_curve(const Ref<Curve> &p_curve);
	Ref<Curve> get_width_curve() const;
	void set_emitting(bool p_emitting);
	bool is_emitting() const;
	void set_color(const Color &p_color);
	Color get_color() const;
	void set_color_gradient(const Ref<Gradient> &p_gradient);
	Ref<Gradient> get_color_gradient() const;
	void set_material_mode(Line3D::MaterialMode p_material_mode);
	Line3D::MaterialMode get_material_mode() const;
	void set_material(const Ref<ShaderMaterial> &p_material);
	Ref<ShaderMaterial> get_material() const;
	void set_mesh_alignment(Line3D::MeshAlignment p_alignment);
	Line3D::MeshAlignment get_mesh_alignment() const;
	void set_tiling_multiplier(float p_tiling_multiplier);
	float get_tiling_multiplier() const;
	void set_tiling_mode(Line3D::TilingMode p_tiling_mode);
	Line3D::TilingMode get_tiling_mode() const;
	void clear();
	void set_min_section_length(float p_min_section_length);
	float get_min_section_length() const;
	void set_limit_mode(Trail3D::LimitMode p_limit_mode);
	Trail3D::LimitMode get_limit_mode() const;
	void set_lifetime(float p_lifetime);
	float get_lifetime() const;
	void set_max_length(float p_max_length);
	float get_max_length() const;
	void set_pin_uv(bool p_pin_uv);
	bool get_pin_uv() const;
	float get_current_length() const;

protected:
	template <typename T, typename B>
	static void register_virtuals() {
		Line3D::register_virtuals<T, B>();
	}

public:
};

} // namespace godot

VARIANT_ENUM_CAST(Trail3D::LimitMode);

