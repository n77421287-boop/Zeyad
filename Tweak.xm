#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>

// دالة موحدة لتشغيل التكرار تلقائياً
static void startAutoTimer(id target) {
    if (!target) return;
    
    static NSMapTable *activeTimers = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        activeTimers = [NSMapTable weakToStrongObjectsMapTable];
    });

    // التأكد من عدم تكرار المؤقت لنفس الكائن
    if (![activeTimers objectForKey:target]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer * _Nonnull t) {
                
                // تنفيذ onEvent تلقائياً كل ثانيتين
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

// 1. مراقبة ظهور العناصر على الشاشة للتشغيل التلقائي فوراً بدون ضغط
%hook UIView

- (void)didMoveToWindow {
    %orig;
    if (self && self.window) {
        UIResponder *responder = self;
        while (responder) {
            if ([responder respondsToSelector:@selector(onEvent)]) {
                startAutoTimer(responder);
                break;
            }
            responder = responder.nextResponder;
        }
    }
}

%end

// 2. كودك الأصلي تماماً لضمان الدعم الكامل
%hook UIControl

- (void)sendAction:(SEL)action to:(id)target forEvent:(UIEvent *)event {
    %orig;

    NSString *actionString = NSStringFromSelector(action);
    if ([actionString isEqualToString:@"onEvent"]) {
        startAutoTimer(target);
    }
}

%end
