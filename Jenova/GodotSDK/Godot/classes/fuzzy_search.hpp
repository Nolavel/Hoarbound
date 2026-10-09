/**************************************************************************/
/*  fuzzy_search.hpp                                                      */
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

#include <Godot/classes/ref.hpp>
#include <Godot/classes/ref_counted.hpp>
#include <Godot/variant/typed_array.hpp>

#include <Godot/core/class_db.hpp>

#include <type_traits>

namespace godot {

class FuzzySearchMatch;
class PackedStringArray;
class String;

class FuzzySearch : public RefCounted {
	GDEXTENSION_CLASS(FuzzySearch, RefCounted)

public:
	void set_start_offset(int32_t p_start_offset);
	int32_t get_start_offset() const;
	void set_max_results(int32_t p_max_results);
	int32_t get_max_results() const;
	void set_max_misses(int32_t p_max_misses);
	int32_t get_max_misses() const;
	void set_use_exact_tokens(bool p_use_exact_tokens);
	bool get_use_exact_tokens() const;
	void set_case_sensitive(bool p_case_sensitive);
	bool get_case_sensitive() const;
	void set_filter_low_scores(bool p_filter_low_scores);
	bool get_filter_low_scores() const;
	void set_filter_factor(float p_filter_factor);
	float get_filter_factor() const;
	void set_filter_cutoff(float p_filter_cutoff);
	float get_filter_cutoff() const;
	Ref<FuzzySearchMatch> search(const String &p_query, const String &p_target) const;
	TypedArray<Ref<FuzzySearchMatch>> search_all(const String &p_query, const PackedStringArray &p_targets) const;

protected:
	template <typename T, typename B>
	static void register_virtuals() {
		RefCounted::register_virtuals<T, B>();
	}

public:
};

} // namespace godot

