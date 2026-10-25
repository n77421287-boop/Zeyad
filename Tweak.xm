#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>

// دالة لتشغيل التكرار لكل زر بشكل مستقل تماماً
static void startAutoClickingForTarget(id target) {
    static NSMapTable *activeTimers = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        activeTimers = [NSMapTable weakToStrongObjectsMapTable];
    });

    if (target && ![activeTimers objectForKey:target]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            // التكرار كل ثانية واحدة (1.0) لكل زر على حدة
            NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer * _Nonnull t) {
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
        
        // تفعيل التكرار لأي زر تضغطه، بحيث يعمل عدة أزرار معاً في نفس الوقت دون أن يلغي أحدها الآخر
        if (target) {
            startAutoClickingForTarget(target);
        }
    }
}

%end
