#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AdSupport/AdSupport.h>
#import <AppTrackingTransparency/AppTrackingTransparency.h>
#import <objc/runtime.h>

// ---------------------------------------------------------
// 1. تعريف البروتوكول الخاص لاعتراض وتزوير الآي بي فقط
// ---------------------------------------------------------
@interface CustomSpoofingProtocol : NSURLProtocol
@end

@implementation CustomSpoofingProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSString *scheme = [[request URL] scheme];
    if ([scheme caseInsensitiveCompare:@"http"] == NSOrderedSame ||
        [scheme caseInsensitiveCompare:@"https"] == NSOrderedSame) {
        
        // لمنع حدوث حلقة مفرغة (Infinite Loop)
        if ([NSURLProtocol propertyForKey:@"CustomSpoofingHandledKey" inRequest:request]) {
            return NO;
        }
        return YES;
    }
    return NO;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

+ (BOOL)requestIsCacheEquivalent:(NSURLRequest *)a toRequest:(NSURLRequest *)b {
    return [super requestIsCacheEquivalent:a toRequest:b];
}

- (void)startLoading {
    NSMutableURLRequest *mutableReq = [[self request] mutableCopy];
    
    // وضع علامة لمنع إعادة اعتراض نفس الطلب
    [NSURLProtocol setProperty:@YES forKey:@"CustomSpoofingHandledKey" inRequest:mutableReq];
    
    // تزوير الهيدرز الخاصة بالـ IP الوهمي الأوروبي
    NSString *fakeIP = [NSString stringWithFormat:@"83.82.%d.%d", arc4random_uniform(250) + 1, arc4random_uniform(250) + 1];
    [mutableReq setValue:fakeIP forHTTPHeaderField:@"X-Forwarded-For"];
    [mutableReq setValue:fakeIP forHTTPHeaderField:@"Client-IP"];
    [mutableReq setValue:fakeIP forHTTPHeaderField:@"True-Client-IP"];

    // تنفيذ الطلب عبر النظام باستخدام NSURLSession القياسية
    NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:mutableReq completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            [[self client] URLProtocol:self didFailWithError:error];
        } else {
            [[self client] URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageAllowed];
            if (data) {
                [[self client] URLProtocol:self didLoadData:data];
            }
            [[self client] URLProtocolDidFinishLoading:self];
        }
    }];
    [task resume];
}

- (void)stopLoading {
}

@end


// ---------------------------------------------------------
// 2. مسح الـ Keychain بالكامل وحقن التوكن الثابت (كما طلبت)
// ---------------------------------------------------------
static void clearAllKeychainAndAddNewItem() {
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
            (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll,
            (__bridge id)kSecReturnAttributes: @YES
        };
        
        CFArrayRef result = NULL;
        if (SecItemCopyMatching((__bridge CFDictionaryRef)spec, (CFTypeRef *)&result) == errSecSuccess) {
            NSArray *items = (__bridge NSArray *)result;
            for (NSDictionary *item in items) {
                NSMutableDictionary *delQuery = [NSMutableDictionary dictionary];
                delQuery[(__bridge id)kSecClass] = secClass;
                
                NSString *service = item[(__bridge id)kSecAttrService];
                NSString *account = item[(__bridge id)kSecAttrAccount];
                NSString *accessGroup = item[(__bridge id)kSecAttrAccessGroup];
                
                if (service) delQuery[(__bridge id)kSecAttrService] = service;
                if (account) delQuery[(__bridge id)kSecAttrAccount] = account;
                if (accessGroup) delQuery[(__bridge id)kSecAttrAccessGroup] = accessGroup;
                
                OSStatus delStatus = SecItemDelete((__bridge CFDictionaryRef)delQuery);
                if (delStatus != errSecSuccess) {
                    NSMutableDictionary *fallbackQuery = [NSMutableDictionary dictionaryWithDictionary:item];
                    fallbackQuery[(__bridge id)kSecClass] = secClass;
                    SecItemDelete((__bridge CFDictionaryRef)fallbackQuery);
                }
            }
            if (result) {
                CFRelease(result);
            }
        }
    }
    
    // إضافة المفتاح والتوكن الثابت بعد مسح الـ Keychain
    NSString *serviceName = @"app.getsmscode";
    NSString *accountName = @"tokenKey";
    NSString *tokenValue  = @"Hv5-C9Nn_Kv4mRg-bmMw3hRn";
    NSString *accessGroup = @"3J96GNXKKU.*";
    
    NSData *tokenData = [tokenValue dataUsingEncoding:NSUTF8StringEncoding];
    
    NSDictionary *addQuery = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: serviceName,
        (__bridge id)kSecAttrAccount: accountName,
        (__bridge id)kSecValueData: tokenData,
        (__bridge id)kSecAttrAccessGroup: accessGroup
    };
    
    OSStatus addStatus = SecItemAdd((__bridge CFDictionaryRef)addQuery, NULL);
    if (addStatus == errSecSuccess) {
        NSLog(@">>> [Dynamic-Refresh] Keychain completely wiped & tokenKey successfully added.");
    } else {
        NSLog(@">>> [Dynamic-Refresh] Failed to add tokenKey to Keychain, error code: %d", (int)addStatus);
    }
}

