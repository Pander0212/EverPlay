/* EverPlay's entry into Godot 4 for iOS (compiled into Godot's platform/ios library by
 * scripts/patch-godot-ios.py). Godot normally owns the app (its own main() and app delegate);
 * inside EverPlay it gets a view controller to present, and EverPlay forwards the app's state.
 * Every function is called on the main thread. One game per process: Godot's globals are not
 * reset, so EverPlay closes when the game ends. MIT, like Godot. */

#include "core/config/engine.h"
#include "core/config/project_settings.h"
#include "core/input/input.h"
#include "core/input/input_event.h"
#include "core/io/json.h"
#include "core/os/main_loop.h"
#include "core/os/os.h"
#include "main/main.h"
#include "scene/main/scene_tree.h"
#include "scene/main/window.h"

#import <UIKit/UIKit.h>

/* Copied by patch-godot-ios.py from compat/<major.minor>.h: the iOS classes of this Godot version. */
#import "everplay_godot_compat.h"

#define EVERPLAY_EXPORT extern "C" __attribute__((visibility("default")))

typedef void (*everplay_godot_quit_fn)(int code);
static everplay_godot_quit_fn quit_callback = nullptr;
static bool quitting = false;

/* Called by Godot's patched view renderer when Godot's main loop asks to quit (iOS Godot never does). */
void everplay_godot_quit_requested() {
	if (quitting) {
		return;
	}
	quitting = true;
	int code = OS::get_singleton() ? OS::get_singleton()->get_exit_code() : 0;
	if (quit_callback) {
		quit_callback(code);
	}
}

/* Starts Godot with a command line (argv[0] is the program, then e.g. --main-pack <file>). Saves
 * (user://) go to `user_dir`. Returns 0 when Godot is set up; the game itself starts once the view
 * controller from everplay_godot_view_controller() is on screen. */
EVERPLAY_EXPORT int everplay_godot_start(int argc, const char **argv, const char *user_dir, everplay_godot_quit_fn on_quit) {
	quit_callback = on_quit;
	if (user_dir) {
		setenv("EVERPLAY_GODOT_USER_DIR", user_dir, 1);
	}
	// Godot keeps pointers into argv for its whole life.
	char **copy = (char **)calloc(argc + 1, sizeof(char *));
	for (int i = 0; i < argc; i++) {
		copy[i] = strdup(argv[i]);
	}
	return everplay_godot_main(argc, copy);
}

/* The view controller that runs the game (+1 retained; Godot's display server finds it too). */
EVERPLAY_EXPORT void *everplay_godot_view_controller() {
	return (__bridge_retained void *)everplay_godot_controller();
}

/* The app's state: 0 inactive, 1 active, 2 entered the background, 3 back from the background. */
EVERPLAY_EXPORT void everplay_godot_app_state(int state) {
	EverPlayGodotOS *os = EverPlayGodotOS::get_singleton();
	if (!os) {
		return;
	}
	switch (state) {
		case 0:
			os->on_focus_out();
			break;
		case 1:
			os->on_focus_in();
			break;
		case 2:
			os->on_enter_background();
			break;
		case 3:
			os->on_exit_background();
			break;
	}
}

EVERPLAY_EXPORT void everplay_godot_memory_warning() {
	if (OS::get_singleton() && OS::get_singleton()->get_main_loop()) {
		OS::get_singleton()->get_main_loop()->notification(MainLoop::NOTIFICATION_OS_MEMORY_WARNING);
	}
}

/* A mouse button (1 left, 2 right, 3 middle, 4/5 wheel up/down) at a point in the game view (points). */
EVERPLAY_EXPORT void everplay_godot_mouse_button(int button, int pressed, float x, float y) {
	if (!Input::get_singleton() || !everplay_godot_view()) {
		return;
	}
	CGFloat scale = everplay_godot_view().contentScaleFactor;
	Vector2 position(x * scale, y * scale);
	Ref<InputEventMouseButton> event;
	event.instantiate();
	event->set_button_index((MouseButton)button);
	event->set_pressed(pressed != 0);
	event->set_position(position);
	event->set_global_position(position);
	BitField<MouseButtonMask> mask = Input::get_singleton()->get_mouse_button_mask();
	MouseButtonMask bit = mouse_button_to_mask((MouseButton)button);
	if (pressed) {
		mask.set_flag(bit);
	} else {
		mask.clear_flag(bit);
	}
	event->set_button_mask(mask);
	Input::get_singleton()->parse_input_event(event);
}

/* A key: Godot's Key code (letters as upper-case ASCII, specials as Key::ESCAPE …), the character it types (0 for none). */
EVERPLAY_EXPORT void everplay_godot_key(int keycode, int unicode, int pressed) {
	if (!Input::get_singleton()) {
		return;
	}
	Ref<InputEventKey> event;
	event.instantiate();
	event->set_keycode((Key)keycode);
	event->set_physical_keycode((Key)keycode);
	event->set_key_label((Key)keycode);
	event->set_unicode(pressed ? (char32_t)unicode : 0);
	event->set_pressed(pressed != 0);
	Input::get_singleton()->parse_input_event(event);
}

/* The game's name from its project settings (valid after everplay_godot_start). */
EVERPLAY_EXPORT int everplay_godot_project_name(char *buffer, int size) {
	if (!ProjectSettings::get_singleton() || size <= 0) {
		return 0;
	}
	CharString name = String(GLOBAL_GET("application/config/name")).utf8();
	snprintf(buffer, size, "%s", name.get_data());
	return 1;
}

// MARK: Cheats: the game's variables

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
