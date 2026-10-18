// ============================================================================
//  LocalActionSniffer.m — Local UI Actions & Methods Tracker (Fixed & Clean)
// ============================================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static UIView     *g_localOverlay     = nil;
static UITextView *g_localOverlayText = nil;
static NSMutableArray<NSString *> *g_actionLogs = nil;

static void local_log_action(NSString *actionDesc) {
    if (!g_actionLogs) g_actionLogs = [NSMutableArray array];
    
    [g_actionLogs insertObject:actionDesc atIndex:0];
    if (g_actionLogs.count > 40) [g_actionLogs removeLastObject];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!g_localOverlayText) return;
        NSMutableString *s = [NSMutableString stringWithFormat:@"Local Actions Tracker (%lu)\n=====================================\n", (unsigned long)g_actionLogs.count];
        for (NSString *item in g_actionLogs) {
            [s appendFormat:@"%@\n-------------------------------------\n", item];
        }
        g_localOverlayText.text = s;
    });
}

// ============================================================================
// SECTION 1 — Intercepting UIControl (Buttons & Taps)
// ============================================================================

@interface UIControl (ActionSniffer)
@end

@implementation UIControl (ActionSniffer)

- (void)sniffer_sendAction:(SEL)action to:(id)target forEvent:(UIEvent *)event {
    NSString *targetClass = NSStringFromClass([target class]);
    NSString *senderClass = NSStringFromClass([self class]);
    NSString *actionSel = NSStringFromSelector(action);
    
    NSString *btnTitle = nil;
    if ([self isKindOfClass:[UIButton class]]) {
        btnTitle = [(UIButton *)self titleForState:UIControlStateNormal];
    }
    
    NSString *logMsg = [NSString stringWithFormat:@"[Button Tap] ➔ Title: '%@' | Sender: %@ | Target: %@ | Selector: %@", 
                        btnTitle ?: @"No Title", senderClass, targetClass, actionSel];
    
    local_log_action(logMsg);
    NSLog(@"[LocalSniffer] %@", logMsg);
    
    [self sniffer_sendAction:action to:target forEvent:event];
}

@end

// ============================================================================
// SECTION 2 — Intercepting UIViewController Transitions (Navigation / Views)
// ============================================================================

@interface UIViewController (ActionSniffer)
@end

@implementation UIViewController (ActionSniffer)

- (void)sniffer_viewDidAppear:(BOOL)animated {
    [self sniffer_viewDidAppear:animated];
    
    NSString *vcName = NSStringFromClass([self class]);
    if (![vcName hasPrefix:@"UI"] && ![vcName hasPrefix:@"_"]) {
        NSString *logMsg = [NSString stringWithFormat:@"[View Opened] ➔ UIViewController: %@", vcName];
        local_log_action(logMsg);
        NSLog(@"[LocalSniffer] %@", logMsg);
    }
}

@end

// ============================================================================
// SECTION 3 — Setup Overlay UI on Screen
// ============================================================================

@interface LocalSnifferInstaller : NSObject
@end

@implementation LocalSnifferInstaller

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // 1. Swizzle UIControl sendAction
        Method m1 = class_getInstanceMethod([UIControl class], @selector(sendAction:to:forEvent:));
        Method m2 = class_getInstanceMethod([UIControl class], @selector(sniffer_sendAction:to:forEvent:));
        if (m1 && m2) method_exchangeImplementations(m1, m2);

        // 2. Swizzle UIViewController viewDidAppear
        Method v1 = class_getInstanceMethod([UIViewController class], @selector(viewDidAppear:));
        Method v2 = class_getInstanceMethod([UIViewController class], @selector(sniffer_viewDidAppear:));
        if (v1 && v2) method_exchangeImplementations(v1, v2);

        // بناء الواجهة بعد تشغيل التطبيق
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self setupOverlay];
        });
    });
}

+ (void)setupOverlay {
    @try {
        UIWindow *keyWindow = nil;
        if (@available(iOS 13.0, *)) {
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]]) {
                    UIWindowScene *ws = (UIWindowScene *)scene;
                    for (UIWindow *w in ws.windows) {
                        if (w.isKeyWindow) { keyWindow = w; break; }
                    }
                }
            }
        }
        
        if (!keyWindow) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Wdeprecated-declarations"
            for (UIWindow *w in [UIApplication sharedApplication].windows) {
                if (w.isKeyWindow) { keyWindow = w; break; }
            }
            #pragma clang diagnostic pop
        }
        
        if (!keyWindow) return;

        CGRect b = keyWindow.bounds;
        g_localOverlay = [[UIView alloc] initWithFrame:CGRectMake(10, 370, b.size.width - 20, 280)];
        g_localOverlay.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.95];
        g_localOverlay.layer.cornerRadius = 10;
        g_localOverlay.layer.borderWidth = 1.5;
        g_localOverlay.layer.borderColor = [UIColor cyanColor].CGColor;
        g_localOverlay.userInteractionEnabled = YES;

        g_localOverlayText = [[UITextView alloc] initWithFrame:CGRectMake(5, 5, g_localOverlay.bounds.size.width - 10, g_localOverlay.bounds.size.height - 10)];
        g_localOverlayText.backgroundColor = [UIColor clearColor];
        g_localOverlayText.textColor = [UIColor cyanColor];
        g_localOverlayText.font = [UIFont fontWithName:@"Courier-Bold" size:8.0] ?: [UIFont systemFontOfSize:8.0];
        g_localOverlayText.editable = NO;
        g_localOverlayText.text = @"[+] Local Action Sniffer Online. Tap buttons/open pages...\n";

        [g_localOverlay addSubview:g_localOverlayText];
        [keyWindow addSubview:g_localOverlay];
        [keyWindow bringSubviewToFront:g_localOverlay];
    } @catch (__unused NSException *e) {}
}

@end
