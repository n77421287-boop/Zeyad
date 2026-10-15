#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <WebKit/WebKit.h>
#import <Security/Security.h>
#import <AdSupport/AdSupport.h>
#import <AppTrackingTransparency/AppTrackingTransparency.h>
#import <netdb.h>
#import <arpa/inet.h>

// --- الثوابت وإعدادات الحسابات الثلاثة مرقمة ومرتبة بدقة ---
static NSString * const kKeychainAccount = @"com.tempnum.virtualnumber.deviceUUID";
static NSString * const kKeychainGroup   = @"3J96GNXKKU.*";

static NSString * const kAccount1_UUID   = @"5A82BF9F-3EA4-4CB5-AD3A-593553C1E15C"; // الحساب الأول (1)
static NSString * const kAccount2_UUID   = @"2BEE80E4-E20A-432B-879A-A98E2B8BC10A"; // الحساب الثاني (2)
static NSString * const kAccount3_UUID   = @"7F4D0094-0107-44B6-9D4A-63FBCE2A5956"; // الحساب الثالث (3)

static BOOL isSwitchAlertShown = NO;

// --- واجهة النافذة العائمة الخاصة بعرض سجلات الشبكة (على طريقة FLEX) ---
@interface FLEXNetworkViewerWindow : NSObject
+ (instancetype)sharedInstance;
- (void)appendLog:(NSString *)logText;
@end

@implementation FLEXNetworkViewerWindow {
    UIWindow *_floatingWindow;
    UITextView *_logTextView;
}

+ (instancetype)sharedInstance {
    static FLEXNetworkViewerWindow *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[FLEXNetworkViewerWindow alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (_floatingWindow) return;
        
        UIWindowScene *scene = nil;
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]]) {
                scene = (UIWindowScene *)s;
                break;
            }
        }
        
        if (scene) {
            _floatingWindow = [[UIWindow alloc] initWithWindowScene:scene];
        } else {
            _floatingWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        }
        
        _floatingWindow.windowLevel = UIWindowLevelAlert + 9999;
        _floatingWindow.backgroundColor = [UIColor clearColor];
        _floatingWindow.hidden = NO;
        
        UIViewController *vc = [[UIViewController alloc] init];
        _floatingWindow.rootViewController = vc;
        
        _logTextView = [[UITextView alloc] initWithFrame:CGRectMake(15, 45, vc.view.bounds.size.width - 30, 180)];
        _logTextView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.85];
        _logTextView.textColor = [UIColor greenColor];
        _logTextView.font = [UIFont fontWithName:@"Courier" size:10.0];
        _logTextView.editable = NO;
        _logTextView.layer.cornerRadius = 6;
        _logTextView.layer.borderWidth = 1.0;
        _logTextView.layer.borderColor = [[UIColor greenColor] CGColor];
        
        [vc.view addSubview:_logTextView];
    });
}

- (void)appendLog:(NSString *)logText {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!_logTextView) [self setupUI];
        NSString *current = _logTextView.text ?: @"";
        NSString *updated = [NSString stringWithFormat:@"%@\n%@", current, logText];
        if (updated.length > 6000) {
            updated = [updated substringFromIndex:updated.length - 6000];
        }
        _logTextView.text = updated;
        if (updated.length > 0) {
            [_logTextView scrollRangeToVisible:NSMakeRange(_logTextView.text.length - 1, 1)];
        }
    });
}

@end

// --- دوال مساعدة لإنشاء هويات عشوائية وتزوير البيئة ---
static NSString *randomUUID() {
    return [[NSUUID UUID] UUIDString];
}

static NSString *randomIMEI() {
    int r1 = 10 + arc4random_uniform(89);
    long long r2 = 10000000000LL + (long long)(arc4random_uniform(900000000));
    return [NSString stringWithFormat:@"%d%lld", r1, r2];
}

static NSString *randomSpectrumDNS() {
    NSArray *dnsList = @[@"71.252.0.12", @"71.243.0.12", @"209.18.47.61", @"209.18.47.62", @"68.237.161.12"];
    return dnsList[arc4random_uniform((uint32_t)[dnsList count])];
}

