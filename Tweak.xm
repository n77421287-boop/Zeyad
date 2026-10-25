#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>

#define PREF_KEY_ACTIVE @"AutoClickerIsActive"
#define PREF_KEY_CLASS @"AutoClickerTargetClass"

// دالة لتشغيل التكرار
static void startAutoClicking(id target) {
    static NSMapTable *activeTimers = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        activeTimers = [NSMapTable weakToStrongObjectsMapTable];
    });

    if (target && ! [activeTimers objectForKey:target]) {
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
        
        // 1. حفظ حالة التفعيل
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:PREF_KEY_ACTIVE];
        
        // 2. حفظ اسم كلاس الـ Target تماماً (سواء كان UIViewController أو كلاس مخصص)
        if (target) {
            NSString *targetClassName = NSStringFromClass([target class]);
            [[NSUserDefaults standardUserDefaults] setObject:targetClassName forKey:PREF_KEY_CLASS];
        }
        [[NSUserDefaults standardUserDefaults] synchronize];

        // 3. بدء التكرار الحالي
        if (target) {
            startAutoClicking(target);
        }
    }
}

%end

// مراقبة ظهور الشاشات والصفحات في التطبيق لاستئناف العمل فور ظهورها
%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    
    // التحقق مما إذا كان التكرار مفعلاً مسبقاً
    BOOL shouldAutoClick = [[NSUserDefaults standardUserDefaults] boolForKey:PREF_KEY_ACTIVE];
    if (shouldAutoClick) {
        NSString *savedClass = [[NSUserDefaults standardUserDefaults] stringForKey:PREF_KEY_CLASS];
        if (savedClass) {
            // هل الصفحة الحالية التي ظهرت الآن هي نفس الصفحة القديمة المسؤولة عن onEvent؟
            if ([self isKindOfClass:NSClassFromString(savedClass)]) {
                if ([self respondsToSelector:@selector(onEvent)]) {
                    // تشغيل التكرار عليها فوراً تلقائياً!
                    startAutoClicking(self);
                }
            }
        }
    }
}

%end
