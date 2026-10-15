#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AdSupport/AdSupport.h>
#import <AppTrackingTransparency/AppTrackingTransparency.h>
#import <objc/runtime.h>
#import <netdb.h>
#import <arpa/inet.h>

@interface ActivatorAdService : NSObject
- (void)loadAd;
- (BOOL)isReady;
- (BOOL)isAdReady;
- (BOOL)canShowAd;
- (BOOL)hasAdLoaded;
- (void)showRewardAd;
- (void)presentAdFromViewController:(UIViewController *)viewController;
@end

// 1. تنظيف الـ Keychain بالكامل مع الحفاظ حصرياً على مفتاح المصادقة الأساسي (tokenKey) لضمان عدم خروجك من الحساب
static void clearKeychainExceptToken() {
    NSArray *secClasses = @[
        (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecClassInternetPassword,
        (__bridge id)kSecClassCertificate,
        (__bridge id)kSecClassKey,
        (__bridge id)kSecClassIdentity
    ];
    
    for (id secClass in secClasses) {
        NSDictionary *spec = @{(__bridge id)kSecClass: secClass};
        CFArrayRef result = NULL;
        if (SecItemCopyMatching((__bridge CFDictionaryRef)spec, (CFTypeRef *)&result) == errSecSuccess) {
            NSArray *items = (__bridge NSArray *)result;
            for (NSDictionary *item in items) {
                NSString *account = item[(__bridge id)kSecAttrAccount];
                
                if (![account isEqualToString:@"tokenKey"]) {
                    NSMutableDictionary *delQuery = [NSMutableDictionary dictionaryWithDictionary:item];
                    delQuery[(__bridge id)kSecClass] = secClass;
                    SecItemDelete((__bridge CFDictionaryRef)delQuery);
                }
            }
            if (result) {
                CFRelease(result);
            }
        }
    }
}

// مولدات الهوية المتغيرة لحظياً
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
    NSArray *subnets = @[@"24.24", @"24.160", @"65.24", @"66.192", @"67.240", @"68.172", @"71.64", @"75.128", @"97.100", @"173.16"];
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

// 2. إعادة تفعيل التدمير الجذري للكاش وملفات التطبيق والـ App Groups مع الحفاظ على ملف AppLockState.plist
static __attribute__((constructor)) void totalAnonymityAndDeepWipeOnEveryLaunch() {
    @autoreleasepool {
        clearKeychainExceptToken();

        NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleId) {
            [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:bundleId];
        }

        [[NSURLCache sharedURLCache] removeAllCachedResponses];
        [[NSURLCache sharedURLCache] setDiskCapacity:0];
        [[NSURLCache sharedURLCache] setMemoryCapacity:0];

        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *homeDir = NSHomeDirectory();
        NSError *error = nil;

        // مسار مجلد Library للتأكد من التعامل معه بدقة
        NSString *libraryDir = [homeDir stringByAppendingPathComponent:@"Library"];

        NSArray *homeContents = [fm contentsOfDirectoryAtPath:homeDir error:&error];
        for (NSString *item in homeContents) {
            NSString *fullPath = [homeDir stringByAppendingPathComponent:item];
            
            // إذا كان العنصر هو مجلد Library، نقوم بتنظيف محتوياته مع الاستثناء
            if ([item isEqualToString:@"Library"]) {
                NSArray *libraryContents = [fm contentsOfDirectoryAtPath:libraryDir error:&error];
                for (NSString *libItem in libraryContents) {
                    // استثناء ملف AppLockState.plist من الحذف
                    if ([libItem isEqualToString:@"AppLockState.plist"]) {
                        continue;
                    }
                    NSString *libItemPath = [libraryDir stringByAppendingPathComponent:libItem];
                    [fm removeItemAtPath:libItemPath error:&error];
                }
            } else {
                // حذف باقي محتويات المجلد الرئيسية بشكل طبيعي
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
}

// تزوير الهويات ومعرّفات الأجهزة
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
    return 2;
}
%end

%hook ASIdentifierManager
- (NSUUID *)advertisingIdentifier {
    return [[NSUUID alloc] initWithUUIDString:randomUUID()];
}
- (BOOL)isAdvertisingTrackingEnabled {
    return NO;
}
%end

// محرك تغيير وتزوير كل طلب شبكي طائراً
%hook NSMutableURLRequest

- (void)setURL:(NSURL *)url {
    NSString *dynamicIP = randomSpectrumIP();
    NSString *urlString = [url absoluteString];
    
    if ([urlString containsString:@"ip="]) {
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"ip=([0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+)" options:0 error:nil];
        urlString = [regex stringByReplacingMatchesInString:urlString options:0 range:NSMakeRange(0, [urlString length]) withTemplate:[NSString stringWithFormat:@"ip=%@", dynamicIP]];
    }
    
    url = [NSURL URLWithString:urlString] ?: url;
    %orig(url);
}

- (void)setValue:(NSString * _Nullable)value forHTTPHeaderField:(NSString *)field {
    NSString *dynIP = randomSpectrumIP();
    NSString *dynDNS = randomSpectrumDNS();
    NSString *dynIMEI = randomIMEI();
    NSString *dynIDFA = randomUUID();
    NSString *dynIDFV = randomUUID();
    NSString *dynOS = randomOSVersion();
    NSString *dynModel = randomDeviceModel();
    
    if ([field isEqualToString:@"X-Forwarded-For"] || [field isEqualToString:@"Client-IP"] || [field isEqualToString:@"True-Client-IP"] || [field isEqualToString:@"X-Client-IP"] || [field isEqualToString:@"Remote-IP"]) {
        value = dynIP;
    } else if ([field isEqualToString:@"X-Custom-DNS"] || [field isEqualToString:@"X-DNS-Server"]) {
        value = dynDNS;
    } else if ([field isEqualToString:@"X-Device-IMEI"] || [field isEqualToString:@"X-IMEI"] || [field isEqualToString:@"Device-Id"] || [field isEqualToString:@"IMEI"]) {
        value = dynIMEI;
    } else if ([field isEqualToString:@"X-Advertising-ID"] || [field isEqualToString:@"IDFA"] || [field isEqualToString:@"Advertising-Identifier"]) {
        value = dynIDFA;
    } else if ([field isEqualToString:@"X-Vendor-ID"] || [field isEqualToString:@"IDFV"]) {
        value = dynIDFV;
    } else if ([field isEqualToString:@"User-Agent"]) {
        value = [NSString stringWithFormat:@"Mozilla/5.0 (iPhone; CPU iPhone OS %@ like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Safari/604.1 AppModel/%@", dynOS, dynModel];
    } else if ([field isEqualToString:@"X-OS-Version"] || [field isEqualToString:@"OS-Version"]) {
        value = dynOS;
    } else if ([field isEqualToString:@"X-Device-Model"]) {
        value = dynModel;
    } else if ([field isEqualToString:@"X-ISP"] || [field isEqualToString:@"X-Carrier"]) {
        value = @"Charter Communications";
    }

    %orig(value, field);
}
%end

// التحكم المطلق بجلسات الشبكة
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData * _Nullable, NSURLResponse * _Nullable, NSError * _Nullable))completionHandler {
    NSMutableURLRequest *mutableReq = [request mutableCopy];
    
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
    
    return %orig(mutableReq, completionHandler);
}

- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url completionHandler:(void (^)(NSData * _Nullable, NSURLResponse * _Nullable, NSError * _Nullable))completionHandler {
    NSString *dynIP = randomSpectrumIP();
    NSString *urlString = [url absoluteString];
    
    if ([urlString containsString:@"ip="]) {
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"ip=([0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+)" options:0 error:nil];
        urlString = [regex stringByReplacingMatchesInString:urlString options:0 range:NSMakeRange(0, [urlString length]) withTemplate:[NSString stringWithFormat:@"ip=%@", dynIP]];
        url = [NSURL URLWithString:urlString] ?: url;
    }
    
    return %orig(url, completionHandler);
}

%end

// --- التحصين المطلق لإعلانات مضمونة بدون حظر ---
%hook ActivatorAdService

- (BOOL)isReady { return YES; }
- (BOOL)isAdReady { return YES; }
- (BOOL)canShowAd { return YES; }
- (BOOL)hasAdLoaded { return YES; }

- (void)loadAd {
    %orig;
    id targetSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if ([targetSelf respondsToSelector:@selector(loadAd)]) {
            [targetSelf loadAd];
        }
    });
}

- (void)showRewardAd {
    @try {
        %orig;
        id targetSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if ([targetSelf respondsToSelector:@selector(loadAd)]) {
                [targetSelf loadAd];
            }
        });
    } @catch (NSException *exception) {}
}

- (void)presentAdFromViewController:(UIViewController *)viewController {
    @try { 
        %orig; 
    } @catch (NSException *exception) {}
}

- (void)ad:(id)arg1 didFailToPresentFullScreenContentWithError:(id)arg2 {
    @try {
        id targetSelf = self;
        if ([targetSelf respondsToSelector:@selector(loadAd)]) {
            [targetSelf loadAd];
        }
    } @catch (NSException *exception) {}
}

%end
