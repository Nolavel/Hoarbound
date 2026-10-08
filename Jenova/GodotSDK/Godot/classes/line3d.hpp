/**************************************************************************/
/*  line3d.hpp                                                            */
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

#include <Godot/classes/geometry_instance3d.hpp>

#include <Godot/core/class_db.hpp>

#include <type_traits>

namespace godot {

class Line3D : public GeometryInstance3D {
	GDEXTENSION_CLASS(Line3D, GeometryInstance3D)

public:
	enum MeshAlignment {
		MESH_ALIGNMENT_LOCAL = 0,
		MESH_ALIGNMENT_BILLBOARD = 1,
		MESH_ALIGNMENT_MAX = 2,
	};

	enum TilingMode {
		TILING_MODE_UNIT = 0,
		TILING_MODE_LENGTH = 1,
		TILING_MAX = 2,
	};

	enum MaterialMode {
		MATERIAL_MODE_MIX = 0,
		MATERIAL_MODE_ADD = 1,
		MATERIAL_MODE_CUSTOM = 2,
		MATERIAL_MODE_MAX = 3,
	};

protected:
	template <typename T, typename B>
	static void register_virtuals() {
		GeometryInstance3D::register_virtuals<T, B>();
	}

public:
};

} // namespace godot

VARIANT_ENUM_CAST(Line3D::MeshAlignment);
VARIANT_ENUM_CAST(Line3D::TilingMode);
VARIANT_ENUM_CAST(Line3D::MaterialMode);

