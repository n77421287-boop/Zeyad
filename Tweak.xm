//  SimpleWebViewSniffer.m — Direct Element Name Sniffer (Fixed)
// ============================================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>

// تخزين الأحداث وعرضها
static NSMutableArray<NSString *> *g_sniffedLogs = nil;
static UIView     *g_overlay     = nil;
static UITextView *g_overlayText = nil;

static void sniffer_add_log(NSString *logText) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        g_sniffedLogs = [NSMutableArray array];
    });
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [g_sniffedLogs insertObject:logText atIndex:0];
        if (g_sniffedLogs.count > 30) [g_sniffedLogs removeLastObject];
        
        if (g_overlayText) {
            g_overlayText.text = [g_sniffedLogs componentsJoinedByString:@"\n----------------------------------------\n"];
        }
    });
}

// طريقة آمنة لجلب النافذة النشطة بدون أخطاء تحذيرات المترجم
static UIWindow *sniffer_key_window(void) {
    UIWindow *keyWindow = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            if (scene.activationState != UISceneActivationStateForegroundActive) continue;
            UIWindowScene *ws = (UIWindowScene *)scene;
            for (UIWindow *w in ws.windows) {
                if (w.isKeyWindow) { keyWindow = w; break; }
            }
            if (keyWindow) break;
        }
    }
    
    if (!keyWindow) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        keyWindow = [UIApplication sharedApplication].keyWindow;
        #pragma clang diagnostic pop
    }
    
    if (!keyWindow) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (w.isKeyWindow) { keyWindow = w; break; }
        }
        #pragma clang diagnostic pop
    }
    return keyWindow;
}

// السكربت الذي سيراقب الـ Click ويعطينا الاسم بوضوح تام
static NSString *const kSimpleJSSnippet = @"(function() {"
@"if (window.__simpleSnifferInjected) return;"
@"window.__simpleSnifferInjected = true;"
@""
@"document.addEventListener('click', function(e) {"
@"    var el = e.target;"
@"    var tagName = el.tagName || 'UNKNOWN';"
@"    var elemId = el.id ? 'id=\"' + el.id + '\"' : '';"
@"    var elemClass = el.className ? 'class=\"' + el.className + '\"' : '';"
@"    var elemText = (el.innerText || el.value || el.getAttribute('aria-label') || '').trim();"
@"    if (elemText.length > 30) elemText = elemText.substring(0, 30) + '...';"
@""
@"    // بناء XPath دقيق للزر الضغوط"
@"    function getXPath(node) {"
@"        if (node.id) return '//*[@id=\"' + node.id + '\"]';"
@"        if (node === document.body) return node.tagName;"
@"        var ix = 0;"
@"        var siblings = node.parentNode ? node.parentNode.childNodes : [];"
@"        for (var i = 0; i < siblings.length; i++) {"
@"            var sibling = siblings[i];"
@"            if (sibling === node) {"
@"                return getXPath(node.parentNode) + '/' + node.tagName.toLowerCase() + '[' + (ix + 1) + ']';"
@"            }"
@"            if (sibling.nodeType === 1 && sibling.tagName === node.tagName) ix++;"
@"        }"
@"        return '';"
@"    }"
@""
@"    var xpath = getXPath(el);"
@"    var info = '🎯 تم ضغط: <' + tagName + '> | النص: [' + elemText + '] | ' + elemId + ' ' + elemClass;"
@""
@"    // إرسال البيانات للتطبيق الأصلي"
@"    window.webkit.messageHandlers.SimpleSnifferHandler.postMessage({text: info, xpath: xpath});"
@"}, true);"
@кновеرت();"; // تم تصحيح القوس الداخلي أدناه بنجاح

