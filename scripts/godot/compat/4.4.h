/* Godot 4.4 iOS (platform/ios before drivers/apple_embedded): names everplay_godot.mm uses. MIT, like Godot. */
#import "os_ios.h"
#import "app_delegate.h"
#import "godot_view.h"
#import "view_controller.h"

extern int ios_main(int, char **);
/* Added to app_delegate.mm by patch-godot-ios.py: AppDelegate.viewController is read-only. */
void everplay_godot_set_view_controller(ViewController *controller);

typedef OS_IOS EverPlayGodotOS;

static int everplay_godot_main(int argc, char **argv) {
	return ios_main(argc, argv);
}

static UIViewController *everplay_godot_controller() {
	if (!AppDelegate.viewController) {
		ViewController *controller = [[ViewController alloc] init];
		// As Godot's own app delegate sets them up.
		controller.godotView.useCADisplayLink = bool(GLOBAL_DEF("display.iOS/use_cadisplaylink", true)) ? YES : NO;
		controller.godotView.renderingInterval = 1.0 / 60;
		everplay_godot_set_view_controller(controller);
	}
	return AppDelegate.viewController;
}

static UIView *everplay_godot_view() {
	return AppDelegate.viewController.godotView;
}

/* Godot's iOS export generates these for a project's iOS plugins; EverPlay runs games without any. */
void godot_ios_plugins_initialize() {}
void godot_ios_plugins_deinitialize() {}