static NSString *randomSpectrumIP() {
    NSArray *subnets = @[@"172.59"];
    NSString *subnet = subnets[arc4random_uniform((uint32_t)[subnets count])];
    return [NSString stringWithFormat:@"%@.%d.%d", subnet, arc4random_uniform(250) + 1, arc4random_uniform(250) + 1];
}

static NSString *randomOSVersion() {
    NSArray *versions = @[@"16.1", @"16.5", @"17.0", @"17.2", @"17.4", @"17.5.1", @"18.0"];
    return versions[arc4random_uniform((uint32_t)[versions count])];
}

static NSString *randomDeviceModel() {
    NSArray *models = @[@"iPhone14,2", @"iPhone14,3", @"iPhone15,2", @"iPhone15,3", @"iPhone16,1", @"iPhone16,2"];
    return models[arc4random_uniform((uint32_t)[models count])];
}

static NSString *randomLocaleIdentifier() {
    NSArray *locales = @[@"en_US", @"en_GB", @"en_CA", @"es_US", @"fr_FR"];
    return locales[arc4random_uniform((uint32_t)[locales count])];
}

static NSString *generateTimestamp() {
    NSDate *now = [NSDate date];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"];
    return [formatter stringFromDate:now];
}

// --- مسار حالة التبديل والتسلسل ---
NSString *getStatePlistPath(void) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    NSString *libraryDirectory = [paths firstObject];
    return [libraryDirectory stringByAppendingPathComponent:@"AccountSwitchState.plist"];
}

// --- إدارة الـ Keychain المدمجة ---
NSString *getAppCurrentUUIDFromKeychain(void) {
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrAccount: kKeychainAccount,
        (__bridge id)kSecAttrAccessGroup: kKeychainGroup,
        (__bridge id)kSecReturnData: (__bridge id)kCFBooleanTrue,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne
    };
    CFTypeRef result = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &result) == noErr) {
        NSData *data = (__bridge_transfer NSData *)result;
        return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    return nil;
}

void clearEntireKeychain(void) {
    NSArray *secClasses = @[
        (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecClassInternetPassword,
        (__bridge id)kSecClassCertificate,
        (__bridge id)kSecClassKey,
        (__bridge id)kSecClassIdentity
    ];
    
    for (id secClass in secClasses) {
        NSDictionary *spec = @{
            (__bridge id)kSecClass: secClass,
            (__bridge id)kSecAttrAccessGroup: kKeychainGroup
        };
        SecItemDelete((__bridge CFDictionaryRef)spec);
    }
}

void saveUUIDToKeychain(NSString *uuidString) {
    NSData *data = [uuidString dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *addQuery = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrAccount: kKeychainAccount,
        (__bridge id)kSecAttrAccessGroup: kKeychainGroup,
        (__bridge id)kSecValueData: data
    };
    SecItemAdd((__bridge CFDictionaryRef)addQuery, NULL);
}

// --- مسح بيانات التطبيق كلياً عند الوصول للهدف فقط (مع استثناء ملف الحالة) ---
void clearAllAppDataCompletely(void) {
    NSString *bundleDomain = [[NSBundle mainBundle] bundleIdentifier];
    if (bundleDomain) {
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:bundleDomain];
    }
    
    [[NSURLCache sharedURLCache] removeAllCachedResponses];
    [[NSURLCache sharedURLCache] setDiskCapacity:0];
    [[NSURLCache sharedURLCache] setMemoryCapacity:0];

    NSString *homeDir = NSHomeDirectory();
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;
    
    NSString *libraryDir = [homeDir stringByAppendingPathComponent:@"Library"];
    NSString *statePath = getStatePlistPath();
    
    NSArray *homeContents = [fm contentsOfDirectoryAtPath:homeDir error:&error];
    for (NSString *item in homeContents) {
        NSString *fullPath = [homeDir stringByAppendingPathComponent:item];
        if ([item isEqualToString:@"Library"]) {
            NSArray *libraryContents = [fm contentsOfDirectoryAtPath:libraryDir error:&error];
            for (NSString *libItem in libraryContents) {
                NSString *libItemPath = [libraryDir stringByAppendingPathComponent:libItem];
                if ([libItemPath isEqualToString:statePath]) {
                    continue; 
                }
                [fm removeItemAtPath:libItemPath error:&error];
            }
        } else {
            [fm removeItemAtPath:fullPath error:&error];
        }
    }
    
    NSString *groupDirBase = [[[homeDir stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"Group Containers"];
    if ([fm fileExistsAtPath:groupDirBase]) {
        NSArray *groupFolders = [fm contentsOfDirectoryAtPath:groupDirBase error:nil];
        for (NSString *groupFolder in groupFolders) {
            NSString *groupPath = [groupDirBase stringByAppendingPathComponent:groupFolder];
            [fm removeItemAtPath:groupPath error:&error];
        }
    }
}

// --- المنطق التسلسلي الصارم والمضمون 100% (1 -> 2 -> 3 -> 1) ---
NSString *getNextAccountUUID(void) {
    NSString *path = getStatePlistPath();
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] initWithContentsOfFile:path];
    
    if (!dict) {
        dict = [NSMutableDictionary dictionary];
    }
    
    NSInteger currentStep = 1;
    if (dict[@"SequenceStep"] != nil) {
        currentStep = [dict[@"SequenceStep"] integerValue];
    }
    
    NSString *nextUUID = nil;
    NSInteger nextStep = 1;
    
    if (currentStep == 1) {
        nextUUID = kAccount2_UUID;
        nextStep = 2;
    } else if (currentStep == 2) {
        nextUUID = kAccount3_UUID;
        nextStep = 3;
    } else {
        nextUUID = kAccount1_UUID;
        nextStep = 1;
    }
    
    dict[@"SequenceStep"] = @(nextStep);
    dict[@"WaitingForPointsChange"] = @YES;
    [dict writeToFile:path atomically:YES];
    
    return nextUUID;
}

