// ============================================================================
//  UltimateClassIntrospector.m — Deep Runtime Class Introspector
// ============================================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static UIView     *g_ultimateOverlay  = nil;
static UITextView *g_ultimateTextView = nil;

static void introspectClass(Class cls, UIView *view) {
    if (!cls) return;
    
    NSMutableString *report = [NSMutableString string];
    [report appendFormat:@"=== CLASS INTROSPECTION ===\n"];
    [report appendFormat:@"Class: %@\n", NSStringFromClass(cls)];
    [report appendFormat:@"Superclass: %@\n\n", NSStringFromClass([cls superclass])];
    
    // 1. استخراج الخصائص (Properties)
    [report appendString:@"--- Properties ---\n"];
    unsigned int propCount = 0;
    objc_property_t *properties = class_copyPropertyList(cls, &propCount);
    for (unsigned int i = 0; i < propCount; i++) {
        objc_property_t prop = properties[i];
        const char *propName = property_getName(prop);
        const char *propAttr = property_getAttributes(prop);
        [report appendFormat:@"• %s (%s)\n", propName, propAttr];
    }
    free(properties);
    
    // 2. استخراج الدوال (Methods)
    [report appendString:@"\n--- Methods (Actions/Getters) ---\n"];
    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(cls, &methodCount);
    for (unsigned int i = 0; i < methodCount; i++) {
        Method method = methods[i];
        SEL selector = method_getName(method);
        [report appendFormat:@"• %s\n", sel_getName(selector)];
    }
    free(methods);
    
    // 3. النص أو العنوان الظاهر إن وجد
    if ([view respondsToSelector:@selector(text)] && [(id)view text]) {
        [report appendFormat:@"\n[Text Value]: %@\n", [(id)view text]];
    } else if ([view respondsToSelector:@selector(title)] && [(id)view title]) {
        [report appendFormat:@"\n[Title Value]: %@\n", [(id)view title]];
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_ultimateTextView) {
            g_ultimateTextView.text = report;
        }
    });
}

// ============================================================================
// SECTION — Intercepting Touches to Introspect Target Class
// ============================================================================

@interface UIWindow (ClassIntrospector)
@end

@implementation UIWindow (ClassIntrospector)

- (UIView *)intro_hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [self intro_hitTest:point withEvent:event];
    
    if (hitView && ![[hitView description] containsString:@"UITextView"] && hitView != g_ultimateOverlay) {
        if (event.type == UIEventTypeTouches) {
            NSSet *touches = [event touchesForWindow:self];
            for (UITouch *touch in touches) {
                if (touch.phase == UITouchPhaseBegan) {
                    introspectClass([hitView class], hitView);
                }
            }
        }
    }
    
    return hitView;
}

@end

// ============================================================================
// Setup Introspector Overlay Window
// ============================================================================

@interface ClassIntrospectorInstaller : NSObject
@end

@implementation ClassIntrospectorInstaller

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Method m1 = class_getInstanceMethod([UIWindow class], @selector(hitTest:withEvent:));
        Method m2 = class_getInstanceMethod([UIWindow class], @selector(intro_hitTest:withEvent:));
        if (m1 && m2) method_exchangeImplementations(m1, m2);

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self setupOverlay];
        });
    });
}

+ (void)setupOverlay {
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
        
        g_ultimateOverlay = [[UIView alloc] initWithFrame:CGRectMake(10, 40, b.size.width - 20, 280)];
        g_ultimateOverlay.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.97];
        g_ultimateOverlay.layer.cornerRadius = 10;
        g_ultimateOverlay.layer.borderWidth = 1.5;
        g_ultimateOverlay.layer.borderColor = [UIColor yellowColor].CGColor;
        g_ultimateOverlay.userInteractionEnabled = YES;
        g_ultimateOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth;

        g_ultimateTextView = [[UITextView alloc] initWithFrame:CGRectMake(5, 5, g_ultimateOverlay.bounds.size.width - 10, g_ultimateOverlay.bounds.size.height - 10)];
        g_ultimateTextView.backgroundColor = [UIColor clearColor];
        g_ultimateTextView.textColor = [UIColor yellowColor];
        g_ultimateTextView.font = [UIFont fontWithName:@"Courier-Bold" size:8.0] ?: [UIFont systemFontOfSize:8.0];
        g_ultimateTextView.editable = NO;
        g_ultimateTextView.text = @"[+] Deep Class Introspector Ready. Tap any button...\n";
        g_ultimateTextView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

        [g_ultimateOverlay addSubview:g_ultimateTextView];
        [keyWindow addSubview:g_ultimateOverlay];
        [keyWindow bringSubviewToFront:g_ultimateOverlay];
        
    } @catch (__unused NSException *e) {}
}

@end
