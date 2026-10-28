#!/usr/bin/env python3
"""Adapts a Godot 3.6, 4.4 or 4.5–4.7 checkout so its iOS library runs inside EverPlay; usage:
patch-godot-ios.py <godot folder>.

Godot's iOS template is a whole app (its own main() or SwiftUI @main, and its own app delegate).
Inside EverPlay it is a framework: EverPlay presents Godot's view controller
(scripts/godot/everplay_godot.mm with compat/<major.minor>.h; everplay_godot3.mm for Godot 3), user:// points to the game's
visible Saves folder, and quitting the game tells EverPlay instead of being ignored. Every
replacement must match exactly once, so a change upstream stops the build.
"""
import pathlib
import re
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


version_py = (root / 'version.py').read_text(encoding='utf-8')
major = int(re.search(r'^major = (\d+)', version_py, re.M).group(1))
minor = int(re.search(r'^minor = (\d+)', version_py, re.M).group(1))
if (major, minor) < (3, 6) or (major == 4 and minor < 4) or major > 4:
    sys.exit(f'Godot {major}.{minor} is not supported by this patch')
embedded = major == 4 and minor >= 5  # 4.5 moved the iOS code to drivers/apple_embedded

# OS.get_executable_path(): many PC games save next to their .exe. EverPlay names a path in the game's
# Saves folder (EVERPLAY_GODOT_EXECUTABLE), so those saves land there instead of in the read-only app.
patch('drivers/unix/os_unix.cpp', 'String OS_Unix::get_executable_path() const {\n',
      'String OS_Unix::get_executable_path() const {\n'
      '\tif (getenv("EVERPLAY_GODOT_EXECUTABLE")) {\n'
      '\t\treturn String::utf8(getenv("EVERPLAY_GODOT_EXECUTABLE"));\n'
      '\t}\n')

if major == 3:
    # Godot 3: platform/iphone, its own API, user:// given to iphone_main (everplay_godot3.mm).
    shutil.copy(here / 'everplay_godot3.mm', root / 'platform/iphone/everplay_godot.mm')
    patch('platform/iphone/main.m', 'int main(int argc, char *argv[]) {', 'int godot_ios_unused_main(int argc, char *argv[]) {')
    patch('platform/iphone/SCsub', '    "godot_iphone.mm",\n', '    "godot_iphone.mm",\n    "everplay_godot.mm",\n')
    patch('platform/iphone/app_delegate.mm', 'static ViewController *mainViewController = nil;\n',
          'static ViewController *mainViewController = nil;\n\n'
          'void everplay_godot_set_view_controller(ViewController *controller) {\n'
          '\tmainViewController = controller;\n}\n')
    patch('platform/iphone/view_controller.mm', '- (void)viewDidLoad {',
          '- (void)viewDidAppear:(BOOL)animated {\n\t[super viewDidAppear:animated];\n'
          '\t[self.godotView startRendering];\n}\n\n- (void)viewDidLoad {')
    patch('platform/iphone/godot_view_renderer.mm', '@implementation GodotViewRenderer',
          'void everplay_godot_quit_requested();\n\n@implementation GodotViewRenderer')
    patch('platform/iphone/godot_view_renderer.mm', """	OSIPhone::get_singleton()->iterate();
}""", """	if (OSIPhone::get_singleton()->iterate()) {
		everplay_godot_quit_requested();
	}
}""")
    patch('platform/iphone/godot_view.mm', '[UIApplication sharedApplication].delegate.window.windowScene', 'self.window.windowScene')
    print(f'Godot {major}.{minor} patched for EverPlay')
    sys.exit(0)

# EverPlay's entry points, built into the iOS platform library, with this version's iOS classes.
shutil.copy(here / 'everplay_godot.mm', root / 'platform/ios/everplay_godot.mm')
shutil.copy(here / 'compat' / ('4.7.h' if embedded else '4.4.h'), root / 'platform/ios/everplay_godot_compat.h')

if embedded:
    driver = 'drivers/apple_embedded'
    # EverPlay is the app: no SwiftUI @main from Godot.
    (root / driver / 'app.swift').unlink()
    patch('platform/ios/SCsub', '    "main_ios.mm",\n', '    "main_ios.mm",\n    "everplay_godot.mm",\n')
    os_file, renderer, view, os_class = f'{driver}/os_apple_embedded.mm', f'{driver}/godot_view_renderer.mm', \
        f'{driver}/godot_view_apple_embedded.mm', 'OS_AppleEmbedded'
    renderer_class = 'GDTViewRenderer'
else:
    # EverPlay is the app: Godot's main() stays unused.
    patch('platform/ios/main.m', 'int main(int argc, char *argv[]) {', 'int godot_ios_unused_main(int argc, char *argv[]) {')
    patch('platform/ios/SCsub', '    "godot_ios.mm",\n', '    "godot_ios.mm",\n    "everplay_godot.mm",\n')
    os_file, renderer, view, os_class = 'platform/ios/os_ios.mm', 'platform/ios/godot_view_renderer.mm', \
        'platform/ios/godot_view.mm', 'OS_IOS'
    renderer_class = 'GodotViewRenderer'
    # AppDelegate.viewController is read-only; EverPlay creates the view controller (compat/4.4.h).
    patch('platform/ios/app_delegate.mm', 'static ViewController *mainViewController = nil;\n',
          'static ViewController *mainViewController = nil;\n\n'
          'void everplay_godot_set_view_controller(ViewController *controller) {\n'
          '\tmainViewController = controller;\n}\n')
    # Godot's app delegate starts rendering when the app becomes active; inside EverPlay the app is
    # already active, so the view controller starts it once it is on screen (as Godot 4.5+ does).
    patch('platform/ios/view_controller.mm', '- (void)viewDidLoad {',
          '- (void)viewDidAppear:(BOOL)animated {\n\t[super viewDidAppear:animated];\n'
          '\t[self.godotView startRendering];\n}\n\n- (void)viewDidLoad {')

# user:// (saves, settings) in the folder EverPlay names, visible in Files, instead of Documents itself.
patch(os_file, """	static String ret;
	if (ret.is_empty()) {
		NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);""", """	static String ret;
	if (ret.is_empty() && getenv("EVERPLAY_GODOT_USER_DIR")) {
		ret = String::utf8(getenv("EVERPLAY_GODOT_USER_DIR"));
	}
	if (ret.is_empty()) {
		NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);""")

# get_tree().quit(): Godot on iOS ignores it; EverPlay ends the game.
patch(renderer, f'@implementation {renderer_class}', f'void everplay_godot_quit_requested();\n\n@implementation {renderer_class}')
patch(renderer, f"""	{os_class}::get_singleton()->iterate();
}}""", f"""	if ({os_class}::get_singleton()->iterate()) {{
		everplay_godot_quit_requested();
	}}
}}""")

# EverPlay's app delegate has no window property: the view's own window scene instead.
patch(view, '[UIApplication sharedApplication].delegate.window.windowScene', 'self.window.windowScene', count=2 if embedded else 1)

if embedded:
    # Godot rewrites the root view controller's orientation and status bar methods; in EverPlay that
    # is EverPlay's own, and EverPlay's game screen sets them itself.
    patch(f'{driver}/godot_view_controller.mm', """	[self.godotView startRendering];
#ifdef IOS_ENABLED
	[self propagateUIPreferencesToRootViewController];
#endif""", """	[self.godotView startRendering];""")

print(f'Godot {major}.{minor} patched for EverPlay')
