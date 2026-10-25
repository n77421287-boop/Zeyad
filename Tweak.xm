#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>

// دالة تبحث في الشاشة عن أي زر أو عنصر يحتوي على الأكشن وتنفذه تلقائياً
static void triggerEventAutomatically(void) {
    // استخدام مؤقت يعمل في الخلفية كل ثانيتين
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer * _Nonnull t) {
            
            // البحث في كل النوافذ المفتوحة بالصورة النشطة
            for (UIWindow *window in [[UIApplication sharedApplication] windows]) {
                if (!window.isKeyWindow) continue;
                
                // استدراج وعمل مسح لعناصر الشاشة (Views)
                void (^searchViews)(UIView *) = ^(UIView *currentView) {
                    for (UIView *subview in currentView.subviews) {
                        
                        // هنا نتحقق إذا كان العنصر هو الكائن المستهدف أو الزر الذي ترغب بالضغط عليه
                        // يمكنك فحص الـ class أو الـ Target المرتبط به
                        id target = subview; // أو الكائن المسؤول عن الحدث
                        
                        // التحقق مما إذا كان يستجيب لدالة الـ onEvent لتنفيذها مباشرة
                        if ([target respondsToSelector:@selector(onEvent)]) {
                            ((void (*)(id, SEL))objc_msgSend)(target, @selector(onEvent));
                        }
                        
                        // البحث بشكل متعمق داخل العناصر الفرعية
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

// حقن الكود ليعمل فور تشغيل التطبيق أو تحميل الواجهات تلقائياً
%hook UIApplication

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    BOOL orig = %orig;
    
    // تشغيل الآلية التلقائية بعد فتح التطبيق بثوانٍ معدودة
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        triggerEventAutomatically();
    });
    
    return orig;
}

%end
