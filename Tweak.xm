// ============================================================================
//  NetworkSniffer.m — Targeted Notification Monitor
// ============================================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ============================================================================
// SECTION 1 — Logging & Model
// ============================================================================

static void snf_log(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    NSLog(@"[Sniffer] %@", msg);
}

static void snf_safe(NSString *name, dispatch_block_t block) {
    @try { block(); }
    @catch (NSException *e) { snf_log(@"FAIL %@ : %@ - %@", name, e.name, e.reason); }
    @catch (...) { snf_log(@"FAIL %@ : C++ exception", name); }
}

@interface SnifferRequest : NSObject
@property (nonatomic, copy) NSString *url;
@property (nonatomic, strong) NSDate *timestamp;
@end

@implementation SnifferRequest
@end

// ============================================================================
// SECTION 2 — Thread-Safe Store (Targeted URL Only)
// ============================================================================

static NSString * const kTargetURLString = @"https://tn.maildisposable.com/api/v1/users/additional/shake";

static NSMutableArray<SnifferRequest *> *g_requests = nil;
static dispatch_queue_t g_storeQueue = nil;

static void sniffer_store_init(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        g_requests = [NSMutableArray array];
        g_storeQueue = dispatch_queue_create("com.sniffer.store", DISPATCH_QUEUE_SERIAL);
    });
}

static void sniffer_store_add(SnifferRequest *req) {
    if (!req || !req.url) return;
    
    // فلترة الطلب بحيث يراقب الرابط المستهدف فقط لا غير
    if (![req.url containsString:kTargetURLString]) {
        return;
    }

    sniffer_store_init();
    dispatch_async(g_storeQueue, ^{
        @try {
            [g_requests insertObject:req atIndex:0];
            if (g_requests.count > 15) [g_requests removeLastObject];
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:@"SnifferNewRequest" object:nil];
            });
        } @catch (__unused NSException *e) { }
    });
}

static NSArray<SnifferRequest *> *sniffer_store_snapshot(void) {
    sniffer_store_init();
    __block NSArray *copy = @[];
    dispatch_sync(g_storeQueue, ^{
        @try { copy = [g_requests copy]; } @catch (__unused NSException *e) { }
    });
    return copy;
}

// ============================================================================
// SECTION 3 — Swizzling (Passive Observation)
// ============================================================================

@interface NSURLSession (SnifferSwizzle)
- (NSURLSessionDataTask *)sniffer_dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler;
- (NSURLSessionDataTask *)sniffer_dataTaskWithURL:(NSURL *)url completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler;
- (NSURLSessionUploadTask *)sniffer_uploadTaskWithRequest:(NSURLRequest *)request fromData:(NSData *)bodyData completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler;
- (NSURLSessionDownloadTask *)sniffer_downloadTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURL *, NSURLResponse *, NSError *))completionHandler;

- (NSURLSessionDataTask *)sniffer_dataTaskWithRequest:(NSURLRequest *)request;
- (NSURLSessionDataTask *)sniffer_dataTaskWithURL:(NSURL *)url;
- (NSURLSessionUploadTask *)sniffer_uploadTaskWithRequest:(NSURLRequest *)request fromData:(NSData *)bodyData;
- (NSURLSessionDownloadTask *)sniffer_downloadTaskWithRequest:(NSURLRequest *)request;
@end

@implementation NSURLSession (SnifferSwizzle)

static void sniffer_check_and_record(NSURLRequest *req) {
    NSString *urlString = req.URL.absoluteString ?: @"";
    if ([urlString containsString:kTargetURLString]) {
        SnifferRequest *rec = [SnifferRequest new];
        rec.url = urlString;
        rec.timestamp = [NSDate date];
        sniffer_store_add(rec);
    }
}

- (NSURLSessionDataTask *)sniffer_dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    sniffer_check_and_record(request);
    return [self sniffer_dataTaskWithRequest:request completionHandler:completionHandler];
}

