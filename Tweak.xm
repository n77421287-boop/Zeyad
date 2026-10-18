// ============================================================================
//  InternalAppActionsSniffer.m — Top Overlay Version
// ============================================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static UIView     *g_internalOverlay     = nil;
static UITextView *g_internalOverlayText = nil;
static NSMutableArray<NSString *> *g_internalLogs = nil;

static void internal_log(NSString *desc) {
    if (!g_internalLogs) g_internalLogs = [NSMutableArray array];
    [g_internalLogs insertObject:desc atIndex:0];
    if (g_internalLogs.count > 40) [g_internalLogs removeLastObject];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!g_internalOverlayText) return;
        NSMutableString *s = [NSMutableString stringWithFormat:@"Internal Actions Tracker (%lu)\n=====================================\n", (unsigned long)g_internalLogs.count];
        for (NSString *item in g_internalLogs) {
            [s appendFormat:@"%@\n-------------------------------------\n", item];
        }
        g_internalOverlayText.text = s;
    });
}

// ============================================================================
// SECTION 1 — Intercepting NSNotificationCenter (App Internal Triggers & Events)
// ============================================================================

@interface NSNotificationCenter (InternalSniffer)
@end

@implementation NSNotificationCenter (InternalSniffer)

- (void)sniffer_postNotificationName:(NSNotificationName)aName object:(id)anObject userInfo:(NSDictionary *)aUserInfo {
    NSString *nameStr = [aName description];
    if (![nameStr hasPrefix:@"UI"] && ![nameStr hasPrefix:@"NS"] && ![nameStr hasPrefix:@"_"]) {
        NSString *logMsg = [NSString stringWithFormat:@"🔔 [Notification] Name: %@", nameStr];
        internal_log(logMsg);
    }
    [self sniffer_postNotificationName:aName object:anObject userInfo:aUserInfo];
}

@end

// ============================================================================
// SECTION 2 — Intercepting UIViewController Actions & Lifecycle
// ============================================================================

@interface UIViewController (InternalSniffer)
@end

@implementation UIViewController (InternalSniffer)

- (void)sniffer_viewDidLoad {
    [self sniffer_viewDidLoad];
    NSString *vcName = NSStringFromClass([self class]);
    if (![vcName hasPrefix:@"UI"] && ![vcName hasPrefix:@"_"]) {
        NSString *logMsg = [NSString stringWithFormat:@"📱 [ViewController Load] ➔ %@", vcName];
        internal_log(logMsg);
    }
}

- (void)sniffer_viewDidAppear:(BOOL)animated {
    [self sniffer_viewDidAppear:animated];
    NSString *vcName = NSStringFromClass([self class]);
    if (![vcName hasPrefix:@"UI"] && ![vcName hasPrefix:@"_"]) {
        NSString *logMsg = [NSString stringWithFormat:@"👁️ [View Active] ➔ %@", vcName];
        internal_log(logMsg);
    }
}

@end

// ============================================================================
// SECTION 3 — Setup Overlay UI at the TOP of the screen
// ============================================================================

@interface InternalSnifferInstaller : NSObject
@end

@implementation InternalSnifferInstaller

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Method n1 = class_getInstanceMethod([NSNotificationCenter class], @selector(postNotificationName:object:userInfo:));
        Method n2 = class_getInstanceMethod([NSNotificationCenter class], @selector(sniffer_postNotificationName:object:userInfo:));
        if (n1 && n2) method_exchangeImplementations(n1, n2);

        Method v1 = class_getInstanceMethod([UIViewController class], @selector(viewDidLoad));
        Method v2 = class_getInstanceMethod([UIViewController class], @selector(sniffer_viewDidLoad));
        if (v1 && v2) method_exchangeImplementations(v1, v2);

        Method a1 = class_getInstanceMethod([UIViewController class], @selector(viewDidAppear:));
        Method a2 = class_getInstanceMethod([UIViewController class], @selector(sniffer_viewDidAppear:));
        if (a1 && a2) method_exchangeImplementations(a1, a2);

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self setupOverlay];
        });
    });
}

+ (void)setupOverlay {
    @try {
        UIWindow *keyWindow = nil;
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (w.isKeyWindow) { keyWindow = w; break; }
        }
        #pragma clang diagnostic pop
        if (!keyWindow) return;

        CGRect b = keyWindow.bounds;
        
        // تعديل الإحداثيات لتكون في أعلى الشاشة تماماً (Y = 40 لتكون تحت الساعة وشريط الحالة)
        g_internalOverlay = [[UIView alloc] initWithFrame:CGRectMake(10, 40, b.size.width - 20, 220)];
        g_internalOverlay.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.95];
        g_internalOverlay.layer.cornerRadius = 10;
        g_internalOverlay.layer.borderWidth = 1.5;
        g_internalOverlay.layer.borderColor = [UIColor orangeColor].CGColor;
        g_internalOverlay.userInteractionEnabled = YES;
        g_internalOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth;

        g_internalOverlayText = [[UITextView alloc] initWithFrame:CGRectMake(5, 5, g_internalOverlay.bounds.size.width - 10, g_internalOverlay.bounds.size.height - 10)];
        g_internalOverlayText.backgroundColor = [UIColor clearColor];
        g_internalOverlayText.textColor = [UIColor orangeColor];
        g_internalOverlayText.font = [UIFont fontWithName:@"Courier-Bold" size:8.0] ?: [UIFont systemFontOfSize:8.0];
        g_internalOverlayText.editable = NO;
        g_internalOverlayText.text = @"[+] Top Tracker Ready...\n";
        g_internalOverlayText.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

        [g_internalOverlay addSubview:g_internalOverlayText];
        [keyWindow addSubview:g_internalOverlay];
        [keyWindow bringSubviewToFront:g_internalOverlay];
    } @catch (__unused NSException *e) {}
}

@end
