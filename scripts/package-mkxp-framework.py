#!/usr/bin/env python3
"""Links the mkxp-z build from build-mkxp-ios.sh into MKXP.framework, which EverPlay embeds.

The framework exports only everplay_mkxp_main(game folder): it switches into the game folder
(mkxp-z is built with workdir_current, so it reads mkxp.json and Game.ini there) and runs
mkxp-z's main. SDL's window is attached to EverPlay's window scene the same way as for Ren'Py
(SCENE_BRIDGE from package-renpy-runtime.py).

Usage (macOS with Xcode): package-mkxp-framework.py OUTPUT_DIR
"""
import importlib.util
import plistlib
import shlex
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / 'build/mkxp-ios'
BUILD = WORK / 'build'
MINIMUM_IOS = '17.0'
NAME = 'MKXP'

ENTRY = r'''#include <CoreFoundation/CoreFoundation.h>
#include <execinfo.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int SDL_main(int argc, char **argv);
void SDL_SetMainReady(void);
void everplay_attach_sdl_windows(void);
void everplay_install_gamepad(void);

/* mkxp-z's output and, on a crash, the signal and stack go to EVERPLAY_MKXP_LOG, which
   EverPlay reads into its diagnostics log at the next start. */
static void everplay_crash(int signal_number) {
    char line[64];
    int length = snprintf(line, sizeof line, "\nEverPlay: mkxp-z crashed with signal %d\n", signal_number);
    write(STDERR_FILENO, line, (size_t) length);
    void *frames[64];
    int count = backtrace(frames, 64);
    backtrace_symbols_fd(frames, count, STDERR_FILENO);
    signal(signal_number, SIG_DFL);
    raise(signal_number);
}

/* NFC file names for mkxp-z's path cache (its iconv has no "utf-8-mac"). */
void everplay_nfc(char *name, size_t capacity) {
    CFMutableStringRef text = CFStringCreateMutable(NULL, 0);
    CFStringAppendCString(text, name, kCFStringEncodingUTF8);
    CFStringNormalize(text, kCFStringNormalizationFormC);
    char normal[1024];
    if (CFStringGetCString(text, normal, sizeof normal, kCFStringEncodingUTF8) && strlen(normal) < capacity)
        strcpy(name, normal);
    CFRelease(text);
}

__attribute__((visibility("default")))
int everplay_mkxp_main(const char *game) {
    const char *log = getenv("EVERPLAY_MKXP_LOG");
    if (log && freopen(log, "w", stderr)) {
        dup2(fileno(stderr), STDOUT_FILENO);
        setvbuf(stderr, NULL, _IONBF, 0);
        setvbuf(stdout, NULL, _IOLBF, 0);
    }
    int signals[] = { SIGSEGV, SIGBUS, SIGABRT, SIGILL, SIGFPE, SIGTRAP };
    for (unsigned i = 0; i < sizeof signals / sizeof signals[0]; i++) signal(signals[i], everplay_crash);
    if (chdir(game) != 0) {
        fprintf(stderr, "EverPlay: cannot open the game folder\n");
        return 1;
    }
    fprintf(stderr, "EverPlay: starting mkxp-z in %s\n", game);
    /* EverPlay owns UIApplicationMain; SDL runs inside it instead of SDL_UIKitRunApp. */
    SDL_SetMainReady();
    everplay_attach_sdl_windows();
    everplay_install_gamepad();
    char *argv[] = { "mkxp-z", NULL };
    int status = SDL_main(1, argv);
    fprintf(stderr, "EverPlay: mkxp-z returned %d\n", status);
    return status;
}
'''

