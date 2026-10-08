/**************************************************************************/
/*  visual_shader_group.hpp                                               */
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

#include <Godot/classes/global_constants.hpp>
#include <Godot/classes/ref.hpp>
#include <Godot/classes/resource.hpp>
#include <Godot/classes/visual_shader_node.hpp>
#include <Godot/variant/dictionary.hpp>
#include <Godot/variant/packed_int32_array.hpp>
#include <Godot/variant/string.hpp>
#include <Godot/variant/typed_array.hpp>
#include <Godot/variant/vector2.hpp>

#include <Godot/core/class_db.hpp>

#include <type_traits>

namespace godot {

class StringName;

class VisualShaderGroup : public Resource {
	GDEXTENSION_CLASS(VisualShaderGroup, Resource)

public:
	void set_group_name(const String &p_name);
	String get_group_name() const;
	String insert_input_port(int32_t p_id, VisualShaderNode::PortType p_type, const String &p_name);
	void remove_input_port(int32_t p_id);
	void move_input_port(int32_t p_from, int32_t p_to);
	void set_input_port_name(int32_t p_id, const String &p_name);
	void set_input_port_type(int32_t p_id, VisualShaderNode::PortType p_type);
	void set_input_port_count(int32_t p_count);
	int32_t get_input_port_count() const;
	String get_input_port_name(int32_t p_id) const;
	VisualShaderNode::PortType get_input_port_type(int32_t p_id) const;
	String insert_output_port(int32_t p_id, VisualShaderNode::PortType p_type, const String &p_name);
	void remove_output_port(int32_t p_id);
	void move_output_port(int32_t p_from, int32_t p_to);
	void set_output_port_name(int32_t p_id, const String &p_name);
	void set_output_port_type(int32_t p_id, VisualShaderNode::PortType p_type);
	void set_output_port_count(int32_t p_count);
	int32_t get_output_port_count() const;
	String get_output_port_name(int32_t p_id) const;
	VisualShaderNode::PortType get_output_port_type(int32_t p_id) const;
	void add_node(const Ref<VisualShaderNode> &p_node, const Vector2 &p_position, int32_t p_id);
	Ref<VisualShaderNode> get_node(int32_t p_id) const;
	void set_node_position(int32_t p_id, const Vector2 &p_position);
	Vector2 get_node_position(int32_t p_id) const;
	PackedInt32Array get_node_list() const;
	int32_t get_valid_node_id() const;
	void remove_node(int32_t p_id);
	void replace_node(int32_t p_id, const StringName &p_new_class);
	bool is_node_connection(int32_t p_from_node, int32_t p_from_port, int32_t p_to_node, int32_t p_to_port) const;
	bool can_connect_nodes(int32_t p_from_node, int32_t p_from_port, int32_t p_to_node, int32_t p_to_port) const;
	Error connect_nodes(int32_t p_from_node, int32_t p_from_port, int32_t p_to_node, int32_t p_to_port);
	void disconnect_nodes(int32_t p_from_node, int32_t p_from_port, int32_t p_to_node, int32_t p_to_port);
	void connect_nodes_forced(int32_t p_from_node, int32_t p_from_port, int32_t p_to_node, int32_t p_to_port);
	TypedArray<Dictionary> get_node_connections() const;
	void attach_node_to_frame(int32_t p_id, int32_t p_frame);
	void detach_node_from_frame(int32_t p_id);

protected:
	template <typename T, typename B>
	static void register_virtuals() {
		Resource::register_virtuals<T, B>();
	}

public:
};

} // namespace godot

