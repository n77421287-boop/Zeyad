// ============================================================================
//  SafeLocalInspector.m — Stable Tap Inspector (Zero Crashes)
// ============================================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static UIView     *g_safeOverlay  = nil;
static UITextView *g_safeTextView = nil;

@interface SafeInspectorManager : NSObject
@end

@implementation SafeInspectorManager

+ (void)load {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self setupSafeInspector];
    });
}

+ (void)setupSafeInspector {
    @try {
        UIWindow *keyWindow = nil;
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (w.isKeyWindow) { keyWindow = w; break; }
        }
        #pragma clang diagnostic pop
        if (!keyWindow) return;

        CGRect b = keyWindow.bounds;
        
        // نافذة عرض المعلومات في أعلى الشاشة بلون إطار أخضر آمن
        g_safeOverlay = [[UIView alloc] initWithFrame:CGRectMake(10, 40, b.size.width - 20, 180)];
        g_safeOverlay.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.96];
        g_safeOverlay.layer.cornerRadius = 10;
        g_safeOverlay.layer.borderWidth = 1.5;
        g_safeOverlay.layer.borderColor = [UIColor systemGreenColor].CGColor;
        g_safeOverlay.userInteractionEnabled = YES;
        g_safeOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth;

        g_safeTextView = [[UITextView alloc] initWithFrame:CGRectMake(5, 5, g_safeOverlay.bounds.size.width - 10, g_safeOverlay.bounds.size.height - 10)];
        g_safeTextView.backgroundColor = [UIColor clearColor];
        g_safeTextView.textColor = [UIColor systemGreenColor];
        g_safeTextView.font = [UIFont fontWithName:@"Courier-Bold" size:9.0] ?: [UIFont systemFontOfSize:9.0];
        g_safeTextView.editable = NO;
        g_safeTextView.text = @"[+] Safe Inspector Ready. Tap anywhere on screen...\n";
        g_safeTextView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

        [g_safeOverlay addSubview:g_safeTextView];
        [keyWindow addSubview:g_safeOverlay];
        [keyWindow bringSubviewToFront:g_safeOverlay];

        // إضافة تتبع لمس آمن تماماً لا يعطل التطبيق ولا يسبب كراش
        UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleScreenTap:)];
        tapGesture.cancelsTouchesInView = NO; // لكي يعمل التطبيق بشكل طبيعي تماماً
        [keyWindow addGestureRecognizer:tapGesture];

    } @catch (__unused NSException *e) {}
}

+ (void)handleScreenTap:(UITapGestureRecognizer *)gesture {
    @try {
        CGPoint point = [gesture locationInView:gesture.view];
        UIView *hitView = [gesture.view hitTest:point withEvent:nil];
        
        if (!hitView || hitView == g_safeOverlay || [hitView isDescendantOfView:g_safeOverlay]) return;

        NSString *className = NSStringFromClass([hitView class]);
        NSString *superName = NSStringFromClass([[hitView superclass] class]);
        
        // استخراج النص أو العنوان إن وجد بشكل آمن
        NSString *extraInfo = @"";
        if ([hitView respondsToSelector:@selector(text)] && [(id)hitView text]) {
            extraInfo = [NSString stringWithFormat:@"\n[Text]: '%@'", [(id)hitView text]];
        } else if ([hitView respondsToSelector:@selector(title)] && [(id)hitView title]) {
            extraInfo = [NSString stringWithFormat:@"\n[Title]: '%@'", [(id)hitView title]];
        }

        NSString *report = [NSString stringWithFormat:@"🎯 Tapped View Class: %@\n📌 Superclass: %@%@\n📍 Frame: %@", 
                            className, superName, extraInfo, NSStringFromCGRect(hitView.frame)];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (g_safeTextView) {
                g_safeTextView.text = report;
            }
        });
    } @catch (__unused NSException *e) {}
}

@end
