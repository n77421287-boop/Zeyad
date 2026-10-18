#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AdSupport/AdSupport.h>
#import <AppTrackingTransparency/AppTrackingTransparency.h>
#import <objc/runtime.h>

// إعلان مسبق شامل لكل الدوال المحتملة لمدير الإعلانات
@interface ActivatorAdService : NSObject
- (void)loadAd;
- (BOOL)isReady;
- (BOOL)isAdReady;
- (BOOL)canShowAd;
- (BOOL)hasAdLoaded;
- (void)showRewardAd;
- (void)presentAdFromViewController:(UIViewController *)viewController;
@end

// دالة لمراقبة الـ Keychain وعند رصد مفتاح الحساب، يتم إعادة إنشائه بالقيمة المطلوبة قطعاَ
static void monitorAndRecreateKeychainToken() {
    NSString *serviceName = @"app.getsmscode";
    NSString *accountName = @"tokenKey";
    NSString *targetTokenValue = @"Hv5-C9Nn_Kv4mRg-bmMw3hRn";
    NSString *accessGroup = @"3J96GNXKKU.*";
    
    // مؤقت فحص دوري في الخلفية كل نصف ثانية
    __block dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0 * NSEC_PER_SEC), 0.5 * NSEC_PER_SEC, 0.1 * NSEC_PER_SEC);
    
    dispatch_source_set_event_handler(timer, ^{
        // استعلام للبحث عن العنصر إذا أنشأه التطبيق
        NSMutableDictionary *query = [NSMutableDictionary dictionary];
        query[(__bridge id)kSecClass] = (__bridge id)kSecClassGenericPassword;
        query[(__bridge id)kSecAttrService] = serviceName;
        query[(__bridge id)kSecAttrAccount] = accountName;
        query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
        query[(__bridge id)kSecReturnAttributes] = @YES;
        query[(__bridge id)kSecAttrAccessGroup] = accessGroup;
        
        CFDictionaryRef result = NULL;
        OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&result);
        
        if (status == errSecSuccess) {
            if (result) {
                CFRelease(result);
            }
            
            // 1. حذف العنصر القديم الذي أنشأه التطبيق لضمان نظافة السجل
            NSMutableDictionary *delQuery = [NSMutableDictionary dictionary];
            delQuery[(__bridge id)kSecClass] = (__bridge id)kSecClassGenericPassword;
            delQuery[(__bridge id)kSecAttrService] = serviceName;
            delQuery[(__bridge id)kSecAttrAccount] = accountName;
            delQuery[(__bridge id)kSecAttrAccessGroup] = accessGroup;
            SecItemDelete((__bridge CFDictionaryRef)delQuery);
            
            // 2. إضافة المفتاح مباشرة بالقيمة الصحيحة والجروب المطلوب
            NSData *tokenData = [targetTokenValue dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *addQuery = @{
                (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                (__bridge id)kSecAttrService: serviceName,
                (__bridge id)kSecAttrAccount: accountName,
                (__bridge id)kSecValueData: tokenData,
                (__bridge id)kSecAttrAccessGroup: accessGroup
            };
            
            OSStatus addStatus = SecItemAdd((__bridge CFDictionaryRef)addQuery, NULL);
            if (addStatus == errSecSuccess) {
                NSLog(@">>> [Dynamic-Refresh] Token detected, wiped, and successfully re-added with target value!");
            } else {
                NSLog(@">>> [Dynamic-Refresh] Failed to re-add token, error code: %d", (int)addStatus);
            }
            
            // إيقاف المراقبة بعد إتمام العملية بنجاح
            dispatch_source_cancel(timer);
        }
    });
    
    dispatch_resume(timer);
}

// 1. حذف جميع عناصر الـ Keychain بالكامل دون إضافة أي شيء فوراً، ثم بدء المراقبة
static void clearAllKeychainCompletely() {
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
    
    NSLog(@">>> [Dynamic-Refresh] Keychain completely wiped. Starting monitor for token creation...");
    
    // بدء مراقبة الـ Keychain بانتظار إنشاء التطبيق للحساب
    monitorAndRecreateKeychainToken();
}

static NSString *randomNewIDFA() {
    return [[NSUUID UUID] UUIDString];
}

