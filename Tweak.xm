// ============================================================================
//  DirectClassInvocationSwitcher.m — Clean & Fixed Programmatic Tweak
// ============================================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static NSTimer *g_invocationTimer = nil;
static BOOL g_invocationState = NO;

@interface DirectClassInvocationManager : NSObject
@end

@implementation DirectClassInvocationManager

+ (void)load {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self startInvocationLoop];
    });
}

+ (void)startInvocationLoop {
    @try {
        if (g_invocationTimer) {
            [g_invocationTimer invalidate];
            g_invocationTimer = nil;
        }
        
        g_invocationTimer = [NSTimer scheduledTimerWithTimeInterval:5.0 
                                                           target:self 
                                                         selector:@selector(handleInvocationTick:) 
                                                         userInfo:nil 
                                                          repeats:YES];
        
        NSLog(@"[DirectInvocation] Programmatic switcher started.");
    } @catch (__unused NSException *e) {}
}

+ (void)handleInvocationTick:(NSTimer *)timer {
    @try {
        UIWindow *keyWindow = nil;
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (w.isKeyWindow) { keyWindow = w; break; }
        }
        #pragma clang diagnostic pop
        if (!keyWindow) return;

        g_invocationState = !g_invocationState;

        // تعريف البلوك بشكل ضعيف لتفادي خطأ الـ retain cycle نهائياً
        __block void (^__weak weakInvokeSwiftUIViews)(NSArray *) = nil;
        void (^strongInvokeSwiftUIViews)(NSArray *) = ^(NSArray *subviews) {
            for (UIView *sub in subviews) {
                NSString *className = NSStringFromClass([sub class]);
                
                if ([className containsString:@"PlatformGroupContainer"] || [className containsString:@"NavigationStackHostingController"]) {
                    [sub setNeedsLayout];
                    [sub layoutIfNeeded];
                    
                    if ([sub respondsToSelector:@selector(updateConstraints)]) {
                        [sub updateConstraints];
                    }
                }
                
                if (sub.subviews.count > 0) {
                    weakInvokeSwiftUIViews(sub.subviews);
                }
            }
        };
        weakInvokeSwiftUIViews = strongInvokeSwiftUIViews;

        strongInvokeSwiftUIViews(keyWindow.subviews);
        
        // التحديث الآمن للـ RootViewController
        UIViewController *rootVC = keyWindow.rootViewController;
        if (rootVC && rootVC.view) {
            [rootVC.view setNeedsLayout];
            [rootVC.view layoutIfNeeded];
        }

    } @catch (__unused NSException *e) {}
}

@end
