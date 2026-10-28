/* EverPlay's cheats for Godot 4 (compiled into Godot's platform/ios library by
 * scripts/patch-godot-ios.py): the running game's variables and speed. Plain C++, apart from
 * everplay_godot.mm: Godot's scene headers and UIKit's CoreText both declare FontVariation.
 * Every function is called on the main thread, between frames. MIT, like Godot. */

#include "core/config/engine.h"
#include "core/io/json.h"
#include "scene/main/scene_tree.h"
#include "scene/main/window.h"

#include <cstdio>

#define EVERPLAY_EXPORT extern "C" __attribute__((visibility("default")))


/* Script variables worth showing: numbers, flags and text. */
static bool everplay_editable(const Variant &p_value) {
	switch (p_value.get_type()) {
		case Variant::BOOL:
		case Variant::INT:
		case Variant::FLOAT:
		case Variant::STRING:
		case Variant::STRING_NAME:
			return true;
		default:
			return false;
	}
}

static void everplay_add(Array &r_list, const String &p_node, const String &p_path, const Variant &p_value) {
	Dictionary entry;
	entry["node"] = p_node;
	entry["path"] = p_path;
	entry["type"] = Variant::get_type_name(p_value.get_type());
	entry["value"] = p_value.get_type() == Variant::STRING_NAME ? Variant(String(p_value)) : p_value;
	r_list.push_back(entry);
}

/* An object's script variables, and one level into its dictionaries and objects ("player.gold"). */
static void everplay_collect(Array &r_list, const String &p_node, Object *p_object, const String &p_prefix, int p_depth) {
	List<PropertyInfo> properties;
	p_object->get_property_list(&properties);
	for (const PropertyInfo &property : properties) {
		if (!(property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) || r_list.size() > 20000) {
			continue;
		}
		String path = p_prefix + String(property.name);
		Variant value = p_object->get(property.name);
		if (everplay_editable(value)) {
			everplay_add(r_list, p_node, path, value);
		} else if (value.get_type() == Variant::DICTIONARY && p_depth == 0) {
			Dictionary dictionary = value;
			Array keys = dictionary.keys();
			for (int i = 0; i < keys.size() && i < 2000; i++) {
				if (everplay_editable(dictionary[keys[i]])) {
					everplay_add(r_list, p_node, path + "." + String(keys[i]), dictionary[keys[i]]);
				}
			}
		} else if (value.get_type() == Variant::OBJECT && p_depth == 0) {
			Object *child = value;
			if (child && !Object::cast_to<Node>(child)) {
				everplay_collect(r_list, p_node, child, path + ".", 1);
			}
		}
	}
}

/* JSON: [{node, path, type, value}] for the autoloads (the game's global scripts) and the current
 * scene. Writes up to `size` bytes; returns the length the whole list needs. */
EVERPLAY_EXPORT int everplay_godot_variables(char *buffer, int size) {
	SceneTree *tree = SceneTree::get_singleton();
	Array list;
	if (tree) {
		Window *root = tree->get_root();
		for (int i = 0; root && i < root->get_child_count(); i++) {
			Node *node = root->get_child(i);
			everplay_collect(list, String(node->get_path()), node, "", 0);
		}
	}
	CharString json = JSON::stringify(list).utf8();
	if (buffer && size > 0) {
		snprintf(buffer, size, "%s", json.get_data());
	}
	return json.length() + 1;
}

/* Sets a variable from everplay_godot_variables to `text`, read as the variable's current type. */
EVERPLAY_EXPORT int everplay_godot_set_variable(const char *node_path, const char *path, const char *text) {
	SceneTree *tree = SceneTree::get_singleton();
	Window *root = tree ? (Window *)tree->get_root() : nullptr;
	Node *node = root ? root->get_node_or_null(NodePath(String::utf8(node_path))) : nullptr;
	if (!node) {
		return 0;
	}
	Vector<String> parts = String::utf8(path).split(".");
	Object *object = node;
	Dictionary dictionary;
	bool in_dictionary = false;
	Variant dictionary_key;
	for (int i = 0; i < parts.size() - 1; i++) {
		Variant next = object->get(StringName(parts[i]));
		if (next.get_type() == Variant::DICTIONARY) {
			dictionary = next;
			Array keys = dictionary.keys();
			String wanted = parts[i + 1];
			for (int k = 1; i + k < parts.size() - 1; k++) {
				wanted += "." + parts[i + 1 + k];  // keys may contain dots
			}
			for (int k = 0; k < keys.size(); k++) {
				if (String(keys[k]) == wanted) {
					dictionary_key = keys[k];
					in_dictionary = true;
				}
			}
			if (!in_dictionary) {
				return 0;
			}
			break;
		}
		object = next;
		if (!object) {
			return 0;
		}
	}
	String name = parts[parts.size() - 1];
	Variant current = in_dictionary ? dictionary[dictionary_key] : object->get(StringName(name));
	String value = String::utf8(text);
	Variant result;
	switch (current.get_type()) {
		case Variant::BOOL:
			result = value == "true" || value == "1";
			break;
		case Variant::INT:
			result = value.to_int();
			break;
		case Variant::FLOAT:
			result = value.to_float();
			break;
		case Variant::STRING_NAME:
			result = StringName(value);
			break;
		default:
			result = value;
	}
	if (in_dictionary) {
		dictionary[dictionary_key] = result;
	} else {
		object->set(StringName(name), result);
	}
	return 1;
}

/* Engine.time_scale: 1 normal, 2 twice as fast. */
EVERPLAY_EXPORT void everplay_godot_set_speed(double scale) {
	Engine::get_singleton()->set_time_scale(scale);
}
