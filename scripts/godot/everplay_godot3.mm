/* EverPlay's entry into Godot 3 for iOS (compiled into Godot's platform/iphone library by
 * scripts/patch-godot-ios.py): the same functions as everplay_godot.mm (Godot 4), written against
 * Godot 3's API. Every function is called on the main thread. One game per process: Godot's
 * globals are not reset, so EverPlay closes when the game ends. MIT, like Godot. */

#include "core/os/input.h"
#include "core/os/input_event.h"
#include "core/os/keyboard.h"
#include "core/os/main_loop.h"
#include "core/os/os.h"
#include "core/project_settings.h"
#include "main/main.h"

#import <UIKit/UIKit.h>

#import "app_delegate.h"
#import "godot_view.h"
#import "os_iphone.h"
#import "view_controller.h"

#define EVERPLAY_EXPORT extern "C" __attribute__((visibility("default")))

extern int iphone_main(int, char **, String, String);
/* Added to app_delegate.mm by patch-godot-ios.py: AppDelegate.viewController is read-only. */
void everplay_godot_set_view_controller(ViewController *controller);

/* Godot's iOS export generates these for a project's iOS plugins; EverPlay runs games without any. */
void godot_ios_plugins_initialize() {}
void godot_ios_plugins_deinitialize() {}

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
 * (user://) go to `user_dir`. Returns 0 when Godot is set up. */
EVERPLAY_EXPORT int everplay_godot_start(int argc, const char **argv, const char *user_dir, everplay_godot_quit_fn on_quit) {
	quit_callback = on_quit;
	// Godot keeps pointers into argv for its whole life.
	char **copy = (char **)calloc(argc + 1, sizeof(char *));
	for (int i = 0; i < argc; i++) {
		copy[i] = strdup(argv[i]);
	}
	NSString *cache = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
	// Godot 3 takes user:// as its data folder when it starts.
	return iphone_main(argc, copy, String::utf8(user_dir ? user_dir : ""), String::utf8(cache.UTF8String));
}

/* The view controller that runs the game (+1 retained; Godot's OS finds it too). */
EVERPLAY_EXPORT void *everplay_godot_view_controller() {
	if (!AppDelegate.viewController) {
		ViewController *controller = [[ViewController alloc] init];
		// As Godot's own app delegate sets them up.
		controller.godotView.useCADisplayLink = bool(GLOBAL_DEF("display.iOS/use_cadisplaylink", true)) ? YES : NO;
		controller.godotView.renderingInterval = 1.0 / 60;
		everplay_godot_set_view_controller(controller);
	}
	return (__bridge_retained void *)AppDelegate.viewController;
}

/* The app's state: 0 inactive, 1 active, 2 entered the background, 3 back from the background. */
EVERPLAY_EXPORT void everplay_godot_app_state(int state) {
	OSIPhone *os = OSIPhone::get_singleton();
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
	if (!Input::get_singleton() || !AppDelegate.viewController) {
		return;
	}
	CGFloat scale = AppDelegate.viewController.godotView.contentScaleFactor;
	Vector2 position(x * scale, y * scale);
	Ref<InputEventMouseButton> event;
	event.instance();
	event->set_button_index(button);
	event->set_pressed(pressed != 0);
	event->set_position(position);
	event->set_global_position(position);
	int mask = Input::get_singleton()->get_mouse_button_mask();
	int bit = 1 << (button - 1);
	event->set_button_mask(pressed ? (mask | bit) : (mask & ~bit));
	Input::get_singleton()->parse_input_event(event);
}

/* A key in Godot 4's codes (EverPlay sends the same for every version): Godot 3 marks special keys
 * with bit 24 instead of 22; the codes below are the same. `unicode` is the character it types. */
EVERPLAY_EXPORT void everplay_godot_key(int keycode, int unicode, int pressed) {
	if (!Input::get_singleton()) {
		return;
	}
	const int godot4_special = 1 << 22;
	uint32_t scancode = (keycode & godot4_special) ? ((keycode & ~godot4_special) | SPKEY) : keycode;
	Ref<InputEventKey> event;
	event.instance();
	event->set_scancode(scancode);
	event->set_physical_scancode(scancode);
	event->set_unicode(pressed ? unicode : 0);
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