# Touch controls over the game: a pad for the arrow keys and buttons for RPG Maker's C (confirm),
# B (cancel/menu) and A (dash), sent as the keys of mkxp-z's default bindings.
GAMEPAD = r'''@import UIKit;
#import <objc/runtime.h>

int SDL_SendKeyboardKey(unsigned char state, int scancode);

enum { KEY_RIGHT = 79, KEY_LEFT = 80, KEY_DOWN = 81, KEY_UP = 82, KEY_RETURN = 40, KEY_ESCAPE = 41, KEY_LSHIFT = 225 };

static UIColor *everplay_fill(void) { return [UIColor colorWithWhite:0 alpha:0.35]; }

/* Lets touches outside the controls reach the game. */
@interface EverPlayPassThrough : UIView
@end
@implementation EverPlayPassThrough
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;
}
@end

@interface EverPlayPad : UIView
@property (nonatomic) int horizontal, vertical;
@end
@implementation EverPlayPad
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = everplay_fill();
        self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.35].CGColor;
        self.layer.borderWidth = 1.5;
        NSArray *arrows = @[@"chevron.up", @"chevron.down", @"chevron.left", @"chevron.right"];
        for (NSString *name in arrows) {
            UIImageView *arrow = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:name]];
            arrow.tintColor = [UIColor colorWithWhite:1 alpha:0.8];
            arrow.tag = (NSInteger) [arrows indexOfObject:name] + 1;
            [self addSubview:arrow];
        }
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat size = self.bounds.size.width, inset = size * 0.18;
    self.layer.cornerRadius = size / 2;
    CGPoint centers[] = { {size / 2, inset}, {size / 2, size - inset}, {inset, size / 2}, {size - inset, size / 2} };
    for (int i = 0; i < 4; i++) [self viewWithTag:i + 1].center = centers[i];
}
- (void)setHorizontal:(int)horizontal vertical:(int)vertical {
    if (horizontal != _horizontal) {
        if (_horizontal) SDL_SendKeyboardKey(0, _horizontal < 0 ? KEY_LEFT : KEY_RIGHT);
        if (horizontal) SDL_SendKeyboardKey(1, horizontal < 0 ? KEY_LEFT : KEY_RIGHT);
        _horizontal = horizontal;
    }
    if (vertical != _vertical) {
        if (_vertical) SDL_SendKeyboardKey(0, _vertical < 0 ? KEY_UP : KEY_DOWN);
        if (vertical) SDL_SendKeyboardKey(1, vertical < 0 ? KEY_UP : KEY_DOWN);
        _vertical = vertical;
    }
}
/* Eight directions of 45 degrees each, with a small dead zone in the middle. */
- (void)track:(NSSet<UITouch *> *)touches {
    CGPoint point = [touches.anyObject locationInView:self];
    CGFloat dx = point.x - self.bounds.size.width / 2, dy = point.y - self.bounds.size.height / 2;
    CGFloat distance = hypot(dx, dy);
    if (distance < self.bounds.size.width * 0.12) { [self setHorizontal:0 vertical:0]; return; }
    CGFloat angle = atan2(dy, dx) * 180 / M_PI;
    int sector = (int) lround(angle / 45.0);
    static const int h[] = { -1, -1, 0, 1, 1, 1, 0, -1, -1 }, v[] = { 0, -1, -1, -1, 0, 1, 1, 1, 0 };
    int index = sector + 4;
    [self setHorizontal:h[index] vertical:v[index]];
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self track:touches]; }
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self track:touches]; }
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self setHorizontal:0 vertical:0]; }
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self setHorizontal:0 vertical:0]; }
@end

@interface EverPlayKey : UIView
@property (nonatomic) int scancode;
@property (nonatomic) BOOL down;
@end
@implementation EverPlayKey
+ (instancetype)keyWithTitle:(NSString *)title scancode:(int)scancode {
    EverPlayKey *key = [EverPlayKey new];
    key.scancode = scancode;
    key.backgroundColor = everplay_fill();
    key.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.35].CGColor;
    key.layer.borderWidth = 1.5;
    UILabel *label = [UILabel new];
    label.text = title;
    label.textColor = [UIColor colorWithWhite:1 alpha:0.85];
    label.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    label.textAlignment = NSTextAlignmentCenter;
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [key addSubview:label];
    return key;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.cornerRadius = self.bounds.size.height / 2;
    self.subviews.firstObject.frame = self.bounds;
}
- (void)setDown:(BOOL)down {
    if (down == _down) return;
    _down = down;
    SDL_SendKeyboardKey(down ? 1 : 0, self.scancode);
    self.alpha = down ? 0.6 : 1;
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { self.down = YES; }
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { self.down = NO; }
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { self.down = NO; }
@end

@interface EverPlayGamepad : EverPlayPassThrough
@property (nonatomic, strong) EverPlayPad *pad;
@property (nonatomic, strong) NSArray<EverPlayKey *> *keys;
@property (nonatomic, strong) UIButton *toggle;
@end
@implementation EverPlayGamepad
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.multipleTouchEnabled = YES;
        self.pad = [EverPlayPad new];
        self.keys = @[[EverPlayKey keyWithTitle:@"OK" scancode:KEY_RETURN],
                      [EverPlayKey keyWithTitle:@"Back" scancode:KEY_ESCAPE],
                      [EverPlayKey keyWithTitle:@"Dash" scancode:KEY_LSHIFT]];
        [self addSubview:self.pad];
        for (EverPlayKey *key in self.keys) [self addSubview:key];
        UIButtonConfiguration *style = [UIButtonConfiguration filledButtonConfiguration];
        style.image = [UIImage systemImageNamed:@"gamecontroller"];
        style.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
        style.baseBackgroundColor = everplay_fill();
        style.baseForegroundColor = UIColor.whiteColor;
        self.toggle = [UIButton buttonWithConfiguration:style primaryAction:nil];
        [self.toggle addTarget:self action:@selector(toggleControls) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.toggle];
    }
    return self;
}
- (void)toggleControls {
    BOOL hide = !self.pad.hidden;
    self.pad.hidden = hide;
    for (EverPlayKey *key in self.keys) { key.down = NO; key.hidden = hide; }
    [self.pad setHorizontal:0 vertical:0];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    UIEdgeInsets safe = self.safeAreaInsets;
    CGRect bounds = self.bounds;
    CGFloat unit = MIN(bounds.size.height / 6, 72);
    CGFloat left = safe.left + 16, right = bounds.size.width - safe.right - 16, bottom = bounds.size.height - safe.bottom - 16;
    CGFloat pad = unit * 2.2;
    self.pad.frame = CGRectMake(left, bottom - pad, pad, pad);
    CGFloat key = unit * 1.05;
    self.keys[0].frame = CGRectMake(right - key, bottom - key * 1.9, key, key);
    self.keys[1].frame = CGRectMake(right - key * 2.15, bottom - key, key, key);
    self.keys[2].frame = CGRectMake(right - key * 2.15, bottom - key * 2.6, key * 0.9, key * 0.62);
    self.toggle.frame = CGRectMake(left, safe.top + 12, 44, 36);
}
@end

static UIWindow *everplay_gamepad_window;

void everplay_install_gamepad(void) {
    /* SDL creates its window once mkxp-z starts; look for it from the main run loop. */
    NSTimer *timer = [NSTimer timerWithTimeInterval:0.3 repeats:YES block:^(NSTimer *timer) {
        Class sdlWindow = objc_getClass("SDL_uikitwindow");
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *window in ((UIWindowScene *) scene).windows) {
                if (sdlWindow == Nil || ![window isKindOfClass:sdlWindow] || window == everplay_gamepad_window) continue;
                everplay_gamepad_window = window;
                EverPlayGamepad *gamepad = [[EverPlayGamepad alloc] initWithFrame:window.bounds];
                gamepad.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                [window addSubview:gamepad];
                fprintf(stderr, "EverPlay: touch controls attached\n");
                [timer invalidate];
                return;
            }
        }
    }];
    [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
}
'''


