#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <Security/Security.h>
#import <AdSupport/AdSupport.h>
#import <AppTrackingTransparency/AppTrackingTransparency.h>

// --- الثوابت وإعدادات الحسابات الثلاثة مرقمة ومرتبة بدقة ---
static NSString * const kKeychainAccount = @"com.tempnum.virtualnumber.deviceUUID";
static NSString * const kKeychainGroup   = @"3J96GNXKKU.*";

static NSString * const kAccount1_UUID   = @"5A82BF9F-3EA4-4CB5-AD3A-593553C1E15C"; // الحساب الأول (1)
static NSString * const kAccount2_UUID   = @"2BEE80E4-E20A-432B-879A-A98E2B8BC10A"; // الحساب الثاني (2)
static NSString * const kAccount3_UUID   = @"7F4D0094-0107-44B6-9D4A-63FBCE2A5956"; // الحساب الثالث (3)

static BOOL isSwitchAlertShown = NO;

// --- واجهة النافذة العائمة الحديثة (FLEX Style Overlay - شفافة ولا تعيق اللمس) ---
@interface FLEXNetworkViewerWindow : NSObject
+ (instancetype)sharedInstance;
- (void)appendLog:(NSString * _Nullable)logText;
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
        _floatingWindow.userInteractionEnabled = NO; // السماح بالضغط على التطبيق خلفها
        _floatingWindow.hidden = NO;
        
        UIViewController *vc = [[UIViewController alloc] init];
        _floatingWindow.rootViewController = vc;
        
        _logTextView = [[UITextView alloc] initWithFrame:CGRectMake(15, 45, vc.view.bounds.size.width - 30, 180)];
        _logTextView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.85];
        _logTextView.textColor = [UIColor greenColor];
        _logTextView.font = [UIFont fontWithName:@"Courier" size:10.0];
        _logTextView.editable = NO;
        _logTextView.userInteractionEnabled = NO;
        _logTextView.layer.cornerRadius = 6;
        _logTextView.layer.borderWidth = 1.0;
        _logTextView.layer.borderColor = [[UIColor greenColor] CGColor];
        
        [vc.view addSubview:_logTextView];
    });
}

- (void)appendLog:(NSString * _Nullable)logText {
    if (!logText) return;
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

// --- دوال الهويات العشوائية وبيئة التشغيل ---
static NSString *randomUUID() { return [[NSUUID UUID] UUIDString]; }
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
    return [NSString stringWithFormat:@"172.59.%d.%d", arc4random_uniform(250) + 1, arc4random_uniform(250) + 1];
}
static NSString *randomOSVersion() {
    NSArray *versions = @[@"16.5", @"17.0", @"17.4", @"17.5.1", @"18.0"];
    return versions[arc4random_uniform((uint32_t)[versions count])];
}
static NSString *randomLocaleIdentifier() { return @"en_US"; }
static NSString *generateTimestamp() {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"];
    return [formatter stringFromDate:[NSDate date]];
}

// --- مسار حالة التبديل والتسلسل ---
NSString *getStatePlistPath(void) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    return [[paths firstObject] stringByAppendingPathComponent:@"AccountSwitchState.plist"];
}

// --- إدارة الـ Keychain ---
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
        NSDictionary *spec = @{ (__bridge id)kSecClass: secClass, (__bridge id)kSecAttrAccessGroup: kKeychainGroup };
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

void clearAllAppDataCompletely(void) {
    NSString *bundleDomain = [[NSBundle mainBundle] bundleIdentifier];
    if (bundleDomain) {
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:bundleDomain];
    }
    [[NSURLCache sharedURLCache] removeAllCachedResponses];
    
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
                if (![libItemPath isEqualToString:statePath]) {
                    [fm removeItemAtPath:libItemPath error:&error];
                }
            }
        } else {
            [fm removeItemAtPath:fullPath error:&error];
        }
    }
}

NSString *getNextAccountUUID(void) {
    NSString *path = getStatePlistPath();
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] initWithContentsOfFile:path] ?: [NSMutableDictionary dictionary];
    NSInteger currentStep = dict[@"SequenceStep"] ? [dict[@"SequenceStep"] integerValue] : 1;
    
    NSString *nextUUID = nil;
    NSInteger nextStep = 1;
    if (currentStep == 1) { nextUUID = kAccount2_UUID; nextStep = 2; }
    else if (currentStep == 2) { nextUUID = kAccount3_UUID; nextStep = 3; }
    else { nextUUID = kAccount1_UUID; nextStep = 1; }
    
    dict[@"SequenceStep"] = @(nextStep);
    dict[@"WaitingForPointsChange"] = @YES;
    [dict writeToFile:path atomically:YES];
    return nextUUID;
}

BOOL shouldProcessPoints(NSInteger currentPoints) {
    NSString *path = getStatePlistPath();
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
    if (dict && dict[@"WaitingForPointsChange"] != nil) {
        if ([dict[@"WaitingForPointsChange"] boolValue]) {
            if (currentPoints == 395) return NO;
            NSMutableDictionary *mutableDict = [dict mutableCopy];
            mutableDict[@"WaitingForPointsChange"] = @NO;
            [mutableDict writeToFile:path atomically:YES];
        }
    }
    return YES;
}

void performAccountSwitchAndAlert(void) {
    if (isSwitchAlertShown) return;
    isSwitchAlertShown = YES;
    
    NSString *nextUUID = getNextAccountUUID();
    clearAllAppDataCompletely();
    clearEntireKeychain();
    saveUUIDToKeychain(nextUUID);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        exit(0);
    });
}

