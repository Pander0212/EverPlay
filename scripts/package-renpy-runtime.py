#!/usr/bin/env python3
"""Turns the renios project produced by build-renpy-ios-prototype.py into parts EverPlay embeds.

One iOS app can carry several Ren'Py runtimes: each becomes a dynamic framework
(Frameworks/RenPyNN.framework) that exports only everplay_renpy_main, so the Python, SDL and
FFmpeg copies inside different runtimes never meet. Only one runtime is loaded per app run.
Its engine files go to Runtimes/NN/base; Ren'Py finds them relative to argv[0].

Usage (macOS with Xcode): package-renpy-runtime.py iphoneos|iphonesimulator OUTPUT_DIR
"""
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
XCODE = ROOT / 'build/renpy-ios/xcode'
RELEASE = os.environ.get('EVERPLAY_RENPY_RUNTIME', '8.5.3')
PLUGIN = ''.join(RELEASE.split('.')[:2])
MINIMUM_IOS = '17.0'
# The 8.x runtimes ship the same MetalANGLE build; other versions get their own renamed copy.
SHARED_ANGLE_SHA256 = '5f861cec64bf298eafff3b698b5af4fd6a9d8d3786ba43b9af3a0804b69b88e6'

ENTRY = r'''#include <dlfcn.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int launcher_main(int argc, char **argv);
void SDL_SetMainReady(void);
void everplay_attach_sdl_windows(void);

/* Runs one game. `runtime` holds base/ (engine, Python library, EverPlay's main.py);
   `game` is the desktop game folder that contains game/. */
__attribute__((visibility("default")))
int everplay_renpy_main(const char *runtime, const char *game) {
    static char program[PATH_MAX];
    snprintf(program, sizeof program, "%s/main", runtime);
    /* Buttons at the bottom edge reach the game before the home indicator gesture. */
    setenv("SDL_IOS_HIDE_HOME_INDICATOR", "2", 0);
    /* EverPlay owns UIApplicationMain; SDL runs inside it instead of SDL_UIKitRunApp. */
    SDL_SetMainReady();
    /* SDL resolves OpenGL ES with dlsym(RTLD_DEFAULT): report which library answers. */
    Dl_info info;
    void *symbol = dlsym(RTLD_DEFAULT, "glGetString");
    fprintf(stderr, "EverPlay: glGetString resolves to %s\n",
            symbol && dladdr(symbol, &info) ? info.dli_fname : "nothing");
    everplay_attach_sdl_windows();
    char *argv[] = { program, (char *) game, NULL };
    return launcher_main(2, argv);
}
'''

