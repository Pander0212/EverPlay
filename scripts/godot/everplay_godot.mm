/* EverPlay's entry into Godot 4 for iOS (compiled into Godot's platform/ios library by
 * scripts/patch-godot-ios.py). Godot normally owns the app (its own main() and app delegate);
 * inside EverPlay it gets a view controller to present, and EverPlay forwards the app's state.
 * Every function is called on the main thread. One game per process: Godot's globals are not
 * reset, so EverPlay closes when the game ends. MIT, like Godot. */

#import "os_ios.h"

#include "core/config/project_settings.h"
#include "core/input/input.h"
#include "core/input/input_event.h"
#import "drivers/apple_embedded/app_delegate_service.h"
#import "drivers/apple_embedded/display_server_apple_embedded.h"
#import "drivers/apple_embedded/godot_view_apple_embedded.h"
#import "drivers/apple_embedded/godot_view_controller.h"
#include "main/main.h"

#import <UIKit/UIKit.h>

#define EVERPLAY_EXPORT extern "C" __attribute__((visibility("default")))

extern int apple_embedded_main(int, char **);

typedef void (*everplay_godot_quit_fn)(int code);
static everplay_godot_quit_fn quit_callback = nullptr;
static bool quitting = false;

/* Called by the patched GDTViewRenderer when Godot's main loop asks to quit (iOS Godot never does). */
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
	return apple_embedded_main(argc, copy);
}

/* The view controller that runs the game (+1 retained; Godot's display server finds it too). */
EVERPLAY_EXPORT void *everplay_godot_view_controller() {
	if (!GDTAppDelegateService.viewController) {
		GDTAppDelegateService.viewController = [[GDTViewController alloc] init];
	}
	return (__bridge_retained void *)GDTAppDelegateService.viewController;
}

/* The app's state: 0 inactive, 1 active, 2 entered the background, 3 back from the background. */
EVERPLAY_EXPORT void everplay_godot_app_state(int state) {
	OS_AppleEmbedded *os = OS_AppleEmbedded::get_singleton();
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
	if (!Input::get_singleton() || !GDTAppDelegateService.viewController) {
		return;
	}
	CGFloat scale = GDTAppDelegateService.viewController.godotView.contentScaleFactor;
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