void checkAndEnforceValidAccount(void) {
    NSString *currentUUID = getAppCurrentUUIDFromKeychain();
    if (![currentUUID isEqualToString:kAccount1_UUID] && ![currentUUID isEqualToString:kAccount2_UUID] && ![currentUUID isEqualToString:kAccount3_UUID]) {
        clearEntireKeychain();
        saveUUIDToKeychain(kAccount1_UUID);
        NSDictionary *dict = @{ @"SequenceStep": @(1), @"WaitingForPointsChange": @NO };
        [dict writeToFile:getStatePlistPath() atomically:YES];
    }
}

// --- معالجة الاستجابة ومراقبة النقاط بأسلوب FLEXNetworkObserver الحديث ---
static void handleResponsePayload(NSURLRequest *request, NSData *data) {
    checkAndEnforceValidAccount();
    NSString *url = request.URL.absoluteString;
    if (!url) return;
    
    [[FLEXNetworkViewerWindow sharedInstance] appendLog:[NSString stringWithFormat:@"[%@] %@", request.HTTPMethod ?: @"GET", url]];

    if (![url containsString:@"tn.maildisposable.com/api/v1/users/additional/points/data"]) {
        return;
    }
    if (data) {
        NSError *jsonError = nil;
        NSDictionary *jsonDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (!jsonError && [jsonDict isKindOfClass:[NSDictionary class]]) {
            NSDictionary *pointsData = jsonDict[@"data"][@"pointsData"];
            NSNumber *pointsVal = pointsData[@"points"];
            if (pointsVal) {
                NSInteger currentPoints = [pointsVal integerValue];
                [[FLEXNetworkViewerWindow sharedInstance] appendLog:[NSString stringWithFormat:@"⭐ النقاط الحالية: %ld", (long)currentPoints]];
                if (shouldProcessPoints(currentPoints) && currentPoints >= 395) {
                    performAccountSwitchAndAlert();
                }
            }
        }
    }
}

// --- حقن الترويسات في الطلب الأصلي (In-Place) ---
static NSURLRequest *injectFLEXObserverHeaders(NSURLRequest *request) {
    if (![request isKindOfClass:[NSURLRequest class]]) return request;
    
    NSMutableURLRequest *mutableReq = [request mutableCopy];
    
    [mutableReq setValue:randomSpectrumIP() forHTTPHeaderField:@"X-Forwarded-For"];
    [mutableReq setValue:randomSpectrumDNS() forHTTPHeaderField:@"X-DNS-Server"];
    [mutableReq setValue:randomIMEI() forHTTPHeaderField:@"X-Device-IMEI"];
    [mutableReq setValue:randomUUID() forHTTPHeaderField:@"X-Advertising-ID"];
    [mutableReq setValue:generateTimestamp() forHTTPHeaderField:@"X-Request-Timestamp"];
    [mutableReq setValue:@"Charter Communications" forHTTPHeaderField:@"X-ISP"];
    [mutableReq setValue:randomOSVersion() forHTTPHeaderField:@"X-OS-Version"];
    
    return mutableReq;
}

// --- التخطي والهويات الأساسية ---
%hook NSUserDefaults
- (BOOL)boolForKey:(NSString *)defaultName {
    if ([defaultName isEqualToString:@"onboarding_completed"] ||
        [defaultName rangeOfString:@"onboard" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [defaultName rangeOfString:@"term" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        return YES;
    }
    return %orig;
}
- (id)objectForKey:(NSString *)defaultName {
    if ([defaultName isEqualToString:@"onboarding_completed"]) return @YES;
    return %orig;
}
- (NSInteger)integerForKey:(NSString *)defaultName {
    if ([defaultName isEqualToString:@"onboarding_completed"]) return 1;
    return %orig;
}
%end

%hook UIDevice
- (NSUUID *)identifierForVendor { return [[NSUUID alloc] initWithUUIDString:randomUUID()]; }
- (NSString *)systemVersion { return randomOSVersion(); }
- (NSString *)model { return @"iPhone"; }
- (NSString *)uniqueIdentifier { return randomIMEI(); }
%end

%hook NSLocale
+ (NSLocale *)currentLocale { return [[NSLocale alloc] initWithLocaleIdentifier:randomLocaleIdentifier()]; }
%end

%hook ATTrackingManager
+ (NSUInteger)trackingAuthorizationStatus { return 3; }
%end

%hook ASIdentifierManager
- (NSUUID *)advertisingIdentifier { return [[NSUUID alloc] initWithUUIDString:randomUUID()]; }
- (BOOL)isAdvertisingTrackingEnabled { return YES; }
%end

// --- معمارية مراقبة جلسات الشبكة الحديثة (FLEXNetworkObserver Engine) ---
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    return %orig(injectFLEXObserverHeaders(request));
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData * _Nullable, NSURLResponse * _Nullable, NSError * _Nullable))completionHandler {
    NSURLRequest *modifiedReq = injectFLEXObserverHeaders(request);
    
    void (^wrappedHandler)(NSData * _Nullable, NSURLResponse * _Nullable, NSError * _Nullable) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        handleResponsePayload(request, data);
        if (completionHandler) {
            completionHandler(data, response, error);
        }
    };
    
    return %orig(modifiedReq, wrappedHandler);
}

%end

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [FLEXNetworkViewerWindow sharedInstance];
        checkAndEnforceValidAccount();
    });
}
