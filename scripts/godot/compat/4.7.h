/* Godot 4.5–4.7 iOS (drivers/apple_embedded): names everplay_godot.mm uses. MIT, like Godot. */
#import "os_ios.h"
#import "drivers/apple_embedded/app_delegate_service.h"
#import "drivers/apple_embedded/godot_view_apple_embedded.h"
#import "drivers/apple_embedded/godot_view_controller.h"

extern int apple_embedded_main(int, char **);

typedef OS_AppleEmbedded EverPlayGodotOS;

static int everplay_godot_main(int argc, char **argv) {
	return apple_embedded_main(argc, argv);
}

static UIViewController *everplay_godot_controller() {
	if (!GDTAppDelegateService.viewController) {
		GDTAppDelegateService.viewController = [[GDTViewController alloc] init];
	}
	return GDTAppDelegateService.viewController;
}

static UIView *everplay_godot_view() {
	return GDTAppDelegateService.viewController.godotView;
}

/* Godot's iOS export generates these for a project's iOS plugins; EverPlay runs games without any. */
void godot_apple_embedded_plugins_initialize() {}
void godot_apple_embedded_plugins_deinitialize() {}
