#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AdSupport/AdSupport.h>
#import <AppTrackingTransparency/AppTrackingTransparency.h>
#import <objc/runtime.h>
#import <objc/message.h>

// إعلان مسبق شامل لكل الدوال المحتملة لمدير الإعلانات
@interface ActivatorAdService : NSObject
- (void)loadAd;
- (BOOL)isReady;
- (BOOL)isAdReady;
- (BOOL)canShowAd;
- (BOOL)hasAdLoaded;
- (void)showRewardAd;
- (void)presentAdFromViewController:(UIViewController *)viewController;
- (void)grantReward;
@end

// 1. تنظيف الـ Keychain مع الحفاظ التام والآمن حصرياً على الـ tokenKey
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
                NSString *service = item[(__bridge id)kSecAttrService];
                
                if (![account isEqualToString:@"tokenKey"]) {
                    NSMutableDictionary *delQuery = [NSMutableDictionary dictionaryWithDictionary:item];
                    delQuery[(__bridge id)kSecClass] = secClass;
                    SecItemDelete((__bridge CFDictionaryRef)delQuery);
                } else {
                    NSLog(@">>> [Full-Simulate] tokenKey safely preserved: %@", service);
                }
            }
            if (result) {
                CFRelease(result);
            }
        }
    }
}

static NSString *randomNewIDFA() {
    return [[NSUUID UUID] UUIDString];
}

// دالة الـ IP الوهمي التي طلبت عدم حذفها
static NSString *randomEuropeanIP() {
    return [NSString stringWithFormat:@"82.92.%d.%d", arc4random_uniform(250) + 1, arc4random_uniform(250) + 1];
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

// 2. محاكاة حذف التطبيق من الجذور وتثبيته من جديد
static void simulateFreshAppReinstallation() {
    @autoreleasepool {
        clearKeychainExceptToken();

        NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleIdentifier) {
            [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:bundleIdentifier];
        }

        NSString *homeDir = NSHomeDirectory();
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSArray *subfoldersToWipe = @[@"Documents", @"Library", @"tmp"];
        
        for (NSString *folder in subfoldersToWipe) {
            NSString *folderPath = [homeDir stringByAppendingPathComponent:folder];
            if ([fileManager fileExistsAtPath:folderPath]) {
                NSArray *contents = [fileManager contentsOfDirectoryAtPath:folderPath error:nil];
                for (NSString *item in contents) {
                    if ([item isEqualToString:@"Caches"] || [item isEqualToString:@"Preferences"] || [item isEqualToString:@"Application Support"] || [item isEqualToString:@"tmp"]) {
                        NSString *subPath = [folderPath stringByAppendingPathComponent:item];
                        NSArray *subContents = [fileManager contentsOfDirectoryAtPath:subPath error:nil];
                        for (NSString *subItem in subContents) {
                            if (![subItem containsString:@"WebKit"] && ![subItem containsString:@"Preferences"]) {
                                NSString *finalPath = [subPath stringByAppendingPathComponent:subItem];
                                [fileManager removeItemAtPath:finalPath error:nil];
                            }
                        }
                    } else {
                        NSString *finalPath = [folderPath stringByAppendingPathComponent:item];
                        [fileManager removeItemAtPath:finalPath error:nil];
                    }
                }
            }
        }
        
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
        
        NSLog(@">>> [Full-Simulate] Sandbox completely wiped & fresh clean-install simulated with ID: %@", freshID);
    }
}

// 3. تطبيق الـ Runtime Hooks للدوال النظامية ومدير الإعلانات
static NSUInteger replacement_trackingAuthorizationStatus(id self, SEL _cmd) {
    return 2; // Denied
}

static NSUUID * replacement_identifierForVendor(id self, SEL _cmd) {
    return [NSUUID UUID];
}

static NSUUID * replacement_advertisingIdentifier(id self, SEL _cmd) {
    return [NSUUID UUID];
}

static BOOL replacement_isAdvertisingTrackingEnabled(id self, SEL _cmd) {
    return NO;
}