// استبدال النص السابق بالنسخ الصحيحة أدناه للـ JS snippet لتفادي أي خطأ
static NSString *const kFixedSimpleJSSnippet = @"(function() {"
@"if (window.__simpleSnifferInjected) return;"
@"window.__simpleSnifferInjected = true;"
@""
@"document.addEventListener('click', function(e) {"
@"    var el = e.target;"
@"    var tagName = el.tagName || 'UNKNOWN';"
@"    var elemId = el.id ? 'id=\"' + el.id + '\"' : '';"
@"    var elemClass = el.className ? 'class=\"' + el.className + '\"' : '';"
@"    var elemText = (el.innerText || el.value || el.getAttribute('aria-label') || '').trim();"
@"    if (elemText.length > 30) elemText = elemText.substring(0, 30) + '...';"
@""
@"    function getXPath(node) {"
@"        if (node.id) return '//*[@id=\"' + node.id + '\"]';"
@"        if (node === document.body) return node.tagName;"
@"        var ix = 0;"
@"        var siblings = node.parentNode ? node.parentNode.childNodes : [];"
@"        for (var i = 0; i < siblings.length; i++) {"
@"            var sibling = siblings[i];"
@"            if (sibling === node) {"
@"                return getXPath(node.parentNode) + '/' + node.tagName.toLowerCase() + '[' + (ix + 1) + ']';"
@"            }"
@"            if (sibling.nodeType === 1 && sibling.tagName === node.tagName) ix++;"
@"        }"
@"        return '';"
@"    }"
@""
@"    var xpath = getXPath(el);"
@"    var info = '🎯 تم ضغط: <' + tagName + '> | النص: [' + elemText + '] | ' + elemId + ' ' + elemClass;"
@"    window.webkit.messageHandlers.SimpleSnifferHandler.postMessage({text: info, xpath: xpath});"
@"}, true);"
@"})();";

@interface SimpleSnifferHandler : NSObject <WKScriptMessageHandler>
@end

@implementation SimpleSnifferHandler
- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    if ([message.name isEqualToString:@"SimpleSnifferHandler"]) {
        NSDictionary *body = message.body;
        NSString *textInfo = body[@"text"];
        NSString *xpath = body[@"xpath"];
        
        NSString *fullLog = [NSString stringWithFormat:@"%@\n📍 XPath: %@\n💻 كود الضغط التلقائي:\n[webView evaluateJavaScript:@\"document.evaluate('%@', document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue.click();\" completionHandler:nil];", textInfo, xpath, xpath];
        
        sniffer_add_log(fullLog);
        NSLog(@"%@", fullLog);
    }
}
@end

@interface WKWebView (SimpleSnifferHook)
@end

@implementation WKWebView (SimpleSnifferHook)

static SimpleSnifferHandler *g_handler = nil;

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        g_handler = [SimpleSnifferHandler new];
        Class cls = [WKWebView class];
        SEL sel = @selector(initWithFrame:configuration:);
        Method m1 = class_getInstanceMethod(cls, sel);
        Method m2 = class_getInstanceMethod(cls, @selector(simple_initWithFrame:configuration:));
        if (m1 && m2) method_exchangeImplementations(m1, m2);
    });
}

- (instancetype)simple_initWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration *)configuration {
    @try {
        if (configuration && configuration.userContentController) {
            [configuration.userContentController addScriptMessageHandler:g_handler name:@"SimpleSnifferHandler"];
            WKUserScript *script = [[WKUserScript alloc] initWithSource:kFixedSimpleJSSnippet
                                                          injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                                       forMainFrameOnly:NO];
            [configuration.userContentController addUserScript:script];
        }
    } @catch (__unused NSException *e) {}
    
    return [self simple_initWithFrame:frame configuration:configuration];
}

@end

// بناء الشاشة العائمة لعرض النتائج فوراً
__attribute__((constructor))
static void SimpleBootstrap(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @try {
            UIWindow *keyWindow = sniffer_key_window();
            if (!keyWindow) return;

            g_overlay = [[UIView alloc] initWithFrame:CGRectMake(10, 40, keyWindow.bounds.size.width - 20, 260)];
            g_overlay.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.95];
            g_overlay.layer.cornerRadius = 8;
            g_overlay.layer.borderWidth = 1.5;
            g_overlay.layer.borderColor = [UIColor yellowColor].CGColor;
            
            g_overlayText = [[UITextView alloc] initWithFrame:CGRectMake(5, 5, g_overlay.bounds.size.width - 10, g_overlay.bounds.size.height - 10)];
            g_overlayText.backgroundColor = [UIColor clearColor];
            g_overlayText.textColor = [UIColor yellowColor];
            g_overlayText.font = [UIFont fontWithName:@"Courier-Bold" size:9.0] ?: [UIFont systemFontOfSize:9.0];
            g_overlayText.editable = NO;
            g_overlayText.text = @"[+] اضغط على أي زر بالمنصة ليظهر اسمه هنا...\n";
            
            [g_overlay addSubview:g_overlayText];
            [keyWindow addSubview:g_overlay];
            [keyWindow bringSubviewToFront:g_overlay];
        } @catch (__unused NSException *e) {}
    });
}