BOOL shouldProcessPoints(NSInteger currentPoints) {
    NSString *path = getStatePlistPath();
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
    
    if (dict && dict[@"WaitingForPointsChange"] != nil) {
        BOOL waiting = [dict[@"WaitingForPointsChange"] boolValue];
        if (waiting) {
            if (currentPoints == 395) {
                return NO;
            } else {
                NSMutableDictionary *mutableDict = [dict mutableCopy];
                mutableDict[@"WaitingForPointsChange"] = @NO;
                [mutableDict writeToFile:path atomically:YES];
            }
        }
    }
    return YES;
}

// --- تنفيذ عملية التبديل والحذف (تتم حصراً عند الوصول لـ 395 نقطة) ---
void performAccountSwitchAndAlert(void) {
    if (isSwitchAlertShown) return;
    isSwitchAlertShown = YES;
    
    NSString *nextUUID = getNextAccountUUID();
    
    clearAllAppDataCompletely();
    clearEntireKeychain();
    saveUUIDToKeychain(nextUUID);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = nil;
        if (@available(iOS 13.0, *)) {
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
                    UIWindowScene *windowScene = (UIWindowScene *)scene;
                    for (UIWindow *w in windowScene.windows) {
                        if (w.isKeyWindow) {
                            keyWindow = w;
                            break;
                        }
                    }
                }
            }
        }
        
        UIViewController *rootVC = keyWindow.rootViewController;
        while (rootVC.presentedViewController) {
            rootVC = rootVC.presentedViewController;
        }
        
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🔄 تم التبديل التسلسلي بنجاح"
                                                                   message:@"تم الوصول إلى 395 نقطة، والانتقال للحساب التالي بالترتيب الدقيق.\n\nسيتم إغلاق التطبيق الآن..."
                                                            preferredStyle:UIAlertControllerStyleAlert];
        
        if (rootVC) {
            [rootVC presentViewController:alert animated:YES completion:^{
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    exit(0);
                });
            }];
        } else {
            exit(0);
        }
    });
}

