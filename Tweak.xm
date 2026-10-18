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

// 1. حذف شامل وجذري للـ Keychain لكل المجموعات والتصنيفات
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
            (__bridge id)kSecReturnAttributes: @YES,
            (__bridge id)kSecReturnData: @NO
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
                
                SecItemDelete((__bridge CFDictionaryRef)delQuery);
            }
            if (result) {
                CFRelease(result);
            }
        }
        
        NSDictionary *genericDel = @{ (__bridge id)kSecClass: secClass };
        SecItemDelete((__bridge CFDictionaryRef)genericDel);
    }
    
    // إعادة إضافة مفتاح الـ Token الأساسي المطلوب فقط (إن أردت الحفاظ على بيانات الدخول الأساسية)
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
    
    SecItemAdd((__bridge CFDictionaryRef)addQuery, NULL);
}

// 2. دالة التطهير الشامل وتزوير الهوية تلقائياً (تطابق عمل الأداة في الصور)
static void executeFullEnvironmentRefresh() {
    @autoreleasepool {
        // أ) مسح الـ Keychain بالكامل بالجروبات
        clearAllKeychainAndAddNewItem();

        // ب) مسح نطاق الـ NSUserDefaults بالكامل
        NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleIdentifier) {
            [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:bundleIdentifier];
        }
        [[NSUserDefaults standardUserDefaults] synchronize];

        // ج) تفريغ كاش الشبكة بالكامل
        [[NSURLCache sharedURLCache] removeAllCachedResponses];
        [[NSURLCache sharedURLCache] setDiskCapacity:0];
        [[NSURLCache sharedURLCache] setMemoryCapacity:0];

        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSError *error = nil;
        
        // د) مسح كافة محتويات Sandbox التطبيق الرئيسية (Documents, Library, tmp, Caches)
        NSString *homeDir = NSHomeDirectory();
        NSArray *homeContents = [fileManager contentsOfDirectoryAtPath:homeDir error:&error];
        for (NSString *item in homeContents) {
            NSString *fullPath = [homeDir stringByAppendingPathComponent:item];
            [fileManager removeItemAtPath:fullPath error:&error];
        }
        
        // هـ) مسح مجلدات الـ Group Containers المرتبطة بالتطبيق والـ SDKs
        NSString *groupDirBase = [[[homeDir stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"Group Containers"];
        if ([fileManager fileExistsAtPath:groupDirBase]) {
            NSArray *groupFolders = [fileManager contentsOfDirectoryAtPath:groupDirBase error:nil];
            for (NSString *groupFolder in groupFolders) {
                if ([groupFolder containsString:@"app.getsmscode"] || [groupFolder containsString:@"appsflyer"] || [groupFolder containsString:@"adjust"] || [groupFolder containsString:@"firebase"]) {
                    NSString *groupPath = [groupDirBase stringByAppendingPathComponent:groupFolder];
                    [fileManager removeItemAtPath:groupPath error:&error];
                }
            }
        }

        NSLog(@">>> [Auto-Spoof & Wipe] Device identity spoofed and app data completely erased automatically.");
    }
}

// تشغيل التطهير وتزوير الهوية تلقائياً فور إقلاع التطبيق
static __attribute__((constructor)) void initialAppLaunchSetup() {
    executeFullEnvironmentRefresh();
}

// 3. فرض حالة رفض التتبع وهويات عشوائية جديدة تماماً في كل تشغيل
%hook ATTrackingManager
+ (NSUInteger)trackingAuthorizationStatus {
    return 2; // Restricted / Denied
}
%end

%hook UIDevice
- (NSUUID *)identifierForVendor {
    return [NSUUID UUID]; // توليد IDFV عشوائي جديد كلياً في كل مرة
}
%end

%hook ASIdentifierManager
- (NSUUID *)advertisingIdentifier {
    return [NSUUID UUID]; // توليد معرف إعلانات (IDFA) عشوائي جديد
}
- (BOOL)isAdvertisingTrackingEnabled {
    return NO;
}
%end

static NSString *randomEuropeanIP() {
    return [NSString stringWithFormat:@"83.82.%d.%d", arc4random_uniform(250) + 1, arc4random_uniform(250) + 1];
}

%hook NSMutableURLRequest
- (void)setValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
    if ([field isEqualToString:@"X-Forwarded-For"] || [field isEqualToString:@"Client-IP"] || [field isEqualToString:@"True-Client-IP"]) {
        value = randomEuropeanIP();
    }
    %orig(value, field);
}
%end

// --- إدارة الإعلانات والتنفيذ التلقائي بعد انتهائها ---
%hook ActivatorAdService

- (BOOL)isReady { return YES; }
- (BOOL)isAdReady { return YES; }
- (BOOL)canShowAd { return YES; }
- (BOOL)hasAdLoaded { return YES; }

- (void)loadAd {
    %orig;
    id targetSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if ([targetSelf respondsToSelector:@selector(loadAd)]) {
            [targetSelf loadAd];
        }
    });
}

- (void)showRewardAd {
    @try {
        %orig;
        executeFullEnvironmentRefresh(); // مسح البيانات وتغيير الهوية تلقائياً فور انتهاء الإعلان
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if ([self respondsToSelector:@selector(loadAd)]) {
                [self loadAd];
            }
        });
    } @catch (NSException *exception) {
        NSLog(@">>> [Auto-Refresh] Exception in showRewardAd: %@", exception.reason);
    }
}

- (void)presentAdFromViewController:(UIViewController *)viewController {
    @try {
        %orig;
        executeFullEnvironmentRefresh(); // مسح البيانات وتغيير الهوية تلقائياً بعد عرض الإعلان
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if ([self respondsToSelector:@selector(loadAd)]) {
                [self loadAd];
            }
        });
    } @catch (NSException *exception) {
        NSLog(@">>> [Auto-Refresh] Exception caught in presentAdFromViewController: %@", exception.reason);
    }
}

- (void)ad:(id)arg1 didFailToPresentFullScreenContentWithError:(id)arg2 {
    executeFullEnvironmentRefresh();
    id targetSelf = self;
    if ([targetSelf respondsToSelector:@selector(loadAd)]) {
        [targetSelf loadAd];
    }
}

%end