# EverPlay is a SwiftUI app with a UIWindowScene; a window created without a scene (as SDL does)
# never appears. Attach SDL's window to the app's scene right before SDL shows it.
# Text input: Ren'Py asks SDL for the on-screen keyboard, which SDL shows through a hidden text
# field. If that keyboard does not come up, a "Type" button appears while the game waits for
# text; it opens an iOS text field and sends the result to the game as typed keys.
SCENE_BRIDGE = r'''@import UIKit;
#import <objc/runtime.h>

int SDL_SendKeyboardText(const char *text);
int SDL_SendKeyboardKey(unsigned char state, int scancode);
unsigned char SDL_EventState(unsigned int type, int state);

enum { EVERPLAY_TEXTINPUT = 0x303, EVERPLAY_RETURN = 40, EVERPLAY_BACKSPACE = 42 };

static IMP everplay_original_show;

/* Appends to EverPlay's diagnostics log (Documents/EverPlay-log.txt). */
static void everplay_note(NSString *message) {
    fprintf(stderr, "EverPlay: %s\n", message.UTF8String);
    NSURL *file = [[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject
                   URLByAppendingPathComponent:@"EverPlay-log.txt"];
    NSString *line = [NSString stringWithFormat:@"%@  %@\n", [[NSISO8601DateFormatter new] stringFromDate:NSDate.date], message];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingToURL:file error:nil];
    if (handle == nil) {
        [line writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:nil];
        return;
    }
    [handle seekToEndOfFile];
    [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
}

static void everplay_press(int scancode) {
    SDL_SendKeyboardKey(1, scancode);
    SDL_SendKeyboardKey(0, scancode);
}

/* Sends text as if typed; `submit` first clears the game's field and presses Return after. */
static void everplay_type(NSString *text, BOOL submit) {
    /* Dismissing the iOS keyboard makes SDL stop text events; the game still wants them. */
    SDL_EventState(EVERPLAY_TEXTINPUT, 1);
    if (submit) {
        for (int i = 0; i < 64; i++) everplay_press(EVERPLAY_BACKSPACE);
    }
    [text enumerateSubstringsInRange:NSMakeRange(0, text.length) options:NSStringEnumerationByComposedCharacterSequences
                          usingBlock:^(NSString *character, NSRange range, NSRange enclosing, BOOL *stop) {
        if (character.length) SDL_SendKeyboardText(character.UTF8String);
    }];
    if (submit) everplay_press(EVERPLAY_RETURN);
    everplay_note([NSString stringWithFormat:@"Typed %lu characters into the game%@", (unsigned long) text.length, submit ? @" and pressed Return" : @""]);
}

@interface EverPlayKeyboard : NSObject
@property (nonatomic, weak) UIWindow *window;
@property (nonatomic, strong) UIButton *button;
@property (nonatomic) BOOL systemKeyboardShown, wanted;
@property (nonatomic) int waiting;
@end

@implementation EverPlayKeyboard

+ (instancetype)shared {
    static EverPlayKeyboard *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [EverPlayKeyboard new]; });
    return shared;
}

- (void)attachTo:(UIWindow *)window {
    if (self.window == window) return;
    self.window = window;
    if (self.button == nil) {
        UIButtonConfiguration *style = [UIButtonConfiguration filledButtonConfiguration];
        style.image = [UIImage systemImageNamed:@"keyboard"];
        style.title = @"Type";
        style.imagePadding = 8;
        style.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
        style.baseBackgroundColor = [UIColor colorWithWhite:0 alpha:0.62];
        style.baseForegroundColor = UIColor.whiteColor;
        self.button = [UIButton buttonWithConfiguration:style primaryAction:nil];
        self.button.accessibilityIdentifier = @"everplayTypeButton";
        [self.button addTarget:self action:@selector(ask) forControlEvents:UIControlEventTouchUpInside];
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserver:self selector:@selector(keyboardShown) name:UIKeyboardDidShowNotification object:nil];
        [center addObserver:self selector:@selector(keyboardHidden) name:UIKeyboardDidHideNotification object:nil];
        NSTimer *timer = [NSTimer timerWithTimeInterval:0.25 target:self selector:@selector(tick) userInfo:nil repeats:YES];
        [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
    }
    self.button.hidden = YES;
    self.button.translatesAutoresizingMaskIntoConstraints = NO;
    [self.button removeFromSuperview];
    [window addSubview:self.button];
    [NSLayoutConstraint activateConstraints:@[
        [self.button.topAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.topAnchor constant:12],
        [self.button.trailingAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.trailingAnchor constant:-16],
    ]];
}

- (void)keyboardShown { self.systemKeyboardShown = YES; }
- (void)keyboardHidden { self.systemKeyboardShown = NO; }

/* SDL's view controller keeps `keyboardVisible` set while the game wants text input. */
- (void)tick {
    UIViewController *controller = self.window.rootViewController;
    BOOL wanted = NO;
    @try {
        wanted = [[controller valueForKey:@"keyboardVisible"] boolValue];
    } @catch (NSException *error) {
        wanted = NO;
    }
    if (wanted != self.wanted) {
        self.wanted = wanted;
        self.waiting = 0;
        everplay_note(wanted ? @"Game asks for text input" : @"Game finished text input");
    }
    BOOL missing = wanted && !self.systemKeyboardShown && controller.presentedViewController == nil;
    self.waiting = missing ? self.waiting + 1 : 0;
    if (self.waiting == 2) {
        /* SDL's hidden text field should own the keyboard by now; ask it once more. */
        @try {
            UITextField *field = [controller valueForKey:@"textField"];
            BOOL focused = [field becomeFirstResponder];
            everplay_note([NSString stringWithFormat:@"iOS keyboard missing; text field in window: %d, focus retry: %d, key window: %d",
                           field.window != nil, focused, self.window.isKeyWindow]);
        } @catch (NSException *error) {
            everplay_note(@"iOS keyboard missing; SDL text field not found");
        }
    }
    BOOL show = self.waiting >= 4;
    if (show && self.button.hidden) [self.window bringSubviewToFront:self.button];
    self.button.hidden = !show;
}

- (void)ask {
    UIViewController *controller = self.window.rootViewController;
    if (controller == nil || controller.presentedViewController != nil) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Text for the game"
                                                                   message:@"Enter replaces the game's text field and confirms it."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.autocapitalizationType = UITextAutocapitalizationTypeWords;
        field.returnKeyType = UIReturnKeyDone;
    }];
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Add without Enter" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        everplay_type(weakAlert.textFields.firstObject.text ?: @"", NO);
    }]];
    UIAlertAction *enter = [UIAlertAction actionWithTitle:@"Enter" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        everplay_type(weakAlert.textFields.firstObject.text ?: @"", YES);
    }];
    [alert addAction:enter];
    alert.preferredAction = enter;
    self.button.hidden = YES;
    [controller presentViewController:alert animated:YES completion:nil];
}

@end

static void everplay_show(UIWindow *self, SEL command) {
    if (self.windowScene == nil) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:UIWindowScene.class]) {
                self.windowScene = (UIWindowScene *) scene;
                self.frame = self.windowScene.coordinateSpace.bounds;
                break;
            }
        }
    }
    ((void (*)(id, SEL)) everplay_original_show)(self, command);
    [[EverPlayKeyboard shared] attachTo:self];
}

void everplay_attach_sdl_windows(void) {
    Class window = objc_getClass("SDL_uikitwindow");
    if (window == Nil || everplay_original_show != NULL) return;
    SEL show = @selector(makeKeyAndVisible);
    Method inherited = class_getInstanceMethod(window, show);
    everplay_original_show = method_getImplementation(inherited);
    if (!class_addMethod(window, show, (IMP) everplay_show, method_getTypeEncoding(inherited))) {
        everplay_original_show = method_setImplementation(class_getInstanceMethod(window, show), (IMP) everplay_show);
    }
}
'''


