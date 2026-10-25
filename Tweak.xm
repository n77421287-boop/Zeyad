#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>

// دالة عادية للبحث المتكرر لتجنب مشاكل الـ Retain Cycle تماماً
static void searchAndTrigger(UIView *view) {
    for (UIView *subview in view.subviews) {
        id target = subview;
        
        if ([target respondsToSelector:@selector(onEvent)]) {
            ((void (*)(id, SEL))objc_msgSend)(target, @selector(onEvent));
        }
        
        if (subview.subviews.count > 0) {
            searchAndTrigger(subview);
        }
    }
}

static void triggerEventAutomatically(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer * _Nonnull t) {
            for (UIWindow *window in [[UIApplication sharedApplication] windows]) {
                if (!window.isKeyWindow) continue;
                searchAndTrigger(window);
            }
        }];
    });
}

%hook UIApplication

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    BOOL orig = %orig;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        triggerEventAutomatically();
    });
    
    return orig;
}

%end
