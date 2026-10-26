// Touch controls over a WOLF RPG game: a pad for the arrow keys and buttons for OK (Enter),
// Cancel (Escape) and Shift, sent as SDL key events. A ☰ button opens EverPlay's cheat screen
// (WolfCheats.swift listens for "EverPlayWolfMenu"). Touches elsewhere reach the game as mouse.
@import UIKit;
#import <objc/runtime.h>
#include <stdio.h>

int SDL_SendKeyboardKey(unsigned char state, int scancode);

enum { KEY_RIGHT = 79, KEY_LEFT = 80, KEY_DOWN = 81, KEY_UP = 82, KEY_RETURN = 40, KEY_ESCAPE = 41, KEY_LSHIFT = 225 };

static UIColor *wolf_fill(void) { return [UIColor colorWithWhite:0 alpha:0.35]; }

@interface WolfPassThrough : UIView
@end
@implementation WolfPassThrough
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;
}
@end

@interface WolfPad : UIView
@property (nonatomic) int horizontal, vertical;
@end
@implementation WolfPad
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = wolf_fill();
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
    if (hypot(dx, dy) < self.bounds.size.width * 0.12) { [self setHorizontal:0 vertical:0]; return; }
    int sector = (int) lround(atan2(dy, dx) * 180 / M_PI / 45.0);
    static const int h[] = { -1, -1, 0, 1, 1, 1, 0, -1, -1 }, v[] = { 0, -1, -1, -1, 0, 1, 1, 1, 0 };
    [self setHorizontal:h[sector + 4] vertical:v[sector + 4]];
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self track:touches]; }
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self track:touches]; }
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self setHorizontal:0 vertical:0]; }
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self setHorizontal:0 vertical:0]; }
@end

@interface WolfKey : UIView
@property (nonatomic) int scancode;
@property (nonatomic) BOOL down;
@end
@implementation WolfKey
+ (instancetype)keyWithTitle:(NSString *)title scancode:(int)scancode {
    WolfKey *key = [WolfKey new];
    key.scancode = scancode;
    key.backgroundColor = wolf_fill();
    key.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.35].CGColor;
    key.layer.borderWidth = 1.5;
    UILabel *label = [UILabel new];
    label.text = title;
    label.textColor = [UIColor colorWithWhite:1 alpha:0.85];
    label.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    label.textAlignment = NSTextAlignmentCenter;
    label.adjustsFontSizeToFitWidth = YES;
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [key addSubview:label];
    return key;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.cornerRadius = self.bounds.size.height / 2;
    self.subviews.firstObject.frame = CGRectInset(self.bounds, 4, 0);
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

@interface WolfGamepad : WolfPassThrough
@property (nonatomic, strong) WolfPad *pad;
@property (nonatomic, strong) NSArray<WolfKey *> *keys;
@property (nonatomic, strong) UIButton *toggle, *menu;
@end
@implementation WolfGamepad
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.multipleTouchEnabled = YES;
        self.pad = [WolfPad new];
        self.keys = @[[WolfKey keyWithTitle:@"OK" scancode:KEY_RETURN],
                      [WolfKey keyWithTitle:@"Back" scancode:KEY_ESCAPE],
                      [WolfKey keyWithTitle:@"Shift" scancode:KEY_LSHIFT]];
        [self addSubview:self.pad];
        for (WolfKey *key in self.keys) [self addSubview:key];
        UIButtonConfiguration *style = [UIButtonConfiguration filledButtonConfiguration];
        style.image = [UIImage systemImageNamed:@"gamecontroller"];
        style.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
        style.baseBackgroundColor = wolf_fill();
        style.baseForegroundColor = UIColor.whiteColor;
        self.toggle = [UIButton buttonWithConfiguration:style primaryAction:nil];
        self.toggle.accessibilityLabel = @"Show or hide the touch controls";
        [self.toggle addTarget:self action:@selector(toggleControls) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.toggle];
        style.image = [UIImage systemImageNamed:@"line.3.horizontal"];
        self.menu = [UIButton buttonWithConfiguration:style primaryAction:nil];
        self.menu.accessibilityLabel = @"EverPlay menu";
        [self.menu addTarget:self action:@selector(showMenu) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.menu];
    }
    return self;
}
- (void)showMenu {
    [NSNotificationCenter.defaultCenter postNotificationName:@"EverPlayWolfMenu" object:nil];
}
- (void)toggleControls {
    BOOL hide = !self.pad.hidden;
    self.pad.hidden = hide;
    for (WolfKey *key in self.keys) { key.down = NO; key.hidden = hide; }
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
    self.keys[2].frame = CGRectMake(right - key * 2.15, bottom - key * 2.6, key * 0.95, key * 0.62);
    self.toggle.frame = CGRectMake(left, safe.top + 12, 44, 36);
    self.menu.frame = CGRectMake(left + 52, safe.top + 12, 44, 36);
}
@end

static UIWindow *wolf_gamepad_window;

void everplay_install_wolf_gamepad(void) {
    /* SDL creates its window once the game starts; look for it from the main run loop. */
    NSTimer *timer = [NSTimer timerWithTimeInterval:0.3 repeats:YES block:^(NSTimer *timer) {
        Class sdlWindow = objc_getClass("SDL_uikitwindow");
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *window in ((UIWindowScene *) scene).windows) {
                if (sdlWindow == Nil || ![window isKindOfClass:sdlWindow] || window == wolf_gamepad_window) continue;
                wolf_gamepad_window = window;
                WolfGamepad *gamepad = [[WolfGamepad alloc] initWithFrame:window.bounds];
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