def run(*command):
    print('+', ' '.join(str(c) for c in command), flush=True)
    subprocess.run([str(c) for c in command], check=True)


def link_flags():
    project = (XCODE / 'EverPlayRenPyProbe.xcodeproj/project.pbxproj').read_text()
    block = re.search(r'OTHER_LDFLAGS = \((.*?)\);', project, re.S)
    libraries = re.findall(r'"(-l[^"]+)"', block.group(1))
    frameworks = sorted(set(re.findall(r'name = (\w+)\.framework; path = System/Library/Frameworks', project)))
    # Pulled in by the prototype's Objective-C (StoreKit, video playback) and by SDL itself.
    frameworks = sorted(set(frameworks) | {'AVFoundation', 'StoreKit', 'Metal', 'CoreMedia',
                                           'CoreVideo', 'CoreAudio', 'CoreHaptics', 'AVKit', 'Security'})
    assert '-lrenpython' in libraries, 'unexpected renios link settings'
    return libraries, frameworks


def objective_c_sources(work):
    sources = []
    for name in ('Log.m', 'IAPHelper.m', 'VideoPlayer.m'):
        text = (XCODE / name).read_text()
        if name == 'Log.m':
            # The plugin-app URL bridge hooks SDL's own app delegate, which EverPlay does not use.
            text = text.split('\n@import UIKit;\n#import <objc/runtime.h>', 1)[0]
        path = work / name
        path.write_text(text)
        sources.append(path)
    return sources


