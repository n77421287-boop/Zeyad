#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>

// متغير عام لتخزين أول زر تم الضغط عليه أثناء فتح التطبيق الحالي
static __weak id lockedTarget = nil;
static NSTimer *globalTimer = nil;

// دالة لبدء التكرار الدائم كل نصف ثانية
static void startPermanentAutoClicking(id target) {
    if (!target) return;
    
    if (globalTimer && [globalTimer isValid]) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        globalTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer * _Nonnull t) {
            if (lockedTarget && [lockedTarget respondsToSelector:@selector(onEvent)]) {
                // تنفيذ الأكشن على أول زر تم قفله كل نصف ثانية
                ((void (*)(id, SEL))objc_msgSend)(lockedTarget, @selector(onEvent));
            } else {
                [t invalidate];
                globalTimer = nil;
            }
        }];
    });
}

%hook UIControl

- (void)sendAction:(SEL)action to:(id)target forEvent:(UIEvent *)event {
    %orig;

    NSString *actionString = NSStringFromSelector(action);
    if ([actionString isEqualToString:@"onEvent"]) {
        
        // قفل أول زر يتم الضغط عليه في الجلسة الحالية فقط (بدون أي حفظ دائم)
        if (!lockedTarget && target) {
            lockedTarget = target;
        }

        // تشغيل التكرار
        if (lockedTarget) {
            startPermanentAutoClicking(lockedTarget);
        }
    }
}

%end