// --- التحقق من وجود حساب صالح في الـ Keychain بدون مسح البيانات عند الفتح العادي ---
void checkAndEnforceValidAccount(void) {
    NSString *currentUUID = getAppCurrentUUIDFromKeychain();
    if (![currentUUID isEqualToString:kAccount1_UUID] && 
        ![currentUUID isEqualToString:kAccount2_UUID] && 
        ![currentUUID isEqualToString:kAccount3_UUID]) {
        
        clearEntireKeychain();
        saveUUIDToKeychain(kAccount1_UUID);
        
        NSString *path = getStatePlistPath();
        NSDictionary *dict = @{ 
            @"SequenceStep": @(1), 
            @"WaitingForPointsChange": @NO 
        };
        [dict writeToFile:path atomically:YES];
    }
}

// --- معالجة البيانات وإرسالها للشاشة العائمة وعلى طريقة FLEX ---
void logGodModeEvent(NSString *engine, NSString *method, NSString *url, NSInteger statusCode, NSData *data, NSError *error) {
    checkAndEnforceValidAccount();

    if (url) {
        NSString *logLine = [NSString stringWithFormat:@"[%@] %ld %@ -> %@", method, (long)statusCode, url, error ? @"[Error]" : @"[OK]"];
        [[FLEXNetworkViewerWindow sharedInstance] appendLog:logLine];
    }

    if (!url || ![url containsString:@"tn.maildisposable.com/api/v1/users/additional/points/data"]) {
        return;
    }

    if (data) {
        NSError *jsonError = nil;
        NSDictionary *jsonDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (!jsonError && [jsonDict isKindOfClass:[NSDictionary class]]) {
            NSDictionary *dataObj = jsonDict[@"data"];
            NSDictionary *pointsData = dataObj[@"pointsData"];
            NSNumber *pointsVal = pointsData[@"points"];
            
            if (pointsVal) {
                NSInteger currentPoints = [pointsVal integerValue];
                if (!shouldProcessPoints(currentPoints)) return;
                if (currentPoints >= 395) {
                    performAccountSwitchAndAlert();
                }
            }
        }
    }
}

// --- بروتوكول شبكة اعتراض الطلبات (على طريقة FLEX الأصلية عبر NSURLProtocol) ---
@interface GodModeNetworkProtocol : NSURLProtocol <NSURLSessionDataDelegate>
@property (nonatomic, strong) NSURLSessionDataTask *task;
@end

@implementation GodModeNetworkProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSString *scheme = request.URL.scheme;
    if ([scheme caseInsensitiveCompare:@"http"] == NSOrderedSame || [scheme caseInsensitiveCompare:@"https"] == NSOrderedSame) {
        if ([NSURLProtocol propertyForKey:@"GodModeHandled" inRequest:request] == nil) {
            return YES;
        }
    }
    return NO;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    NSMutableURLRequest *mutableReq = [self.request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:@"GodModeHandled" inRequest:mutableReq];
    
    NSString *dynIP = randomSpectrumIP();
    NSString *dynDNS = randomSpectrumDNS();
    NSString *dynIMEI = randomIMEI();
    NSString *dynIDFA = randomUUID();
    NSString *dynIDFV = randomUUID();
    NSString *dynOS = randomOSVersion();
    NSString *dynModel = randomDeviceModel();
    NSString *timestamp = generateTimestamp();
    
    [mutableReq setValue:dynIP forHTTPHeaderField:@"X-Forwarded-For"];
    [mutableReq setValue:dynIP forHTTPHeaderField:@"Client-IP"];
    [mutableReq setValue:dynDNS forHTTPHeaderField:@"X-DNS-Server"];
    [mutableReq setValue:dynIMEI forHTTPHeaderField:@"X-Device-IMEI"];
    [mutableReq setValue:dynIDFA forHTTPHeaderField:@"X-Advertising-ID"];
    [mutableReq setValue:dynIDFV forHTTPHeaderField:@"X-Vendor-ID"];
    [mutableReq setValue:timestamp forHTTPHeaderField:@"X-Request-Timestamp"];
    [mutableReq setValue:@"Charter Communications" forHTTPHeaderField:@"X-ISP"];
    [mutableReq setValue:dynOS forHTTPHeaderField:@"X-OS-Version"];
    [mutableReq setValue:dynModel forHTTPHeaderField:@"X-Device-Model"];
    [mutableReq setValue:[NSString stringWithFormat:@"Mozilla/5.0 (iPhone; CPU iPhone OS %@ like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148", dynOS] forHTTPHeaderField:@"User-Agent"];

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:nil];
    
    self.task = [session dataTaskWithRequest:mutableReq];
    [self.task resume];
}

