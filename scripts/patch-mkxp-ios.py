#!/usr/bin/env python3
"""Adapts a mkxp-z checkout (dev branch) for iPhone; usage: patch-mkxp-ios.py <mkxp-z folder>.

mkxp-z's Apple code is written for macOS (AppKit, the Touch Bar, a Cocoa settings window and a
folder picker). For iOS (-DMKXPZ_IOS) the macOS-only parts are left out: mkxp-z's own SDL
settings menu takes the place of the Cocoa one, and the system and file helpers use Foundation
and UIKit. Every replacement must match exactly once, so a change upstream stops the build.
"""
import pathlib
import sys

root = pathlib.Path(sys.argv[1])


def patch(name, old, new, count=1):
    path = root / name
    text = path.read_text(encoding='utf-8')
    found = text.count(old)
    if found != count:
        sys.exit(f'{name}: expected {count} match(es) of {old!r}, found {found}')
    path.write_text(text.replace(old, new), encoding='utf-8')


MAC_ONLY = 'defined(__APPLE__) && !defined(MKXPZ_IOS)'
NOT_MAC = '!defined(__APPLE__) || defined(MKXPZ_IOS)'

# Top-level build: UIKit instead of AppKit, no macOS views or app bundle.
patch('meson.build', """if host_system == 'darwin'
    global_dependencies += dependency(
        'appleframeworks',
        modules: [
            'AppKit',""", """mkxpz_ios = host_system == 'darwin' and meson.get_compiler('cpp').compute_int('!!TARGET_OS_IPHONE', prefix: '#include <TargetConditionals.h>', low: 0, high: 1) == 1
if mkxpz_ios
    global_args += '-DMKXPZ_IOS'
    global_dependencies += dependency('appleframeworks', modules: ['UIKit', 'Foundation', 'GameController', 'OpenGLES', 'QuartzCore', 'AVFoundation', 'AudioToolbox', 'CoreAudio', 'CoreMotion', 'CoreHaptics', 'Metal'], required: true)
elif host_system == 'darwin'
    global_dependencies += dependency(
        'appleframeworks',
        modules: [
            'AppKit',""")

for name in ['src/main.cpp', 'src/eventthread.cpp']:
    path = root / name
    text = path.read_text(encoding='utf-8')
    text = text.replace('#ifdef __APPLE__', f'#if {MAC_ONLY}').replace('#ifndef __APPLE__', f'#if {NOT_MAC}')
    path.write_text(text, encoding='utf-8')

patch('src/system/system.h', """#ifdef __APPLE__
void openSettingsWindow();""", f"""#if {MAC_ONLY}
void openSettingsWindow();""")

# File helpers: Foundation only; there is no folder picker on iOS.
patch('src/filesystem/filesystemImplApple.mm', '#import <AppKit/AppKit.h>\n#import <SDL_syswm.h>',
      '#import <Foundation/Foundation.h>\n#ifndef MKXPZ_IOS\n#import <AppKit/AppKit.h>\n#import <SDL_syswm.h>\n#endif')
# selectPath (macOS folder picker) is the last function in the file.
patch('src/filesystem/filesystemImplApple.mm', """std::string filesystemImpl::selectPath(SDL_Window *win, const char *msg, const char *prompt) {
    @autoreleasepool {""", """std::string filesystemImpl::selectPath(SDL_Window *win, const char *msg, const char *prompt) {
#ifdef MKXPZ_IOS
    return std::string();
}
#else
    @autoreleasepool {""")
path = root / 'src/filesystem/filesystemImplApple.mm'
path.write_text(path.read_text(encoding='utf-8').rstrip('\n') + '\n#endif\n', encoding='utf-8')

# System helpers: screen scale from UIKit, no Cocoa settings window.
patch('src/system/systemImplApple.mm', '#import <AppKit/AppKit.h>',
      '#ifdef MKXPZ_IOS\n#import <UIKit/UIKit.h>\n#else\n#import <AppKit/AppKit.h>\n#endif')
patch('src/system/systemImplApple.mm', '#import "SettingsMenuController.h"',
      '#ifndef MKXPZ_IOS\n#import "SettingsMenuController.h"\n#endif')
patch('src/system/systemImplApple.mm', """int systemImpl::getScalingFactor() {
    return NSApplication.sharedApplication.mainWindow.backingScaleFactor;
}""", """int systemImpl::getScalingFactor() {
#ifdef MKXPZ_IOS
    return (int) UIScreen.mainScreen.scale;
#else
    return NSApplication.sharedApplication.mainWindow.backingScaleFactor;
#endif
}""")
patch('src/system/systemImplApple.mm', """// constant, if it's not nil then just raise the menu instead
SettingsMenu *smenu = nil;""", """#ifndef MKXPZ_IOS
// constant, if it's not nil then just raise the menu instead
SettingsMenu *smenu = nil;""")
path = root / 'src/system/systemImplApple.mm'
path.write_text(path.read_text(encoding='utf-8').rstrip('\n') + '\n#endif\n', encoding='utf-8')

# Ruby: iOS declares getentropy only in <sys/random.h>, which random.c does not include, and
# forbids fork, vfork, system and daemon. Without them Ruby spawns processes with posix_spawn.
patch('subprojects/packagefiles/ruby-3.1/meson.build', """                'ac_cv_func_crypt': 'no',""", """                'ac_cv_func_crypt': 'no',
                'ac_cv_func_getentropy': 'no',
                'ac_cv_func_fork': 'no',
                'ac_cv_func_vfork': 'no',
                'ac_cv_func_system': 'no',
                'ac_cv_func_daemon': 'no',""")

print('mkxp-z patched for iOS')