// Hook لـ NSMutableURLRequest لتزوير الهيدر والـ IP الوهمي
static void (*original_setValue_forHTTPHeaderField)(id, SEL, NSString *, NSString *);
static void replacement_setValue_forHTTPHeaderField(id self, SEL _cmd, NSString *value, NSString *field) {
    if ([field isEqualToString:@"X-Forwarded-For"] || [field isEqualToString:@"Client-IP"] || [field isEqualToString:@"True-Client-IP"]) {
        value = randomEuropeanIP();
    }
    if (original_setValue_forHTTPHeaderField) {
        original_setValue_forHTTPHeaderField(self, _cmd, value, field);
    }
}

static BOOL replacement_isReady(id self, SEL _cmd) { return YES; }
static BOOL replacement_isAdReady(id self, SEL _cmd) { return YES; }
static BOOL replacement_canShowAd(id self, SEL _cmd) { return YES; }
static BOOL replacement_hasAdLoaded(id self, SEL _cmd) { return YES; }

static void replacement_loadAd(id self, SEL _cmd) {
    id targetSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if ([targetSelf respondsToSelector:NSSelectorFromString(@"loadAd")]) {
            NSLog(@">>> [Full-Simulate] loadAd triggered safely.");
        }
    });
}

static void replacement_showRewardAd(id self, SEL _cmd) {
    @try {
        NSLog(@">>> [Full-Simulate] showRewardAd executed successfully.");
    } @catch (NSException *exception) {
        NSLog(@">>> [Full-Simulate] Exception caught in showRewardAd, bypassing safely: %@", exception.reason);
    }
}

// نقطة الدخول الرئيسية للحقن المباشر عبر eSign
__attribute__((constructor)) static void initializer() {
    @autoreleasepool {
        simulateFreshAppReinstallation();
        
        Class attClass = objc_getClass("ATTrackingManager");
        if (attClass) {
            Method m = class_getClassMethod(attClass, @selector(trackingAuthorizationStatus));
            if (m) method_setImplementation(m, (IMP)replacement_trackingAuthorizationStatus);
        }
        
        Class uiDevClass = objc_getClass("UIDevice");
        if (uiDevClass) {
            Method m = class_getInstanceMethod(uiDevClass, @selector(identifierForVendor));
            if (m) method_setImplementation(m, (IMP)replacement_identifierForVendor);
        }
        
        Class asIdClass = objc_getClass("ASIdentifierManager");
        if (asIdClass) {
            Method m = class_getInstanceMethod(asIdClass, @selector(advertisingIdentifier));
            if (m) method_setImplementation(m, (IMP)replacement_advertisingIdentifier);
            Method m2 = class_getInstanceMethod(asIdClass, @selector(isAdvertisingTrackingEnabled));
            if (m2) method_setImplementation(m2, (IMP)replacement_isAdvertisingTrackingEnabled);
        }
        
        // تفعيل الـ Hook لـ NSMutableURLRequest مع استخدام دالة الـ IP الوهمي
        Class reqClass = objc_getClass("NSMutableURLRequest");
        if (reqClass) {
            Method m = class_getInstanceMethod(reqClass, @selector(setValue:forHTTPHeaderField:));
            if (m) {
                original_setValue_forHTTPHeaderField = (void(*)(id, SEL, NSString *, NSString *))method_getImplementation(m);
                method_setImplementation(m, (IMP)replacement_setValue_forHTTPHeaderField);
            }
        }
        
        Class adServiceClass = objc_getClass("ActivatorAdService");
        if (adServiceClass) {
            SEL selectors[] = {
                @selector(isReady),
                @selector(isAdReady),
                @selector(canShowAd),
                @selector(hasAdLoaded),
                @selector(loadAd),
                @selector(showRewardAd)
            };
            
            IMP implementations[] = {
                (IMP)replacement_isReady,
                (IMP)replacement_isAdReady,
                (IMP)replacement_canShowAd,
                (IMP)replacement_hasAdLoaded,
                (IMP)replacement_loadAd,
                (IMP)replacement_showRewardAd
            };
            
            for (int i = 0; i < 6; i++) {
                Method m = class_getInstanceMethod(adServiceClass, selectors[i]);
                if (m) {
                    method_setImplementation(m, implementations[i]);
                }
            }
        }
        
        NSLog(@">>> [Non-Jailbroken dylib] Successfully loaded, IP spoofed & hooked via eSign!");
    }
}