- (NSURLSessionDataTask *)sniffer_dataTaskWithURL:(NSURL *)url completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    NSURLRequest *req = [NSURLRequest requestWithURL:url];
    sniffer_check_and_record(req);
    return [self sniffer_dataTaskWithURL:url completionHandler:completionHandler];
}

- (NSURLSessionUploadTask *)sniffer_uploadTaskWithRequest:(NSURLRequest *)request fromData:(NSData *)bodyData completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    sniffer_check_and_record(request);
    return [self sniffer_uploadTaskWithRequest:request fromData:bodyData completionHandler:completionHandler];
}

- (NSURLSessionDownloadTask *)sniffer_downloadTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURL *, NSURLResponse *, NSError *))completionHandler {
    sniffer_check_and_record(request);
    return [self sniffer_downloadTaskWithRequest:request completionHandler:completionHandler];
}

- (NSURLSessionDataTask *)sniffer_dataTaskWithRequest:(NSURLRequest *)request {
    sniffer_check_and_record(request);
    return [self sniffer_dataTaskWithRequest:request];
}

- (NSURLSessionDataTask *)sniffer_dataTaskWithURL:(NSURL *)url {
    NSURLRequest *req = [NSURLRequest requestWithURL:url];
    sniffer_check_and_record(req);
    return [self sniffer_dataTaskWithURL:url];
}

- (NSURLSessionUploadTask *)sniffer_uploadTaskWithRequest:(NSURLRequest *)request fromData:(NSData *)bodyData {
    sniffer_check_and_record(request);
    return [self sniffer_uploadTaskWithRequest:request fromData:bodyData];
}

- (NSURLSessionDownloadTask *)sniffer_downloadTaskWithRequest:(NSURLRequest *)request {
    sniffer_check_and_record(request);
    return [self sniffer_downloadTaskWithRequest:request];
}

@end

// ============================================================================
// SECTION 4 — Swizzle Installer
// ============================================================================

@interface SnifferHook : NSObject
+ (void)install;
@end

@implementation SnifferHook

+ (void)install {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class cls = [NSURLSession class];

        [self swap:cls sel:@selector(dataTaskWithRequest:completionHandler:) with:@selector(sniffer_dataTaskWithRequest:completionHandler:)];
        [self swap:cls sel:@selector(dataTaskWithURL:completionHandler:) with:@selector(sniffer_dataTaskWithURL:completionHandler:)];
        [self swap:cls sel:@selector(uploadTaskWithRequest:fromData:completionHandler:) with:@selector(sniffer_uploadTaskWithRequest:fromData:completionHandler:)];
        [self swap:cls sel:@selector(downloadTaskWithRequest:completionHandler:) with:@selector(sniffer_downloadTaskWithRequest:completionHandler:)];

        [self swap:cls sel:@selector(dataTaskWithRequest:) with:@selector(sniffer_dataTaskWithRequest:)];
        [self swap:cls sel:@selector(dataTaskWithURL:) with:@selector(sniffer_dataTaskWithURL:)];
        [self swap:cls sel:@selector(uploadTaskWithRequest:fromData:) with:@selector(sniffer_uploadTaskWithRequest:fromData:)];
        [self swap:cls sel:@selector(downloadTaskWithRequest:) with:@selector(sniffer_downloadTaskWithRequest:)];

        snf_log(@"Swizzle installed successfully");
    });
}

+ (void)swap:(Class)cls sel:(SEL)a with:(SEL)b {
    Method ma = class_getInstanceMethod(cls, a);
    Method mb = class_getInstanceMethod(cls, b);
    if (ma && mb) method_exchangeImplementations(ma, mb);
}

@end

// ============================================================================
// SECTION 5 — Overlay UI
// ============================================================================

static UIView     *g_overlay       = nil;
static UITextView *g_overlayText   = nil;
static id          g_observerToken = nil;

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
    if (!keyWindow) keyWindow = [UIApplication sharedApplication].keyWindow;
    return keyWindow;
}