static NSString *randomNewIDFA() {
    return [[NSUUID UUID] UUIDString];
}

static double randomInactivitySeconds() {
    return (double)(864000 + arc4random_uniform(4320000));
}

static NSString *generateFreshTimestamp() {
    NSDate *now = [NSDate date];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSS'+0300'"];
    return [formatter stringFromDate:now];
}

// 3. دالة مركزية لتنظيف البيئة وتوليد الهوية وتفعيل البروتوكول
static void executeFullEnvironmentRefresh() {
    @autoreleasepool {
        // أ) مسح الـ Keychain بالكامل وحقن التوكن الثابت
        clearAllKeychainAndAddNewItem();

        // ب) مسح نطاق الـ NSUserDefaults بالكامل
        NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleIdentifier) {
            [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:bundleIdentifier];
        }

        // ج) تفريغ كاش الشبكة
        [[NSURLCache sharedURLCache] removeAllCachedResponses];
        [[NSURLCache sharedURLCache] setDiskCapacity:0];
        [[NSURLCache sharedURLCache] setMemoryCapacity:0];

        NSFileManager *fileManager = [NSFileManager defaultManager];
        
        // د) مسح الـ Sandbox الرئيسي
        NSString *homeDir = NSHomeDirectory();
        NSError *error = nil;
        NSArray *homeContents = [fileManager contentsOfDirectoryAtPath:homeDir error:&error];
        for (NSString *item in homeContents) {
            NSString *fullPath = [homeDir stringByAppendingPathComponent:item];
            [fileManager removeItemAtPath:fullPath error:&error];
        }
        
        // هـ) مسح الـ App Groups
        NSString *groupDirBase = [[[homeDir stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"Group Containers"];
        if ([fileManager fileExistsAtPath:groupDirBase]) {
            NSArray *groupFolders = [fileManager contentsOfDirectoryAtPath:groupDirBase error:nil];
            for (NSString *groupFolder in groupFolders) {
                NSString *groupPath = [groupDirBase stringByAppendingPathComponent:groupFolder];
                [fileManager removeItemAtPath:groupPath error:&error];
            }
        }

        // و) حقن هويات وبصمات جديدة
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSString *freshID = randomNewIDFA();
        NSString *freshDate = generateFreshTimestamp();
        double dynamicInactivityTime = randomInactivitySeconds();
        
        [defaults setObject:freshID forKey:@"device.id.key"];
        [defaults setObject:freshID forKey:@"com.google.sso.GeneratedDeviceIdentifier"];
        [defaults setObject:freshID forKey:@"AppsFlyerUserId"];
        [defaults setObject:freshID forKey:@"com.firebase.installations.app_id_to_fiid_enforcement"];
        
        [defaults setInteger:2 forKey:@"ATT_Tracking_Status"];
        [defaults setInteger:0 forKey:@"ump_status"];
        [defaults setInteger:0 forKey:@"IABTCF_gdprApplies"];
        
        [defaults setInteger:1 forKey:@"AppsFlyerRealLaunchCounter"];
        [defaults setInteger:0 forKey:@"AppsFlyerReinstallCounter"];
        [defaults setInteger:1 forKey:@"AppsFlyerLaunchKey"];
        
        [defaults setObject:freshDate forKey:@"AppsFlyerInstallDate"];
        [defaults setObject:freshDate forKey:@"AppsFlyerFirstLaunchDate"];
        [defaults setObject:freshDate forKey:@"AppsFlyerInstallTimestamp"];
        
        [defaults setDouble:0.0 forKey:@"AppsFlyerLastSessionDuration"];
        [defaults setDouble:dynamicInactivityTime forKey:@"AppsFlyerTimePassedSincePrevLaunch"];
        [defaults setDouble:dynamicInactivityTime forKey:@"time_passed_since_last_session"];
        [defaults setDouble:dynamicInactivityTime forKey:@"last_activity_interval"];
        
        [defaults synchronize];
        
        // ز) تسجيل البروتوكول الخاص لاعتراض الطلبات وتزوير الآي بي
        [NSURLProtocol registerClass:[CustomSpoofingProtocol class]];
        
        NSLog(@">>> [Dynamic-Refresh] Full environment wiped, tokenKey injected, & Custom Protocol registered.");
    }
}

// تشغيل التطهير وتسجيل البروتوكول تلقائياً عند إقلاع التطبيق
static __attribute__((constructor)) void initialAppLaunchSetup() {
    executeFullEnvironmentRefresh();
}

// 4. هوكات النظام لتوليد هويات جديدة ورفض التتبع
%hook ATTrackingManager
+ (NSUInteger)trackingAuthorizationStatus {
    return 2;
}
%end

%hook UIDevice
- (NSUUID *)identifierForVendor {
    return [NSUUID UUID];
}
%end

%hook ASIdentifierManager
- (NSUUID *)advertisingIdentifier {
    return [NSUUID UUID];
}
- (BOOL)isAdvertisingTrackingEnabled {
    return NO;
}
%end
