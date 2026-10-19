// ============================================================================
//  NetworkSniffer.m — Passive Overlay Sniffer (no re-send, full coverage)
// ============================================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <zlib.h>

// ============================================================================
// SECTION 1 — Logging
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

// ============================================================================
// SECTION 2 — Request model
// ============================================================================

@interface SnifferRequest : NSObject
@property (nonatomic, copy)   NSString *url;
@property (nonatomic, copy)   NSString *method;
@property (nonatomic, strong) NSDictionary *requestHeaders;
@property (nonatomic, strong) NSData *requestBody;
@property (nonatomic, strong) NSDictionary *responseHeaders;
@property (nonatomic, assign) NSInteger statusCode;
@property (nonatomic, strong) NSData *responseBody;
@property (nonatomic, strong) NSError *error;
@property (nonatomic, strong) NSDate *timestamp;
@end

@implementation SnifferRequest
@end

@interface SnifferTaskBuffer : NSObject
@property (nonatomic, strong) NSMutableData *data;
@property (nonatomic, strong) NSURLResponse *response;
@end

@implementation SnifferTaskBuffer
- (instancetype)init {
    self = [super init];
    if (self) _data = [NSMutableData data];
    return self;
}
@end

// ============================================================================
// SECTION 3 — Thread-safe store
// ============================================================================

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
    if (!req) return;
    sniffer_store_init();
    dispatch_async(g_storeQueue, ^{
        @try {
            [g_requests insertObject:req atIndex:0];
            if (g_requests.count > 500) [g_requests removeLastObject];
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter]
                    postNotificationName:@"SnifferNewRequest" object:nil];
            });
        } @catch (__unused NSException *e) { }
    });
}

