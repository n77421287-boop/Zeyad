#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>

static void triggerEventAutomatically(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer * _Nonnull t) {
            
            for (UIWindow *window in [[UIApplication sharedApplication] windows]) {
                if (!window.isKeyWindow) continue;
                
                // إضافة __block لتعريف البلوك المتكرر بشكل صحيح للمترجم
                __block void (^searchViews)(UIView *) = nil;
                searchViews = ^(UIView *currentView) {
                    for (UIView *subview in currentView.subviews) {
                        
                        id target = subview;
                        
                        if ([target respondsToSelector:@selector(onEvent)]) {
                            ((void (*)(id, SEL))objc_msgSend)(target, @selector(onEvent));
                        }
                        
                        if (subview.subviews.count > 0) {
                            searchViews(subview);
                        }
                    }
                };
                
                searchViews(window);
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
