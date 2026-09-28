#import "Overlay.h"
#import "Feature.h"
#import "Log.h"
#import "Scheduler.h"
#import <UIKit/UIKit.h>

// Touches that land on the window itself (not on our controls) fall through to the game.
@interface PAPassWindow : UIWindow
@end
@implementation PAPassWindow
- (UIView *)hitTest:(CGPoint)pt withEvent:(UIEvent *)e {
    UIView *v = [super hitTest:pt withEvent:e];
    if (v == self || v == self.rootViewController.view) return nil;
    return v;
}
@end

static const NSInteger kAutoTag = 1000;      // feature buttons are tagged with their registry index

@interface PAOverlay : NSObject
+ (BOOL)ensure;
@end

static UIWindow *gWin = nil;
static UIButton *gFab = nil;                 // the one handle that is always visible
static UIView *gPanel = nil;                 // the switches, shown only when it is tapped
static UIButton *gAutoBtn = nil;
static NSMutableArray<UIButton *> *gButtons = nil;

@implementation PAOverlay

+ (void)style:(UIButton *)b on:(BOOL)on title:(NSString *)title {
    UIColor *base = on ? UIColor.systemGreenColor : UIColor.systemGrayColor;
    b.backgroundColor = [base colorWithAlphaComponent:on ? 0.9 : 0.85];
    [b setTitle:[NSString stringWithFormat:@"%@ %@", on ? @"☑" : @"☐", title] forState:UIControlStateNormal];
}

+ (void)refresh {
    NSArray<PKFeature *> *features = pkFeatures();
    for (UIButton *b in gButtons) {
        PKFeature *f = features[b.tag];
        [self style:b on:f.enabled title:f.title];
    }
    [self style:gAutoBtn on:pkAutoEnabled() title:@"자동성장"];
}

+ (void)tapFeature:(UIButton *)b { PKFeature *f = pkFeatures()[b.tag]; pkFeatureSetEnabled(f, !f.enabled); }
+ (void)tapAuto { pkAutoSetEnabled(!pkAutoEnabled()); }

+ (void)togglePanel {
    gPanel.hidden = !gPanel.hidden;
    if (!gPanel.hidden) { [self refresh]; [gPanel.superview bringSubviewToFront:gPanel]; }
}

+ (void)drag:(UIPanGestureRecognizer *)g {
    UIView *host = g.view.superview;
    CGPoint t = [g translationInView:host];
    CGPoint c = CGPointMake(g.view.center.x + t.x, g.view.center.y + t.y);
    CGFloat hw = g.view.bounds.size.width / 2, hh = g.view.bounds.size.height / 2;
    c.x = MAX(hw, MIN(host.bounds.size.width - hw, c.x));
    c.y = MAX(hh, MIN(host.bounds.size.height - hh, c.y));
    g.view.center = c;
    [g setTranslation:CGPointZero inView:host];
    if (g.view == gFab && gPanel) {                      // keep the panel under the handle, and on screen
        CGFloat x = MIN(host.bounds.size.width - gPanel.bounds.size.width - 8, MAX(8.0, c.x - gPanel.bounds.size.width + 22));
        CGFloat y = MIN(host.bounds.size.height - gPanel.bounds.size.height - 8, c.y + 28);
        gPanel.frame = CGRectMake(x, y, gPanel.bounds.size.width, gPanel.bounds.size.height);
    }
}

+ (UIButton *)buttonAt:(CGFloat)y in:(UIView *)root width:(CGFloat)w action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = CGRectMake(8, y, w - 16, 36);
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    b.layer.cornerRadius = 9;
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:b];
    return b;
}

+ (UIWindowScene *)scene {
    NSArray *scenes = [UIApplication sharedApplication].connectedScenes.allObjects;
    for (UIScene *s in scenes)
        if ([s isKindOfClass:UIWindowScene.class] && s.activationState == UISceneActivationStateForegroundActive) return (UIWindowScene *)s;
    for (UIScene *s in scenes)
        if ([s isKindOfClass:UIWindowScene.class]) return (UIWindowScene *)s;
    return nil;
}

+ (BOOL)ensure {
    if (gWin) return YES;
    UIWindowScene *scene = [self scene];
    if (!scene) return NO;

    PAPassWindow *win = [[PAPassWindow alloc] initWithWindowScene:scene];
    win.frame = scene.coordinateSpace.bounds;
    win.windowLevel = (UIWindowLevel)1000000;
    win.backgroundColor = UIColor.clearColor;
    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = UIColor.clearColor;
    win.rootViewController = vc;
    win.hidden = NO;
    gWin = win;
    UIView *root = vc.view;
    CGFloat w = win.bounds.size.width;

    // The handle: small, draggable, always on top, the only thing on screen until tapped.
    UIButton *fab = [UIButton buttonWithType:UIButtonTypeSystem];
    fab.frame = CGRectMake(w - 56, 70, 44, 44);
    fab.layer.cornerRadius = 22;
    fab.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.55];
    fab.titleLabel.font = [UIFont systemFontOfSize:20];
    [fab setTitle:@"🌱" forState:UIControlStateNormal];
    [fab addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [fab addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)]];
    fab.layer.zPosition = 100001;
    [root addSubview:fab];
    gFab = fab;

    NSArray<PKFeature *> *features = pkFeatures();
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(w - 190, 120, 178, 8 + (CGFloat)(features.count + 1) * 40)];
    panel.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.72];
    panel.layer.cornerRadius = 12;
    panel.layer.zPosition = 100000;
    panel.hidden = YES;
    [root addSubview:panel];
    gPanel = panel;

    gAutoBtn = [self buttonAt:8 in:panel width:panel.bounds.size.width action:@selector(tapAuto)];
    gAutoBtn.tag = kAutoTag;
    gButtons = [NSMutableArray array];
    for (NSUInteger i = 0; i < features.count; i++) {
        UIButton *b = [self buttonAt:48 + 40 * (CGFloat)i in:panel width:panel.bounds.size.width action:@selector(tapFeature:)];
        b.tag = (NSInteger)i;
        [gButtons addObject:b];
    }
    [[NSNotificationCenter defaultCenter] addObserverForName:PKFeaturesChangedNotification object:nil
                                                       queue:NSOperationQueue.mainQueue
                                                  usingBlock:^(NSNotification *n) { [PAOverlay refresh]; }];
    [self refresh];

    // Keep the handle above whatever the game puts on screen.
    [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t) {
        if (gFab.superview) [gFab.superview bringSubviewToFront:gFab];
        if (gPanel && !gPanel.hidden && gPanel.superview) [gPanel.superview bringSubviewToFront:gPanel];
    }];
    PALOG(@"[ui] overlay ready");
    return YES;
}
@end

BOOL pkOverlayEnsure(void) { return [PAOverlay ensure]; }