static void sniffer_record_update(SnifferRequest *rec,
                                  NSURLResponse *resp,
                                  NSData *data,
                                  NSError *err) {
    if (!rec) return;
    sniffer_store_init();
    dispatch_async(g_storeQueue, ^{
        @try {
            if (resp) {
                rec.responseHeaders = [(NSHTTPURLResponse *)resp allHeaderFields];
                rec.statusCode = [(NSHTTPURLResponse *)resp statusCode];
            }
            if (data) rec.responseBody = data;
            if (err) rec.error = err;
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter]
                    postNotificationName:@"SnifferNewRequest" object:nil];
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
// SECTION 4 — Gzip/Deflate (display only)
// ============================================================================

static NSData *sniffer_inflate(NSData *data, BOOL raw) {
    if (data.length == 0) return data;
    @try {
        z_stream stream = {0};
        stream.next_in = (Bytef *)data.bytes;
        stream.avail_in = (uInt)data.length;
        int windowBits = raw ? -MAX_WBITS : (15 + 32);
        if (inflateInit2(&stream, windowBits) != Z_OK) return data;

        NSMutableData *out = [NSMutableData dataWithCapacity:data.length * 4];
        unsigned char buffer[32768];
        int status;
        do {
            stream.next_out = buffer;
            stream.avail_out = sizeof(buffer);
            status = inflate(&stream, Z_NO_FLUSH);
            if (status != Z_OK && status != Z_STREAM_END && status != Z_BUF_ERROR) {
                inflateEnd(&stream);
                return data;
            }
            NSUInteger produced = sizeof(buffer) - stream.avail_out;
            if (produced) [out appendBytes:buffer length:produced];
        } while (status != Z_STREAM_END && stream.avail_in > 0);

        inflateEnd(&stream);
        return out.length ? out : data;
    } @catch (__unused NSException *e) { return data; }
}

static NSData *sniffer_decompress_for_display(NSData *data, NSDictionary *headers) {
    @try {
        NSString *enc = headers[@"Content-Encoding"] ?: headers[@"content-encoding"];
        if (!enc) return data;
        enc = enc.lowercaseString;
        if ([enc containsString:@"gzip"])    return sniffer_inflate(data, NO);
        if ([enc containsString:@"deflate"]) return sniffer_inflate(data, YES);
    } @catch (__unused NSException *e) { }
    return data;
}

// ============================================================================
// SECTION 5 — Delegate Proxy
// ============================================================================

static const void *kSnifferRecordKey = &kSnifferRecordKey;
static const void *kSnifferBufferKey = &kSnifferBufferKey;

@interface SnifferDelegateProxy : NSObject <
    NSURLSessionDelegate,
    NSURLSessionTaskDelegate,
    NSURLSessionDataDelegate,
    NSURLSessionDownloadDelegate,
    NSURLSessionStreamDelegate
>
@property (nonatomic, weak) id originalDelegate;
@end

@implementation SnifferDelegateProxy

- (BOOL)respondsToSelector:(SEL)aSelector {
    if ([super respondsToSelector:aSelector]) return YES;
    return [self.originalDelegate respondsToSelector:aSelector];
}

- (id)forwardingTargetForSelector:(SEL)aSelector {
    if ([self.originalDelegate respondsToSelector:aSelector]) {
        return self.originalDelegate;
    }
    return [super forwardingTargetForSelector:aSelector];
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data {
    @try {
        SnifferTaskBuffer *buf = objc_getAssociatedObject(dataTask, kSnifferBufferKey);
        if (!buf) {
            buf = [SnifferTaskBuffer new];
            objc_setAssociatedObject(dataTask, kSnifferBufferKey, buf,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        [buf.data appendData:data];
    } @catch (__unused NSException *e) { }

    if ([self.originalDelegate respondsToSelector:_cmd]) {
        [self.originalDelegate URLSession:session dataTask:dataTask didReceiveData:data];
    }
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    @try {
        SnifferTaskBuffer *buf = objc_getAssociatedObject(dataTask, kSnifferBufferKey);
        if (!buf) {
            buf = [SnifferTaskBuffer new];
            objc_setAssociatedObject(dataTask, kSnifferBufferKey, buf,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        buf.response = response;
    } @catch (__unused NSException *e) { }

    if ([self.originalDelegate respondsToSelector:_cmd]) {
        [self.originalDelegate URLSession:session
                                 dataTask:dataTask
                       didReceiveResponse:response
                        completionHandler:completionHandler];
    } else {
        completionHandler(NSURLSessionResponseAllow);
    }
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    @try {
        SnifferRequest *rec = objc_getAssociatedObject(task, kSnifferRecordKey);
        SnifferTaskBuffer *buf = objc_getAssociatedObject(task, kSnifferBufferKey);

        if (rec) {
            NSURLResponse *resp = buf.response ?: task.response;
            NSData *data = buf.data.length ? [buf.data copy] : nil;
            NSDictionary *hdrs = [(NSHTTPURLResponse *)resp allHeaderFields];
            NSData *display = sniffer_decompress_for_display(data, hdrs);
            sniffer_record_update(rec, resp, display, error);
        }
    } @catch (__unused NSException *e) { }

    if ([self.originalDelegate respondsToSelector:_cmd]) {
        [self.originalDelegate URLSession:session task:task didCompleteWithError:error];
    }
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location {
    @try {
        SnifferRequest *rec = objc_getAssociatedObject(downloadTask, kSnifferRecordKey);
        if (rec && location) {
            NSData *data = [NSData dataWithContentsOfURL:location];
            sniffer_record_update(rec, downloadTask.response, data, nil);
        }
    } @catch (__unused NSException *e) { }

    if ([self.originalDelegate respondsToSelector:_cmd]) {
        [self.originalDelegate URLSession:session
                             downloadTask:downloadTask
                didFinishDownloadingToURL:location];
    }
}

@end

// ============================================================================
// SECTION 6 — NSURLSession Swizzling
// ============================================================================

@interface NSURLSession (SnifferSwizzle)

- (NSURLSessionDataTask *)sniffer_dataTaskWithRequest:(NSURLRequest *)request
                                     completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler;
- (NSURLSessionDataTask *)sniffer_dataTaskWithURL:(NSURL *)url
                                completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler;
- (NSURLSessionUploadTask *)sniffer_uploadTaskWithRequest:(NSURLRequest *)request
                                                 fromData:(NSData *)bodyData
                                        completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler;
- (NSURLSessionDownloadTask *)sniffer_downloadTaskWithRequest:(NSURLRequest *)request
                                            completionHandler:(void (^)(NSURL *, NSURLResponse *, NSError *))completionHandler;

- (NSURLSessionDataTask *)sniffer_dataTaskWithRequest:(NSURLRequest *)request;
- (NSURLSessionDataTask *)sniffer_dataTaskWithURL:(NSURL *)url;
- (NSURLSessionUploadTask *)sniffer_uploadTaskWithRequest:(NSURLRequest *)request
                                                 fromData:(NSData *)bodyData;
- (NSURLSessionDownloadTask *)sniffer_downloadTaskWithRequest:(NSURLRequest *)request;

@end

@implementation NSURLSession (SnifferSwizzle)

static SnifferRequest *sniffer_make_record(NSURLRequest *req, NSData *body) {
    SnifferRequest *rec = [SnifferRequest new];
    rec.url = req.URL.absoluteString ?: @"";
    rec.method = req.HTTPMethod ?: @"GET";
    rec.requestHeaders = req.allHTTPHeaderFields;
    rec.requestBody = body ?: req.HTTPBody;
    rec.timestamp = [NSDate date];
    sniffer_store_add(rec);
    return rec;
}

- (NSURLSessionDataTask *)sniffer_dataTaskWithRequest:(NSURLRequest *)request
                                     completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    SnifferRequest *rec = sniffer_make_record(request, nil);

    void (^wrapped)(NSData *, NSURLResponse *, NSError *) =
        ^(NSData *data, NSURLResponse *resp, NSError *err) {
        @try {
            NSDictionary *hdrs = [(NSHTTPURLResponse *)resp allHeaderFields];
            NSData *display = sniffer_decompress_for_display(data, hdrs);
            sniffer_record_update(rec, resp, display, err);
        } @catch (__unused NSException *e) { }
        if (completionHandler) completionHandler(data, resp, err);
    };

    return [self sniffer_dataTaskWithRequest:request completionHandler:wrapped];
}

- (NSURLSessionDataTask *)sniffer_dataTaskWithURL:(NSURL *)url
                                completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    NSURLRequest *req = [NSURLRequest requestWithURL:url];
    SnifferRequest *rec = sniffer_make_record(req, nil);

    void (^wrapped)(NSData *, NSURLResponse *, NSError *) =
        ^(NSData *data, NSURLResponse *resp, NSError *err) {
        @try {
            NSDictionary *hdrs = [(NSHTTPURLResponse *)resp allHeaderFields];
            NSData *display = sniffer_decompress_for_display(data, hdrs);
            sniffer_record_update(rec, resp, display, err);
        } @catch (__unused NSException *e) { }
        if (completionHandler) completionHandler(data, resp, err);
    };

    return [self sniffer_dataTaskWithURL:url completionHandler:wrapped];
}

- (NSURLSessionUploadTask *)sniffer_uploadTaskWithRequest:(NSURLRequest *)request
                                                 fromData:(NSData *)bodyData
                                        completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    SnifferRequest *rec = sniffer_make_record(request, bodyData);

    void (^wrapped)(NSData *, NSURLResponse *, NSError *) =
        ^(NSData *data, NSURLResponse *resp, NSError *err) {
        @try {
            NSDictionary *hdrs = [(NSHTTPURLResponse *)resp allHeaderFields];
            NSData *display = sniffer_decompress_for_display(data, hdrs);
            sniffer_record_update(rec, resp, display, err);
        } @catch (__unused NSException *e) { }
        if (completionHandler) completionHandler(data, resp, err);
    };

    return [self sniffer_uploadTaskWithRequest:request
                                      fromData:bodyData
                             completionHandler:wrapped];
}

- (NSURLSessionDownloadTask *)sniffer_downloadTaskWithRequest:(NSURLRequest *)request
                                            completionHandler:(void (^)(NSURL *, NSURLResponse *, NSError *))completionHandler {
    SnifferRequest *rec = sniffer_make_record(request, nil);

    void (^wrapped)(NSURL *, NSURLResponse *, NSError *) =
        ^(NSURL *location, NSURLResponse *resp, NSError *err) {
        @try {
            NSData *data = location ? [NSData dataWithContentsOfURL:location] : nil;
            sniffer_record_update(rec, resp, data, err);
        } @catch (__unused NSException *e) { }
        if (completionHandler) completionHandler(location, resp, err);
    };

    return [self sniffer_downloadTaskWithRequest:request completionHandler:wrapped];
}

- (NSURLSessionDataTask *)sniffer_dataTaskWithRequest:(NSURLRequest *)request {
    NSURLSessionDataTask *task = [self sniffer_dataTaskWithRequest:request];
    @try {
        SnifferRequest *rec = sniffer_make_record(request, nil);
        objc_setAssociatedObject(task, kSnifferRecordKey, rec,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } @catch (__unused NSException *e) { }
    return task;
}

- (NSURLSessionDataTask *)sniffer_dataTaskWithURL:(NSURL *)url {
    NSURLRequest *req = [NSURLRequest requestWithURL:url];
    NSURLSessionDataTask *task = [self sniffer_dataTaskWithURL:url];
    @try {
        SnifferRequest *rec = sniffer_make_record(req, nil);
        objc_setAssociatedObject(task, kSnifferRecordKey, rec,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } @catch (__unused NSException *e) { }
    return task;
}

- (NSURLSessionUploadTask *)sniffer_uploadTaskWithRequest:(NSURLRequest *)request
                                                 fromData:(NSData *)bodyData {
    NSURLSessionUploadTask *task = [self sniffer_uploadTaskWithRequest:request
                                                              fromData:bodyData];
    @try {
        SnifferRequest *rec = sniffer_make_record(request, bodyData);
        objc_setAssociatedObject(task, kSnifferRecordKey, rec,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } @catch (__unused NSException *e) { }
    return task;
}

- (NSURLSessionDownloadTask *)sniffer_downloadTaskWithRequest:(NSURLRequest *)request {
    NSURLSessionDownloadTask *task = [self sniffer_downloadTaskWithRequest:request];
    @try {
        SnifferRequest *rec = sniffer_make_record(request, nil);
        objc_setAssociatedObject(task, kSnifferRecordKey, rec,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } @catch (__unused NSException *e) { }
    return task;
}

@end

// ============================================================================
// SECTION 7 — Session creation swizzle
// ============================================================================

@interface NSURLSession (SnifferSessionCreation)

- (instancetype)sniffer_initWithConfiguration:(NSURLSessionConfiguration *)configuration
                                     delegate:(id)delegate
                                delegateQueue:(NSOperationQueue *)queue;

+ (NSURLSession *)sniffer_sessionWithConfiguration:(NSURLSessionConfiguration *)configuration
                                          delegate:(id)delegate
                                     delegateQueue:(NSOperationQueue *)queue;

@end

@implementation NSURLSession (SnifferSessionCreation)

- (instancetype)sniffer_initWithConfiguration:(NSURLSessionConfiguration *)configuration
                                     delegate:(id)delegate
                                delegateQueue:(NSOperationQueue *)queue {
    id effectiveDelegate = delegate;

    if (delegate && ![delegate isKindOfClass:[SnifferDelegateProxy class]]) {
        SnifferDelegateProxy *proxy = [SnifferDelegateProxy new];
        proxy.originalDelegate = delegate;
        effectiveDelegate = proxy;
        snf_log(@"delegate wrapped: %@", NSStringFromClass([delegate class]));
    }

    return [self sniffer_initWithConfiguration:configuration
                                      delegate:effectiveDelegate
                                 delegateQueue:queue];
}

+ (NSURLSession *)sniffer_sessionWithConfiguration:(NSURLSessionConfiguration *)configuration
                                          delegate:(id)delegate
                                     delegateQueue:(NSOperationQueue *)queue {
    id effectiveDelegate = delegate;
    if (delegate && ![delegate isKindOfClass:[SnifferDelegateProxy class]]) {
        SnifferDelegateProxy *proxy = [SnifferDelegateProxy new];
        proxy.originalDelegate = delegate;
        effectiveDelegate = proxy;
        snf_log(@"delegate wrapped (class): %@", NSStringFromClass([delegate class]));
    }
    return [self sniffer_sessionWithConfiguration:configuration
                                         delegate:effectiveDelegate
                                    delegateQueue:queue];
}

@end

// ============================================================================
// SECTION 8 — Installer
// ============================================================================

@interface SnifferSessionHook : NSObject
+ (void)install;
+ (void)swapDelegateOnExistingSession:(NSURLSession *)session;
@end

@implementation SnifferSessionHook

+ (void)install {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class cls = [NSURLSession class];

        [self swap:cls
               sel:@selector(dataTaskWithRequest:completionHandler:)
              with:@selector(sniffer_dataTaskWithRequest:completionHandler:)];
        [self swap:cls
               sel:@selector(dataTaskWithURL:completionHandler:)
              with:@selector(sniffer_dataTaskWithURL:completionHandler:)];
        [self swap:cls
               sel:@selector(uploadTaskWithRequest:fromData:completionHandler:)
              with:@selector(sniffer_uploadTaskWithRequest:fromData:completionHandler:)];
        [self swap:cls
               sel:@selector(downloadTaskWithRequest:completionHandler:)
              with:@selector(sniffer_downloadTaskWithRequest:completionHandler:)];

        [self swap:cls
               sel:@selector(dataTaskWithRequest:)
              with:@selector(sniffer_dataTaskWithRequest:)];
        [self swap:cls
               sel:@selector(dataTaskWithURL:)
              with:@selector(sniffer_dataTaskWithURL:)];
        [self swap:cls
               sel:@selector(uploadTaskWithRequest:fromData:)
              with:@selector(sniffer_uploadTaskWithRequest:fromData:)];
        [self swap:cls
               sel:@selector(downloadTaskWithRequest:)
              with:@selector(sniffer_downloadTaskWithRequest:)];

        [self swap:cls
               sel:@selector(initWithConfiguration:delegate:delegateQueue:)
              with:@selector(sniffer_initWithConfiguration:delegate:delegateQueue:)];

        Method m1 = class_getClassMethod(cls, @selector(sessionWithConfiguration:delegate:delegateQueue:));
        Method m2 = class_getClassMethod(cls, @selector(sniffer_sessionWithConfiguration:delegate:delegateQueue:));
        if (m1 && m2) method_exchangeImplementations(m1, m2);

        snf_log(@"NSURLSession swizzle installed (instance + class init)");
    });
}

+ (void)swapDelegateOnExistingSession:(NSURLSession *)session {
    @try {
        if (!session) return;

        id currentDelegate = session.delegate;
        if (!currentDelegate) return;
        if ([currentDelegate isKindOfClass:[SnifferDelegateProxy class]]) return;

        SnifferDelegateProxy *proxy = [SnifferDelegateProxy new];
        proxy.originalDelegate = currentDelegate;

        @try {
            [session setValue:proxy forKey:@"delegate"];
            snf_log(@"KVC-swapped delegate on existing session: %@",
                    NSStringFromClass([currentDelegate class]));
            return;
        } @catch (__unused NSException *e) { }

        Ivar iv = class_getInstanceVariable([NSURLSession class], "_delegate");
        if (!iv) iv = class_getInstanceVariable([NSURLSession class], "delegate");
        if (iv) {
            object_setIvar(session, iv, proxy);
            snf_log(@"ivar-swapped delegate on existing session: %@",
                    NSStringFromClass([currentDelegate class]));
        } else {
            snf_log(@"could not swap delegate — no _delegate ivar");
        }
    } @catch (NSException *e) {
        snf_log(@"swapDelegateOnExistingSession failed: %@", e.reason);
    }
}

+ (void)swap:(Class)cls sel:(SEL)a with:(SEL)b {
    Method ma = class_getInstanceMethod(cls, a);
    Method mb = class_getInstanceMethod(cls, b);
    if (ma && mb) {
        method_exchangeImplementations(ma, mb);
    } else {
        snf_log(@"swap failed: %@ <-> %@",
                NSStringFromSelector(a), NSStringFromSelector(b));
    }
}

@end

// ============================================================================
// SECTION 9 — Overlay UI
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
    if (!keyWindow) {
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (w.isKeyWindow) { keyWindow = w; break; }
        }
    }
    return keyWindow;
}

static NSString *sniffer_format_request(SnifferRequest *r) {
    NSURL *u = [NSURL URLWithString:r.url];
    NSString *host = u.host ?: @"";
    NSString *path = u.path.length ? u.path : @"/";
    NSString *query = u.query.length ? [NSString stringWithFormat:@"?%@", u.query] : @"";

    NSString *statusStr = r.statusCode ? [NSString stringWithFormat:@"%ld", (long)r.statusCode] : @"...";

    NSMutableString *s = [NSMutableString string];
    [s appendFormat:@"[%@] [%@] %@%@%@\n", r.method ?: @"?", statusStr, host, path, query];

    if (r.responseBody.length) {
        NSString *body = nil;
        @try {
            NSError *err = nil;
            id json = [NSJSONSerialization JSONObjectWithData:r.responseBody options:0 error:&err];
            if (json && !err) {
                NSData *pretty = [NSJSONSerialization dataWithJSONObject:json
                                                                 options:NSJSONWritingPrettyPrinted
                                                                   error:nil];
                if (pretty)
                    body = [[NSString alloc] initWithData:pretty encoding:NSUTF8StringEncoding];
            }
        } @catch (__unused NSException *e) { }

        if (!body)
            body = [[NSString alloc] initWithData:r.responseBody encoding:NSUTF8StringEncoding];

        if (body.length > 220)
            body = [[body substringToIndex:220] stringByAppendingString:@"...(truncated)"];

        if (body) {
            [s appendFormat:@"Data: %@\n", body];
        } else {
            [s appendFormat:@"Data: [Binary %lu bytes]\n", (unsigned long)r.responseBody.length];
        }
    } else if (r.error) {
        [s appendFormat:@"Error: %@\n", r.error.localizedDescription];
    } else {
        [s appendFormat:@"Data: [waiting...]\n"];
    }

    return s;
}

static void sniffer_refresh_overlay(void) {
    if (!g_overlayText) return;
    NSArray<SnifferRequest *> *items = sniffer_store_snapshot();

    NSMutableString *s = [NSMutableString stringWithFormat:
        @"Network Sniffer — %lu request(s)\n============================\n",
        (unsigned long)items.count];

    NSUInteger limit = MIN(items.count, 40);
    for (NSUInteger i = 0; i < limit; i++) {
        [s appendString:sniffer_format_request(items[i])];
        [s appendString:@"----------------------------\n"];
    }

    g_overlayText.text = s;
}

static void sniffer_build_overlay(void) {
    @try {
        if (g_overlay) return;

        UIWindow *keyWindow = sniffer_key_window();
        if (!keyWindow) { snf_log(@"build overlay: no key window"); return; }

        CGRect b = keyWindow.bounds;

        g_overlay = [[UIView alloc] initWithFrame:
            CGRectMake(5, 40, b.size.width - 10, 270)];
        g_overlay.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.99];
        g_overlay.layer.cornerRadius = 10;
        g_overlay.layer.borderWidth = 1.8;
        g_overlay.layer.borderColor = [UIColor greenColor].CGColor;
        g_overlay.userInteractionEnabled = YES;
        g_overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth;

        g_overlayText = [[UITextView alloc] initWithFrame:
            CGRectMake(5, 5,
                       g_overlay.bounds.size.width - 10,
                       g_overlay.bounds.size.height - 10)];
        g_overlayText.backgroundColor = [UIColor clearColor];
        g_overlayText.textColor = [UIColor greenColor];
        g_overlayText.font = [UIFont fontWithName:@"Courier-Bold" size:7.5]
                             ?: [UIFont systemFontOfSize:7.5];
        g_overlayText.editable = NO;
        g_overlayText.text = @"[+] Network Sniffer Online...\n";
        g_overlayText.autoresizingMask =
            UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

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

        snf_log(@"Overlay installed on key window");
        sniffer_refresh_overlay();
    } @catch (NSException *e) {
        snf_log(@"buildOverlay failed: %@", e);
    }
}

// ============================================================================
// SECTION 10 — Install UI with retry
// ============================================================================

static dispatch_source_t g_retryTimer = nil;

static BOOL sniffer_try_install_ui(void) {
    if (g_overlay) return YES;
    @try {
        UIWindow *w = sniffer_key_window();
        if (!w) return NO;
        sniffer_build_overlay();
        return g_overlay != nil;
    } @catch (NSException *e) {
        snf_log(@"tryInstallUI failed: %@", e);
        return NO;
    }
}

static void sniffer_schedule_ui_retry(void) {
    if (g_retryTimer) return;
    g_retryTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                          dispatch_get_main_queue());
    dispatch_source_set_timer(g_retryTimer,
                              dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC),
                              1 * NSEC_PER_SEC,
                              0.1 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(g_retryTimer, ^{
        if (sniffer_try_install_ui()) {
            dispatch_source_cancel(g_retryTimer);
            g_retryTimer = nil;
        }
    });
    dispatch_resume(g_retryTimer);
}

// ============================================================================
// SECTION 11 — Bootstrap (hook immediately, UI delayed)
// ============================================================================

__attribute__((constructor))
static void SnifferBootstrap(void) {
    snf_log(@"dylib loaded");

    // 1) Session hook IMMEDIATELY — before the app creates any session.
    snf_safe(@"Session hook", ^{
        [SnifferSessionHook install];
    });

    // 2) Try to wrap delegate on already-existing shared session.
    snf_safe(@"Existing sessions", ^{
        NSURLSession *shared = [NSURLSession sharedSession];
        if (shared) [SnifferSessionHook swapDelegateOnExistingSession:shared];
    });

    // 3) UI install — deferred, with retry.
    [[NSNotificationCenter defaultCenter]
        addObserverForName:UIApplicationDidBecomeActiveNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
        if (!sniffer_try_install_ui()) sniffer_schedule_ui_retry();
    }];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        snf_safe(@"UI", ^{
            if (!sniffer_try_install_ui()) {
                snf_log(@"UI not ready — scheduling retry");
                sniffer_schedule_ui_retry();
            }
        });
    });

    snf_log(@"bootstrap complete");
}
