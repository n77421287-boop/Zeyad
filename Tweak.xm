#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>

%hook UIControl

- (void)sendAction:(SEL)action to:(id)target forEvent:(UIEvent *)event {
    // 1. تنفيذ الضغطة الأصلية التي تفعلها أنت
    %orig;

    // 2. التحقق من أن الأكشن هو onEvent (كما ظهر في الفحص)[span_2](start_span)[span_2](end_span)[span_3](start_span)[span_3](end_span)
    NSString *actionString = NSStringFromSelector(action);
    if ([actionString isEqualToString:@"onEvent"]) {
        
        static NSMapTable *activeTimers = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            activeTimers = [NSMapTable weakToStrongObjectsMapTable];
        });

        // 3. التأكد من عدم تكرار المؤقت لنفس الكائن
        if (target && ![activeTimers objectForKey:target]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer * _Nonnull t) {
                    
                    // 4. هنا يتم عمل الـ (Call) تماماً مثل زر Call في الأداة لتنفيذ onEvent تلقائياً كل ثانيتين[span_4](start_span)[span_4](end_span)
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
}

%end
