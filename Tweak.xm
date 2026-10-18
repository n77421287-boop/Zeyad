// ============================================================================
//  DirectClassInvocationSwitcher.m — Pure Programmatic Class Invocation Tweak
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
        
        // مؤقت زمني يستدعي الكلاسات برمجياً كل 5 ثوانٍ بدقة
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

        // البحث والاستدعاء المباشر للكلاسات النشطة في شجرة الـ Views في الذاكرة
        void (^__block invokeSwiftUIViews)(NSArray *) = ^(NSArray *subviews) {
            for (UIView *sub in subviews) {
                NSString *className = NSStringFromClass([sub class]);
                
                // استهداف كلاسات الـ SwiftUI الفعلية التي استخرجناها
                if ([className containsString:@"PlatformGroupContainer"] || [className containsString:@"NavigationStackHostingController"]) {
                    
                    // الاستدعاء البرمجي المباشر لتحديث الحالة وإجبار الـ View على إعادة التحميل والتبديل
                    [sub setNeedsLayout];
                    [sub layoutIfNeeded];
                    
                    // محاولة استدعاء ميثودات التحديث الخاصة بالـ SwiftUI إن وجدت في وقت التشغيل
                    if ([sub respondsToSelector:@selector(updateConstraints)]) {
                        [sub updateConstraints];
                    }
                    
                    NSLog(@"[DirectInvocation] Invoked class programmatically: %@", className);
                }
                
                if (sub.subviews.count > 0) {
                    invokeSwiftUIViews(sub.subviews);
                }
            }
        };

        invokeSwiftUIViews(keyWindow.subviews);
        
        // استدعاء مباشر على مستوى الـ RootViewController لتحديث الـ Navigation Stack برمجياً
        UIViewController *rootVC = keyWindow.rootViewController;
        if (rootVC) {
            [rootVC setNeedsUpdateOfHomeIndicatorAutoHide];
            // إجبار متحكم العرض الرئيسي على إعادة رسم الـ Container برمجياً
            [rootVC.view setNeedsDisplay];
        }

    } @catch (__unused NSException *e) {}
}

@end