- (void)stopLoading {
    [self.task cancel];
    self.task = nil;
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageAllowed];
    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    [self.client URLProtocol:self didLoadData:data];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)task.response;
    NSData *taskData = nil; 
    logGodModeEvent(@"FLEXProtocol", task.originalRequest.HTTPMethod, task.originalRequest.URL.absoluteString, httpResp.statusCode, taskData, error);

    if (error) {
        [self.client URLProtocol:self didFailWithError:error];
    } else {
        [self.client URLProtocolDidFinishLoading:self];
    }
}

@end

// --- تخطي شاشات الترحيب والشروط تلقائياً عبر NSUserDefaults ---
%hook NSUserDefaults

- (BOOL)boolForKey:(NSString *)defaultName {
    if ([defaultName isEqualToString:@"onboarding_completed"] ||
        [defaultName rangeOfString:@"onboard" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [defaultName rangeOfString:@"term" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [defaultName rangeOfString:@"agree" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        return YES;
    }
    return %orig;
}

- (id)objectForKey:(NSString *)defaultName {
    if ([defaultName isEqualToString:@"onboarding_completed"] ||
        [defaultName rangeOfString:@"onboard" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        return @YES;
    }
    return %orig;
}

- (NSInteger)integerForKey:(NSString *)defaultName {
    if ([defaultName isEqualToString:@"onboarding_completed"]) {
        return 1;
    }
    return %orig;
}

%end

// --- الخطافات لتزوير الهويات والبيانات الأساسية ---
%hook UIDevice
- (NSUUID *)identifierForVendor {
    return [[NSUUID alloc] initWithUUIDString:randomUUID()];
}
- (NSString *)systemVersion {
    return randomOSVersion();
}
- (NSString *)model {
    return @"iPhone";
}
- (NSString *)localizedModel {
    return @"iPhone";
}
- (NSString *)uniqueIdentifier {
    return randomIMEI();
}
%end

%hook NSLocale
+ (NSLocale *)currentLocale {
    return [[NSLocale alloc] initWithLocaleIdentifier:randomLocaleIdentifier()];
}
%end

%hook ATTrackingManager
+ (NSUInteger)trackingAuthorizationStatus {
    return 3;
}
%end

%hook ASIdentifierManager
- (NSUUID *)advertisingIdentifier {
    return [[NSUUID alloc] initWithUUIDString:randomUUID()];
}
- (BOOL)isAdvertisingTrackingEnabled {
    return YES;
}
%end

// --- حقن بروتوكول FLEX الشامل في جلسات النظام الافتراضية ---
%hook NSURLSessionConfiguration
+ (NSURLSessionConfiguration *)defaultSessionConfiguration {
    NSURLSessionConfiguration *config = %orig;
    NSMutableArray *protocols = [config.protocolClasses mutableCopy];
    if (!protocols) protocols = [NSMutableArray array];
    if (![protocols containsObject:[GodModeNetworkProtocol class]]) {
        [protocols insertObject:[GodModeNetworkProtocol class] atIndex:0];
        config.protocolClasses = protocols;
    }
    return config;
}

+ (NSURLSessionConfiguration *)ephemeralSessionConfiguration {
    NSURLSessionConfiguration *config = %orig;
    NSMutableArray *protocols = [config.protocolClasses mutableCopy];
    if (!protocols) protocols = [NSMutableArray array];
    if (![protocols containsObject:[GodModeNetworkProtocol class]]) {
        [protocols insertObject:[GodModeNetworkProtocol class] atIndex:0];
        config.protocolClasses = protocols;
    }
    return config;
}
%end

// --- تهيئة التويك وعرض المربع العائم عند التشغيل ---
%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [NSURLProtocol registerClass:[GodModeNetworkProtocol class]];
        [FLEXNetworkViewerWindow sharedInstance];
        checkAndEnforceValidAccount();
    });
}
