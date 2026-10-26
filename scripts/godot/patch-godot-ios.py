#!/usr/bin/env python3
"""Adapts a Godot 4.7 checkout so its iOS library runs inside EverPlay; usage:
patch-godot-ios.py <godot folder>.

Godot's iOS template is a whole app (a SwiftUI @main and its own app delegate). Inside EverPlay
it is a framework: EverPlay presents Godot's view controller (scripts/godot/everplay_godot.mm),
user:// points to the game's visible Saves folder, and quitting the game tells EverPlay instead
of being ignored. Every replacement must match exactly once, so a change upstream stops the build.
"""
import pathlib
import shutil
import sys

root = pathlib.Path(sys.argv[1])
here = pathlib.Path(__file__).resolve().parent


def patch(name, old, new, count=1):
    path = root / name
    text = path.read_text(encoding='utf-8')
    found = text.count(old)
    if found != count:
        sys.exit(f'{name}: expected {count} match(es) of {old!r}, found {found}')
    path.write_text(text.replace(old, new), encoding='utf-8')


# EverPlay is the app: no SwiftUI @main from Godot.
(root / 'drivers/apple_embedded/app.swift').unlink()

# EverPlay's entry points, built into the iOS platform library.
shutil.copy(here / 'everplay_godot.mm', root / 'platform/ios/everplay_godot.mm')
patch('platform/ios/SCsub', '    "main_ios.mm",\n', '    "main_ios.mm",\n    "everplay_godot.mm",\n')

# user:// (saves, settings) in the folder EverPlay names, visible in Files, instead of Documents itself.
patch('drivers/apple_embedded/os_apple_embedded.mm', """	static String ret;
	if (ret.is_empty()) {
		NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);""", """	static String ret;
	if (ret.is_empty() && getenv("EVERPLAY_GODOT_USER_DIR")) {
		ret.append_utf8(getenv("EVERPLAY_GODOT_USER_DIR"));
	}
	if (ret.is_empty()) {
		NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);""")

# get_tree().quit(): Godot on iOS ignores it; EverPlay ends the game.
patch('drivers/apple_embedded/godot_view_renderer.mm', '@implementation GDTViewRenderer',
      'void everplay_godot_quit_requested();\n\n@implementation GDTViewRenderer')
patch('drivers/apple_embedded/godot_view_renderer.mm', """	OS_AppleEmbedded::get_singleton()->iterate();
}""", """	if (OS_AppleEmbedded::get_singleton()->iterate()) {
		everplay_godot_quit_requested();
	}
}""")

# EverPlay's app delegate has no window property: the view's own window scene instead.
patch('drivers/apple_embedded/godot_view_apple_embedded.mm',
      '[UIApplication sharedApplication].delegate.window.windowScene', 'self.window.windowScene', count=2)

# Godot rewrites the root view controller's orientation and status bar methods; in EverPlay that
# is EverPlay's own, and EverPlay's game screen sets them itself.
patch('drivers/apple_embedded/godot_view_controller.mm', """	[self.godotView startRendering];
#ifdef IOS_ENABLED
	[self propagateUIPreferencesToRootViewController];
#endif""", """	[self.godotView startRendering];""")

print('Godot patched for EverPlay')
