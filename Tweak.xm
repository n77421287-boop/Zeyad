#import <UIKit/UIKit.h>
#import <StoreKit/StoreKit.h>
#import <WebKit/WebKit.h>

// دالة جافا سكريبت لإغلاق إعلانات الويب فور توفر زر الإغلاق
static void injectJavaScriptToDismissWebAds(UIView *view) {
    if (!view) return;
    
    if ([view isKindOfClass:[WKWebView class]]) {
        WKWebView *webView = (WKWebView *)view;
        NSString *jsCloseScript = 
        @"(function() {"
        "var selectors = ['button', 'div', 'span', 'a', 'img', 'svg', 'iframe'];"
        "for (var i = 0; i < selectors.length; i++) {"
        "  var elements = document.querySelectorAll(selectors[i]);"
        "  for (var j = 0; j < elements.length; j++) {"
        "    var el = elements[j];"
        "    var text = (el.innerText || el.textContent || '').trim().toLowerCase();"
        "    var aria = (el.getAttribute('aria-label') || '').toLowerCase();"
        "    var cls = (el.className || '').toLowerCase();"
        "    var id = (el.id || '').toLowerCase();"
        "    "
        "    var isXButton = (text === 'x' || text === '✕' || text === '×');"
        "    var isCloseWord = (text === 'close' || text === 'dismiss' || text === 'skip' || text === 'إغلاق' || text === 'تخطي' || text === 'done' || text === 'تم');"
        "    var hasCloseAttr = (aria.includes('close') || aria.includes('skip') || aria.includes('dismiss') || "
        "                        cls.includes('close') || cls.includes('skip') || cls.includes('dismiss') || "
        "                        id.includes('close') || id.includes('skip') || id.includes('dismiss'));"
        "    "
        "    if (isXButton || isCloseWord || hasCloseAttr) {"
        "       el.click();"
        "    }"
        "  } "
        "}"
        "})();";
        
        [webView evaluateJavaScript:jsCloseScript completionHandler:nil];
    }
    
    for (UIView *subview in view.subviews) {
        injectJavaScriptToDismissWebAds(subview);
    }
}

// دالة فحص العناصر وإغلاقها عند ظهور زر الإغلاق
static void safeDismissAllAds(UIView *view) {
    if (!view || ![view isKindOfClass:[UIView class]]) return;
    
    injectJavaScriptToDismissWebAds(view);
    
    NSArray *subviews = [view.subviews copy];
    for (UIView *subview in subviews) {
        if (!subview || subview.hidden || subview.alpha < 0.01) continue;
        
        BOOL isCloseButtonOnly = NO;
        
        if ([subview isKindOfClass:[UIButton class]]) {
            UIButton *button = (UIButton *)subview;
            NSString *title = [[button titleForState:UIControlStateNormal] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSString *accLabel = [button.accessibilityLabel lowercaseString];
            NSString *accId = [button.accessibilityIdentifier lowercaseString];
            
            if ([title isEqualToString:@"X"] || [title isEqualToString:@"✕"] || [title isEqualToString:@"×"] ||
                [title caseInsensitiveCompare:@"close"] == NSOrderedSame ||
                [title caseInsensitiveCompare:@"skip"] == NSOrderedSame ||
                [title caseInsensitiveCompare:@"إغلاق"] == NSOrderedSame ||
                [title caseInsensitiveCompare:@"done"] == NSOrderedSame ||
                [title caseInsensitiveCompare:@"تم"] == NSOrderedSame ||
                [accLabel containsString:@"close"] || [accLabel containsString:@"skip"] ||
                [accId containsString:@"close"] || [accId containsString:@"skip"]) {
                isCloseButtonOnly = YES;
            }
        }
        
        if (isCloseButtonOnly && subview.userInteractionEnabled) {
            if ([subview isKindOfClass:[UIControl class]]) {
                [(UIControl *)subview sendActionsForControlEvents:UIControlEventTouchUpInside];
            }
        }
        
        safeDismissAllAds(subview);
    }
}

// دالة التحقق مما إذا كانت الشاشة الحالية عبارة عن إعلان مكافأة (Rewarded Ad) أو إعلان مرئي
static BOOL isRewardedOrVideoAdViewController(UIViewController *vc) {
    if (!vc) return NO;
    NSString *className = NSStringFromClass([vc class]);
    
    if ([className containsString:@"Fullscreen"] || 
        [className containsString:@"Interstitial"] || 
        [className containsString:@"Rewarded"] || 
        [className containsString:@"AdController"] || 
        [className containsString:@"GAD"] || 
        [className containsString:@"FBAd"] || 
        [className containsString:@"UnityAds"] || 
        [className containsString:@"AppLovin"] ||
        [className containsString:@"IronSource"]) {
        return YES;
    }
    
    return NO;
}

%hook UIViewController

- (void)presentViewController:(UIViewController *)viewControllerToPresent animated:(BOOL)flag completion:(void (^)(void))completion {
    if ([viewControllerToPresent isKindOfClass:[SKStoreProductViewController class]]) {
        return; 
    }
    
    %orig;
    
    if (!viewControllerToPresent) return;

    if (isRewardedOrVideoAdViewController(viewControllerToPresent)) {
        // يبدأ الفحص بعد مرور 60 ثانية كاملة (تبدأ الحلقة من 60 إلى 90 مثلاً، أو كما ترغب)
        // هنا يبدأ من الثانية 60 ويستمر لمدة 30 ثانية أخرى كمثال
        for (int i = 60; i <= 90; i++) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (viewControllerToPresent && viewControllerToPresent.view && !viewControllerToPresent.isBeingDismissed) {
                    safeDismissAllAds(viewControllerToPresent.view);
                }
            });
        }
    }
}

%end
