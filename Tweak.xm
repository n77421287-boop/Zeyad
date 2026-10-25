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

// عند فتح التطبيق بالكامل
%ctor {
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification * _Nonnull note) {
            
            BOOL shouldAutoClick = [[NSUserDefaults standardUserDefaults] boolForKey:PREF_KEY_ACTIVE];
            
            if (shouldAutoClick) {
                // الانتظار لمدة 10 ثوانٍ كاملة حتى يتم تحميل الواجهة بالكامل وتجاوز أي شاشات ترحيبية
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    
                    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
                    if (!keyWindow) {
                        keyWindow = [[UIApplication sharedApplication].windows firstObject];
                    }
                    
                    void (^findAndTrigger)(UIView *) = ^(UIView *view) {
                        if ([view respondsToSelector:@selector(onEvent)]) {
                            startAutoClicking(view);
                        }
                    };
                    
                    for (UIView *subview in keyWindow.subviews) {
                        findAndTrigger(subview);
                    }
                    
                    NSLog(@"[Tweak] مرّت 10 ثوانٍ، وتم استئناف التكرار تلقائياً بنجاح!");
                });
            }
        }];
}
