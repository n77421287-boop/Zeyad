#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>

#define PREF_KEY_ACTIVE @"AutoClickerIsActive"

// دالة لتشغيل التكرار
static void startAutoClicking(id target) {
    static NSMapTable *activeTimers = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        activeTimers = [NSMapTable weakToStrongObjectsMapTable];
    });

    if (target && ![activeTimers objectForKey:target]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer * _Nonnull t) {
                if (target && [target respondsToSelector:@selector(onEvent)]) {
                    ((void (*)(id, SEL))objc_msgSend)(target, @selector(onEvent));
                } else {
                    [t invalidate];
                    [activeTimers removeObjectForKey:target];
                }
            }];
            [activeTimers setObject:timer forKey:target];
        });
    }
}

%hook UIControl

- (void)sendAction:(SEL)action to:(id)target forEvent:(UIEvent *)event {
    %orig;

    NSString *actionString = NSStringFromSelector(action);
    if ([actionString isEqualToString:@"onEvent"]) {
        
        // حفظ حالة أن التكرار مفعل
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:PREF_KEY_ACTIVE];
        [[NSUserDefaults standardUserDefaults] synchronize];

        // بدء التكرار الحالي
        if (target) {
            startAutoClicking(target);
        }
    }
}

%end

// دالة البحث العميق التلقائي (تتغلغل داخل جميع العناصر المتداخلة)
static void deepSearchAndTrigger(UIView *view) {
    if (!view) return;
    
    // التحقق مما إذا كان الكائن يستجيب للأكشن المطلوب
    if ([view respondsToSelector:@selector(onEvent)]) {
        startAutoClicking(view);
        // يمكنك إزالة الـ return لو أردت تفعيل أكثر من زر يمتلك نفس الأكشن
        return; 
    }
    
    // البحث بشكل متكرر في جميع العناصر الفرعية مهما كانت عميقة
    for (UIView *subview in view.subviews) {
        deepSearchAndTrigger(subview);
    }
}

// عند فتح التطبيق بالكامل
%ctor {
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification * _Nonnull note) {
            
            BOOL shouldAutoClick = [[NSUserDefaults standardUserDefaults] boolForKey:PREF_KEY_ACTIVE];
            
            if (shouldAutoClick) {
                // الانتظار لمدة 10 ثوانٍ كاملة حتى يتم تحميل الواجهة بالكامل
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    
                    UIWindow *targetWindow = nil;
                    for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
                        if (scene.activationState == UISceneActivationStateForegroundActive) {
                            for (UIWindow *window in scene.windows) {
                                if (window.isKeyWindow) {
                                    targetWindow = window;
                                    break;
                                }
                            }
                        }
                    }
                    
                    if (!targetWindow) {
                        targetWindow = [[[UIApplication sharedApplication] windows] firstObject];
                    }
                    
                    if (targetWindow) {
                        // بدء البحث العميق من النافذة الرئيسية
                        deepSearchAndTrigger(targetWindow);
                    }
                    
                    NSLog(@"[Tweak] انتهى البحث العميق بعد 10 ثوانٍ، وتم الاستئناف بنجاح!");
                });
            }
        }];
}
