#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AdSupport/AdSupport.h>
#import <AppTrackingTransparency/AppTrackingTransparency.h>
#import <Security/Security.h>
#import <objc/runtime.h>

@interface ActivatorAdService : NSObject
- (void)loadAd;
- (BOOL)isReady;
- (BOOL)isAdReady;
- (BOOL)canShowAd;
- (BOOL)hasAdLoaded;
- (void)showRewardAd;
- (void)presentAdFromViewController:(UIViewController *)viewController;
@end

extern void executeFullEnvironmentRefresh(void);

// 1. حذف جميع عناصر الـ Keychain بالكامل ديناميكياً وجذرياً (باستخدام الـ Access Group الخاص بك) ثم إضافة المفتاح الجديد
static void clearAllKeychainAndAddNewItem() {
    NSArray *secClasses = @[
        (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecClassInternetPassword,
        (__bridge id)kSecClassCertificate,
        (__bridge id)kSecClassKey,
        (__bridge id)kSecClassIdentity
    ];
    
    NSString *primaryAccessGroup = @"3J96GNXKKU.*";
    
    for (id secClass in secClasses) {
        NSDictionary *generalQuery = @{
            (__bridge id)kSecClass: secClass
        };
        SecItemDelete((__bridge CFDictionaryRef)generalQuery);
        
        if (primaryAccessGroup && [primaryAccessGroup length] > 0) {
            NSDictionary *groupQuery = @{
                (__bridge id)kSecClass: secClass,
                (__bridge id)kSecAttrAccessGroup: primaryAccessGroup
            };
            SecItemDelete((__bridge CFDictionaryRef)groupQuery);
        }
        
        NSMutableDictionary *spec = [NSMutableDictionary dictionaryWithDictionary:@{
            (__bridge id)kSecClass: secClass,
            (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll,
            (__bridge id)kSecReturnPersistentRef: @YES
        }];
        
        if (primaryAccessGroup && [primaryAccessGroup length] > 0) {
            spec[(__bridge id)kSecAttrAccessGroup] = primaryAccessGroup;
        }
        
        CFArrayRef result = NULL;
        if (SecItemCopyMatching((__bridge CFDictionaryRef)spec, (CFTypeRef *)&result) == errSecSuccess) {
            NSArray *items = (__bridge NSArray *)result;
            for (id itemRef in items) {
                NSDictionary *refQuery = @{
                    (__bridge id)kSecValueRef: itemRef
                };
                SecItemDelete((__bridge CFDictionaryRef)refQuery);
            }
            CFRelease(result);
        }
    }
    
    NSString *serviceName = @"app.getsmscode";
    NSString *accountName = @"tokenKey";
    NSString *tokenValue  = @"Hv5-C9Nn_Kv4mRg-bmMw3hRn";
    
    NSData *tokenData = [tokenValue dataUsingEncoding:NSUTF8StringEncoding];
    
    NSMutableDictionary *addQuery = [NSMutableDictionary dictionaryWithDictionary:@{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: serviceName,
        (__bridge id)kSecAttrAccount: accountName,
        (__bridge id)kSecValueData: tokenData
    }];
    
    if (primaryAccessGroup && [primaryAccessGroup length] > 0) {
        addQuery[(__bridge id)kSecAttrAccessGroup] = primaryAccessGroup;
    }
    
    SecItemDelete((__bridge CFDictionaryRef)addQuery);
    OSStatus addStatus = SecItemAdd((__bridge CFDictionaryRef)addQuery, NULL);
    
    if (addStatus == errSecSuccess) {
        NSLog(@">>> [Dynamic-Refresh] Keychain completely wiped with group 3J96GNXKKU.* & tokenKey added.");
    } else {
        [addQuery removeObjectForKey:(__bridge id)kSecAttrAccessGroup];
        SecItemDelete((__bridge CFDictionaryRef)addQuery);
        OSStatus fallbackStatus = SecItemAdd((__bridge CFDictionaryRef)addQuery, NULL);
        if (fallbackStatus == errSecSuccess) {
            NSLog(@">>> [Dynamic-Refresh] Keychain wiped & tokenKey added via fallback mode.");
        } else {
            NSLog(@">>> [Dynamic-Refresh] Failed to add tokenKey, error code: %d", (int)fallbackStatus);
        }
    }
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
void executeFullEnvironmentRefresh() {
    @autoreleasepool {
        clearAllKeychainAndAddNewItem();

        NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleIdentifier) {
            [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:bundleIdentifier];
        }

        NSFileManager *fileManager = [NSFileManager defaultManager];
        
        NSString *homeDir = NSHomeDirectory();
        NSError *error = nil;
        NSArray *homeContents = [fileManager contentsOfDirectoryAtPath:homeDir error:&error];
        for (NSString *item in homeContents) {
            NSString *fullPath = [homeDir stringByAppendingPathComponent:item];
            [fileManager removeItemAtPath:fullPath error:&error];
        }
        
        NSString *groupDirBase = [[[homeDir stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"Group Containers"];
        if ([fileManager fileExistsAtPath:groupDirBase]) {
            NSArray *groupFolders = [fileManager contentsOfDirectoryAtPath:groupDirBase error:nil];
            for (NSString *groupFolder in groupFolders) {
                NSString *groupPath = [groupDirBase stringByAppendingPathComponent:groupFolder];
                [fileManager removeItemAtPath:groupPath error:nil];
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
        
        NSLog(@">>> [Manual-Refresh] Full sandbox files, app folders & environment wiped completely: %@", freshID);
    }
}

// 3. نافذة مخصصة مستقلة للزر العائم
@interface FloatingButtonWindow : UIWindow
@end

@implementation FloatingButtonWindow
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return [super pointInside:point withEvent:event];
}
@end

@interface FloatingButtonManager : NSObject
+ (instancetype)sharedInstance;
- (void)showFloatingButton;
@end

@implementation FloatingButtonManager {
    FloatingButtonWindow *floatingWindow;
}

+ (instancetype)sharedInstance {
    static FloatingButtonManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[FloatingButtonManager alloc] init];
    });
    return sharedInstance;
}

- (void)showFloatingButton {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->floatingWindow) return;
        
        UIWindowScene *targetScene = nil;
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
                targetScene = (UIWindowScene *)scene;
                break;
            }
        }
        
        if (targetScene) {
            self->floatingWindow = [[FloatingButtonWindow alloc] initWithWindowScene:targetScene];
        } else {
            self->floatingWindow = [[FloatingButtonWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        }
        
        self->floatingWindow.windowLevel = UIWindowLevelAlert + 100;
        self->floatingWindow.backgroundColor = [UIColor clearColor];
        
        UIViewController *emptyVC = [[UIViewController alloc] init];
        emptyVC.view.backgroundColor = [UIColor clearColor];
        self->floatingWindow.rootViewController = emptyVC;
        
        UIButton *refreshButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [refreshButton setTitle:@"🔄 تطهير شامل" forState:UIControlStateNormal];
        [refreshButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        refreshButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.5 blue:1.0 alpha:0.85];
        refreshButton.layer.cornerRadius = 20;
        refreshButton.layer.shadowColor = [[UIColor blackColor] CGColor];
        refreshButton.layer.shadowOffset = CGSizeMake(0, 2);
        refreshButton.layer.shadowOpacity = 0.4;
        refreshButton.layer.shadowRadius = 4;
        
        refreshButton.frame = CGRectMake(20, 60, 140, 40);
        
        [refreshButton addTarget:self action:@selector(handleRefreshButtonTapped) forControlEvents:UIControlEventTouchUpInside];
        
        [emptyVC.view addSubview:refreshButton];
        [self->floatingWindow setHidden:NO];
    });
}