def angle(sdk, output):
    """Returns (framework name, path) of the MetalANGLE to link, copying it into output."""
    slice_name = 'ios-arm64_armv7' if sdk == 'iphoneos' else 'ios-arm64_i386_x86_64-simulator'
    source = XCODE / 'Frameworks/MetalANGLE.xcframework' / slice_name / 'MetalANGLE.framework'
    digest = subprocess.run(['shasum', '-a', '256', str(XCODE / 'Frameworks/MetalANGLE.xcframework/ios-arm64_armv7/MetalANGLE.framework/MetalANGLE')],
                            check=True, capture_output=True, text=True).stdout.split()[0]
    # EverPlay links MetalANGLE directly so it precedes any system GLES library in symbol
    # lookups; every runtime therefore shares the 8.x build (same MGLContext API).
    name = 'MetalANGLE'
    target = output / 'Frameworks' / f'{name}.framework'
    if digest != SHARED_ANGLE_SHA256:
        if not target.exists():
            raise SystemExit(f'Package an 8.x runtime first: Ren\'Py {RELEASE} links the shared 8.x MetalANGLE')
        print(f'Note: Ren\'Py {RELEASE} ships a different MetalANGLE; linking the shared 8.x build')
        return name, target
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(source, target, symlinks=True)
    shutil.rmtree(target / 'Headers', ignore_errors=True)
    binary = target / 'MetalANGLE'
    if sdk == 'iphoneos':
        run('lipo', binary, '-thin', 'arm64', '-output', binary)
    with (target / 'Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    info.update(MinimumOSVersion=MINIMUM_IOS)
    with (target / 'Info.plist').open('wb') as stream:
        plistlib.dump(info, stream)
    return name, target


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ('iphoneos', 'iphonesimulator'):
        raise SystemExit(__doc__)
    sdk, output = sys.argv[1], Path(sys.argv[2]).resolve()
    arch = 'arm64' if sdk == 'iphoneos' else os.environ.get('EVERPLAY_SIMULATOR_ARCH', 'x86_64')
    prebuilt = XCODE / 'prebuilt' / ('release' if sdk == 'iphoneos' else 'debug')
    libraries, frameworks = link_flags()
    # The app link drops unused objects; a dynamic library must resolve everything it keeps.
    libraries += [f'-l{lib}' for lib in ('sharpyuv',) if (prebuilt / f'lib{lib}.a').exists()]
    name = f'RenPy{PLUGIN}'
    framework = output / 'Frameworks' / f'{name}.framework'
    if framework.exists():
        shutil.rmtree(framework)
    framework.mkdir(parents=True)
    angle_name, angle_path = angle(sdk, output)
    version_flag = f'-mios-version-min={MINIMUM_IOS}' if sdk == 'iphoneos' else f'-mios-simulator-version-min={MINIMUM_IOS}'
    with tempfile.TemporaryDirectory() as temporary:
        work = Path(temporary)
        (work / 'entry.c').write_text(ENTRY)
        (work / 'scene.m').write_text(SCENE_BRIDGE)
        command = ['xcrun', '-sdk', sdk, 'clang', '-dynamiclib', '-arch', arch, version_flag,
                   '-fobjc-arc', '-fmodules', '-O2',
                   work / 'entry.c', work / 'scene.m', *objective_c_sources(work),
                   '-L', prebuilt, *libraries, '-lc++',
                   '-F', angle_path.parent, '-framework', angle_name,
                   *[part for item in frameworks for part in ('-framework', item)],
                   '-install_name', f'@rpath/{name}.framework/{name}',
                   '-Wl,-exported_symbol,_everplay_renpy_main', '-Wl,-dead_strip',
                   '-o', framework / name]
        run(*command)
    plistlib.dump({'CFBundleExecutable': name, 'CFBundleIdentifier': f'app.everplay.runtime.renpy{PLUGIN}',
                   'CFBundleName': name, 'CFBundlePackageType': 'FMWK', 'CFBundleShortVersionString': RELEASE,
                   'CFBundleVersion': '1', 'MinimumOSVersion': MINIMUM_IOS,
                   'CFBundleSupportedPlatforms': ['iPhoneOS' if sdk == 'iphoneos' else 'iPhoneSimulator']},
                  (framework / 'Info.plist').open('wb'))
    runtime = output / 'Runtimes' / PLUGIN
    if runtime.exists():
        shutil.rmtree(runtime)
    shutil.copytree(XCODE / 'base', runtime / 'base', symlinks=True)
    (runtime / 'version.txt').write_text(RELEASE + '\n')
    print(f'Packaged Ren\'Py {RELEASE} as {framework} and {runtime}')


if __name__ == '__main__':
    main()