def scene_bridge():
    spec = importlib.util.spec_from_file_location('renpy_packager', ROOT / 'scripts/package-renpy-runtime.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.SCENE_BRIDGE


def executable_link_command():
    """mkxp-z's own executable link line: every static library and framework it needs."""
    targets = subprocess.run(['ninja', '-C', BUILD, '-t', 'targets', 'all'], check=True,
                             capture_output=True, text=True).stdout
    linked = [line.split(':')[0] for line in targets.splitlines()
              if ':' in line and 'LINKER' in line.split(':', 1)[1] and Path(line.split(':')[0]).name.startswith('mkxp-z.')]
    if not linked:
        print('\n'.join(line for line in targets.splitlines() if 'LINKER' in line))
        sys.exit('mkxp-z executable target not found')
    executable = linked[0]
    commands = subprocess.run(['ninja', '-C', BUILD, '-t', 'commands', executable], check=True,
                              capture_output=True, text=True).stdout.strip().splitlines()
    return executable, shlex.split(commands[-1])


def main():
    output = Path(sys.argv[1]).resolve()  # the link runs inside the build folder
    executable, command = executable_link_command()
    # Build everything the executable links (the libraries, Ruby included), but not the executable.
    # Absolute paths are outside Ninja (SDL2 from build-mkxp-ios.sh, Ruby's own make build).
    inputs = [part for part in command if (part.endswith('.a') or part.endswith('.o')) and not part.startswith('/')]
    subprocess.run(['ninja', '-k', '0', '-C', BUILD, *inputs], check=True)
    framework = output / 'Frameworks' / f'{NAME}.framework'
    if framework.exists():
        shutil.rmtree(framework)
    framework.mkdir(parents=True)
    # Ruby's link list names every extension; the ones left out for iOS (pty, syslog) do not exist.
    command = [part for part in command if not (part.startswith('/') and part.endswith('.a') and not Path(part).exists())]
    output_index = command.index('-o')
    del command[output_index:output_index + 2]
    with tempfile.TemporaryDirectory() as temporary:
        work = Path(temporary)
        (work / 'entry.c').write_text(ENTRY)
        (work / 'scene.m').write_text(scene_bridge())
        (work / 'gamepad.m').write_text(GAMEPAD)
        sdk = subprocess.run(['xcrun', '--sdk', 'iphoneos', '--show-sdk-path'], check=True,
                             capture_output=True, text=True).stdout.strip()
        objects = []
        for source in ('entry.c', 'scene.m', 'gamepad.m'):
            target = work / (source + '.o')
            subprocess.run(['xcrun', '-sdk', 'iphoneos', 'clang', '-c', '-arch', 'arm64', f'-mios-version-min={MINIMUM_IOS}',
                            '-isysroot', sdk, '-fobjc-arc', '-fmodules', '-O2', work / source, '-o', target], check=True)
            objects.append(str(target))
        command += [*objects, '-dynamiclib', '-install_name', f'@rpath/{NAME}.framework/{NAME}',
                    '-Wl,-exported_symbol,_everplay_mkxp_main', '-Wl,-dead_strip',
                    '-framework', 'UIKit', '-framework', 'OpenGLES', '-o', str(framework / NAME)]
        print('+', shlex.join(command), flush=True)
        subprocess.run(command, check=True, cwd=BUILD)
    plistlib.dump({'CFBundleExecutable': NAME, 'CFBundleIdentifier': 'app.everplay.runtime.mkxp',
                   'CFBundleName': NAME, 'CFBundlePackageType': 'FMWK', 'CFBundleShortVersionString': '2.4.2',
                   'CFBundleVersion': '1', 'MinimumOSVersion': MINIMUM_IOS,
                   'CFBundleSupportedPlatforms': ['iPhoneOS']},
                  (framework / 'Info.plist').open('wb'))
    print(f'Packaged mkxp-z ({executable}) as {framework}')


if __name__ == '__main__':
    main()