// تم تسطيح الدوال وتجنب التداخل العميق لضمان صحة الترجمة
- (void)showSuccessAlertFromRoot:(UIViewController *)rootVC {
    UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"تم بنجاح" 
                                                                           message:@"تم مسح جميع ملفات ومجلدات التطبيق والـ NSUserDefaults وزرع التوكن الجديد." 
                                                                    preferredStyle:UIAlertControllerStyleAlert];
    [successAlert addAction:[UIAlertAction actionWithTitle:@"حسناً" style:UIAlertActionStyleDefault handler:nil]];
    [rootVC presentViewController:successAlert animated:YES completion:nil];
}

- (void)handleRefreshButtonTapped {
    UIViewController *rootVC = self->floatingWindow.rootViewController;
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"تنظيف وتطهير البيئة" 
                                                               message:@"جاري مسح كافة ملفات ومجلدات التطبيق والـ Keychain..." 
                                                        preferredStyle:UIAlertControllerStyleAlert];
    
    __weak typeof(self) weakSelf = self;
    [rootVC presentViewController:alert animated:YES completion:^{
        executeFullEnvironmentRefresh();
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [alert dismissViewControllerAnimated:YES completion:^{
                if (weakSelf) {
                    [weakSelf showSuccessAlertFromRoot:rootVC];
                }
            }];
        });
    }];
}

@end

// إطلاق الزر المستقل عبر %ctor
%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[FloatingButtonManager sharedInstance] showFloatingButton];
    });
}

// بقية الهوكات
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
}

- (void)showRewardAd {
    @try {
        %orig;
    } @catch (NSException *exception) {
        NSLog(@">>> [Dynamic-Refresh] Exception in showRewardAd: %@", exception.reason);
    }
}

- (void)presentAdFromViewController:(UIViewController *)viewController {
    @try {
        %orig;
    } @catch (NSException *exception) {
        NSLog(@">>> [Dynamic-Refresh] Exception caught in presentAdFromViewController: %@", exception.reason);
    }
}

- (void)ad:(id)arg1 didFailToPresentFullScreenContentWithError:(id)arg2 {
    id targetSelf = self;
    if ([targetSelf respondsToSelector:@selector(loadAd)]) {
        [targetSelf loadAd];
    }
}

%end