static NSString *sniffer_format_request(SnifferRequest *r) {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"HH:mm:ss"];
    NSString *timeString = [formatter stringFromDate:r.timestamp ?: [NSDate date]];
    
    return [NSString stringWithFormat:@"[%@] 🚀 تم إرسال طلب الـ Shake للسيرفر بنجاح\n", timeString];
}

static void sniffer_refresh_overlay(void) {
    if (!g_overlayText) return;
    NSArray<SnifferRequest *> *items = sniffer_store_snapshot();

    NSMutableString *s = [NSMutableString stringWithFormat:@"Shake Status Monitor\n============================\n"];

    NSUInteger limit = MIN(items.count, 8);
    for (NSUInteger i = 0; i < limit; i++) {
        [s appendString:sniffer_format_request(items[i])];
    }

    g_overlayText.text = s;
}

static void sniffer_build_overlay(void) {
    @try {
        if (g_overlay) return;
        UIWindow *keyWindow = sniffer_key_window();
        if (!keyWindow) return;

        CGRect b = keyWindow.bounds;

        g_overlay = [[UIView alloc] initWithFrame:CGRectMake(10, 50, b.size.width - 20, 150)];
        g_overlay.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.90];
        g_overlay.layer.cornerRadius = 10;
        g_overlay.layer.borderWidth = 1.5;
        g_overlay.layer.borderColor = [UIColor greenColor].CGColor;
        g_overlay.userInteractionEnabled = YES;
        g_overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth;

        g_overlayText = [[UITextView alloc] initWithFrame:CGRectMake(5, 5, g_overlay.bounds.size.width - 10, g_overlay.bounds.size.height - 10)];
        g_overlayText.backgroundColor = [UIColor clearColor];
        g_overlayText.textColor = [UIColor greenColor];
        g_overlayText.font = [UIFont fontWithName:@"Courier-Bold" size:11.0] ?: [UIFont systemFontOfSize:11.0];
        g_overlayText.editable = NO;
        g_overlayText.text = @"[+] Monitor Active...\nبانتظار إرسال الطلب...\n";
        g_overlayText.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

        [g_overlay addSubview:g_overlayText];
        [keyWindow addSubview:g_overlay];
        [keyWindow bringSubviewToFront:g_overlay];

        if (!g_observerToken) {
            g_observerToken = [[NSNotificationCenter defaultCenter]
                addObserverForName:@"SnifferNewRequest"
                            object:nil
                             queue:[NSOperationQueue mainQueue]
                        usingBlock:^(NSNotification *note) {
                sniffer_refresh_overlay();
            }];
        }

        sniffer_refresh_overlay();
    } @catch (__unused NSException *e) { }
}

// ============================================================================
// SECTION 6 — Installer with Retry
// ============================================================================

static dispatch_source_t g_retryTimer = nil;

static BOOL sniffer_try_install_ui(void) {
    if (g_overlay) return YES;
    @try {
        UIWindow *w = sniffer_key_window();
        if (!w) return NO;
        sniffer_build_overlay();
        return g_overlay != nil;
    } @catch (__unused NSException *e) {
        return NO;
    }
}

static void sniffer_schedule_ui_retry(void) {
    if (g_retryTimer) return;
    g_retryTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(g_retryTimer, dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), 1 * NSEC_PER_SEC, 0.1 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(g_retryTimer, ^{
        if (sniffer_try_install_ui()) {
            dispatch_source_cancel(g_retryTimer);
            g_retryTimer = nil;
        }
    });
    dispatch_resume(g_retryTimer);
}

// ============================================================================
// SECTION 7 — Bootstrap
// ============================================================================

__attribute__((constructor))
static void SnifferBootstrap(void) {
    snf_safe(@"Session hook", ^{
        [SnifferHook install];
    });

    [[NSNotificationCenter defaultCenter]
        addObserverForName:UIApplicationDidBecomeActiveNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
        if (!sniffer_try_install_ui()) sniffer_schedule_ui_retry();
    }];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        snf_safe(@"UI", ^{
            if (!sniffer_try_install_ui()) {
                sniffer_schedule_ui_retry();
            }
        });
    });
}