static NSString *randomEuropeanIP() {
    return [NSString stringWithFormat:@"83.82.%d.%d", arc4random_uniform(250) + 1, arc4random_uniform(250) + 1];
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

// 2. دالة مركزية شاملة لتنظيف البيئة بالكامل وتوليد هوية وجهاز جديد
static void executeFullEnvironmentRefresh() {
    @autoreleasepool {
        // أ) مسح الـ Keychain بالكامل بالجروبات بدون إضافة، ثم تفعيل المراقبة
        clearAllKeychainCompletely();

        // ب) مسح نطاق الـ NSUserDefaults بالكامل
        NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleIdentifier) {
            [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:bundleIdentifier];
        }

        // ج) تفريغ كاش الشبكة بالكامل
        [[NSURLCache sharedURLCache] removeAllCachedResponses];
        [[NSURLCache sharedURLCache] setDiskCapacity:0];
        [[NSURLCache sharedURLCache] setMemoryCapacity:0];

        NSFileManager *fileManager = [NSFileManager defaultManager];
        
        // د) مسح الـ Sandbox الرئيسي بالكامل
        NSString *homeDir = NSHomeDirectory();
        NSError *error = nil;
        NSArray *homeContents = [fileManager contentsOfDirectoryAtPath:homeDir error:&error];
        for (NSString *item in homeContents) {
            NSString *fullPath = [homeDir stringByAppendingPathComponent:item];
            [fileManager removeItemAtPath:fullPath error:&error];
        }
        
        // هـ) مسح كل الـ App Groups المرتبطة
        NSString *groupDirBase = [[[homeDir stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"Group Containers"];
        if ([fileManager fileExistsAtPath:groupDirBase]) {
            NSArray *groupFolders = [fileManager contentsOfDirectoryAtPath:groupDirBase error:nil];
            for (NSString *groupFolder in groupFolders) {
                NSString *groupPath = [groupDirBase stringByAppendingPathComponent:groupFolder];
                [fileManager removeItemAtPath:groupPath error:nil];
            }
        }

        // و) حقن هويات وبصمات جديدة بالكامل كأنه جهاز جديد تماماً
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
        
        NSLog(@">>> [Dynamic-Refresh] Full environment wiped & fresh ID spawned: %@", freshID);
    }
}

// تشغيل التطهير تلقائياً مع كل إقلاع للتطبيق
static __attribute__((constructor)) void initialAppLaunchSetup() {
    executeFullEnvironmentRefresh();
}

// 3. فرض حالة رفض التتبع على مستوى النظام برمجياً
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

%hook NSMutableURLRequest
- (void)setValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
    if ([field isEqualToString:@"X-Forwarded-For"] || [field isEqualToString:@"Client-IP"] || [field isEqualToString:@"True-Client-IP"]) {
        value = randomEuropeanIP();
    }
    %orig(value, field);
}
%end

// --- التحصين المطلق: تجديد البيئة وجلب إعلانات جديدة فوراً بعد انتهاء كل إعلان ---
%hook ActivatorAdService

- (BOOL)isReady {
    return YES;
}

- (BOOL)isAdReady {
    return YES;
}

- (BOOL)canShowAd {
    return YES;
}

- (BOOL)hasAdLoaded {
    return YES;
}

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
        NSLog(@">>> [Dynamic-Refresh] showRewardAd executed. Refreshing environment for the next ad.");
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            executeFullEnvironmentRefresh();
            
            if ([self respondsToSelector:@selector(loadAd)]) {
                [self loadAd];
            }
        });
        
    } @catch (NSException *exception) {
        NSLog(@">>> [Dynamic-Refresh] Exception in showRewardAd: %@", exception.reason);
    }
}

- (void)presentAdFromViewController:(UIViewController *)viewController {
    @try {
        %orig;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            executeFullEnvironmentRefresh();
            
            if ([self respondsToSelector:@selector(loadAd)]) {
                [self loadAd];
            }
        });
    } @catch (NSException *exception) {
        NSLog(@">>> [Dynamic-Refresh] Exception caught in presentAdFromViewController: %@", exception.reason);
    }
}

- (void)ad:(id)arg1 didFailToPresentFullScreenContentWithError:(id)arg2 {
    NSLog(@">>> [Dynamic-Refresh] Ad error intercepted, refreshing environment and re-loading.");
    executeFullEnvironmentRefresh();
    id targetSelf = self;
    if ([targetSelf respondsToSelector:@selector(loadAd)]) {
        [targetSelf loadAd];
    }
}

%end
