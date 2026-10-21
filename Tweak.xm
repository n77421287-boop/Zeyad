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

// توليد توكن عشوائي جديد بنفس صيغة الـ Hex (طول 64 حرفاً سداسياً عشرياً) لمفتاح deviceTokenKey
static NSString *generateRandomHexToken() {
    NSMutableString *token = [NSMutableString stringWithCapacity:64];
    NSString *letters = @"0123456789ABCDEF";
    for (int i = 0; i < 64; i++) {
        u_int32_t index = arc4random_uniform((u_int32_t)[letters length]);
        unichar c = [letters characterAtIndex:index];
        [token appendFormat:@"%C", c];
    }
    return token;
}

// 1. حذف جميع عناصر الـ Keychain ثم حقن كلا التوكنين معاً (tokenKey الأصلي بجانب deviceTokenKey الجديد)
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
    
    // --- العنصر الأول: tokenKey الأصلي ---
    NSString *account1 = @"tokenKey";
    NSString *tokenVal1 = @"Hv5-C9Nn_Kv4mRg-bmMw3hRn";
    NSData *data1 = [tokenVal1 dataUsingEncoding:NSUTF8StringEncoding];
    
    NSMutableDictionary *query1 = [NSMutableDictionary dictionaryWithDictionary:@{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: serviceName,
        (__bridge id)kSecAttrAccount: account1,
        (__bridge id)kSecValueData: data1
    }];
    if (primaryAccessGroup && [primaryAccessGroup length] > 0) {
        query1[(__bridge id)kSecAttrAccessGroup] = primaryAccessGroup;
    }
    SecItemDelete((__bridge CFDictionaryRef)query1);
    OSStatus status1 = SecItemAdd((__bridge CFDictionaryRef)query1, NULL);
    if (status1 != errSecSuccess) {
        [query1 removeObjectForKey:(__bridge id)kSecAttrAccessGroup];
        SecItemDelete((__bridge CFDictionaryRef)query1);
        SecItemAdd((__bridge CFDictionaryRef)query1, NULL);
    }
    
    // --- العنصر الثاني: deviceTokenKey الجديد مع توكن Hex عشوائي بطول 64 حرفاً ---
    NSString *account2 = @"deviceTokenKey";
    NSString *tokenVal2 = generateRandomHexToken();
    NSData *data2 = [tokenVal2 dataUsingEncoding:NSUTF8StringEncoding];
    
    NSMutableDictionary *query2 = [NSMutableDictionary dictionaryWithDictionary:@{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: serviceName,
        (__bridge id)kSecAttrAccount: account2,
        (__bridge id)kSecValueData: data2
    }];
    if (primaryAccessGroup && [primaryAccessGroup length] > 0) {
        query2[(__bridge id)kSecAttrAccessGroup] = primaryAccessGroup;
    }
    SecItemDelete((__bridge CFDictionaryRef)query2);
    OSStatus status2 = SecItemAdd((__bridge CFDictionaryRef)query2, NULL);
    if (status2 != errSecSuccess) {
        [query2 removeObjectForKey:(__bridge id)kSecAttrAccessGroup];
        SecItemDelete((__bridge CFDictionaryRef)query2);
        SecItemAdd((__bridge CFDictionaryRef)query2, NULL);
    }
    
    NSLog(@">>> [Dynamic-Refresh] Both tokenKey and deviceTokenKey successfully injected into Keychain.");
}

static NSString *randomNewIDFA() {
    return [[NSUUID UUID] UUIDString];
}

static NSString *randomEuropeanIP() {
    return [NSString stringWithFormat:@"83.82.%d.%d", arc4random_uniform(250) + 1, arc4random_uniform(250) + 1];
}

// توليد فترة إزاحة عشوائية تتراوح بين 5 أيام إلى 60 يوماً بالثواني
static double randomTimeOffsetSeconds() {
    return (double)(432000 + arc4random_uniform(4752001));
}

// توليد التاريخ بصيغة AppsFlyer الدقيقة الظاهرة في الصور (yyyy-MM-dd'T'HH:mm:ss+0300)
static NSString *generateShiftedTimestamp() {
    double offsetSeconds = randomTimeOffsetSeconds();
    NSDate *shiftedDate = [NSDate dateWithTimeIntervalSinceNow:-offsetSeconds];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss+0300"];
    return [formatter stringFromDate:shiftedDate];
}

// 2. دالة تنظيف شاملة وضبط القيم الزمنية وفتح الإعلانات
void executeFullEnvironmentRefresh() {
    @autoreleasepool {
        clearAllKeychainAndAddNewItem();

        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *homeDir = NSHomeDirectory();
        
        NSError *error = nil;
        NSArray *homeContents = [fileManager contentsOfDirectoryAtPath:homeDir error:&error];
        for (NSString *item in homeContents) {
            NSString *fullPath = [homeDir stringByAppendingPathComponent:item];
            [fileManager removeItemAtPath:fullPath error:&error];
        }
        
        NSArray *subDirs = @[@"Documents", @"Library/Caches", @"Library/Application Support", @"Library/Preferences", @"Library/Cookies", @"tmp"];
        for (NSString *subDir in subDirs) {
            NSString *targetPath = [homeDir stringByAppendingPathComponent:subDir];
            if ([fileManager fileExistsAtPath:targetPath]) {
                NSArray *contents = [fileManager contentsOfDirectoryAtPath:targetPath error:nil];
                for (NSString *file in contents) {
                    NSString *filePath = [targetPath stringByAppendingPathComponent:file];
                    [fileManager removeItemAtPath:filePath error:nil];
                }
            }
        }

        NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleIdentifier) {
            [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:bundleIdentifier];
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
        NSString *shiftedDateStr = generateShiftedTimestamp();
        double shiftedSeconds = randomTimeOffsetSeconds();
        
        NSTimeInterval currentReferenceTime = [[NSDate date] timeIntervalSinceReferenceDate];
        NSTimeInterval shiftedReferenceTime = currentReferenceTime - shiftedSeconds;
        NSTimeInterval shiftedEpochMillis = shiftedReferenceTime * 1000.0;
        double largeIntervalValue = shiftedSeconds * 50.0 + (double)arc4random_uniform(500000);

        // المفاتيح والمعرفات المطابقة للصور
        [defaults setObject:freshID forKey:@"device.id.key"];
        [defaults setObject:freshID forKey:@"com.google.sso.GeneratedDeviceIdentifier"];
        [defaults setObject:freshID forKey:@"AppsFlyerUserId"];
        [defaults setObject:freshID forKey:@"com.firebase.installations.app_id_to_fiid_enforcement"];
        [defaults setObject:freshID forKey:@"igg-userId"];
        [defaults setObject:freshID forKey:@"STAStoredDeveloperUserId"];
        [defaults setObject:freshID forKey:@"STASessionUUID"];

        // تصفير وفتح عدادات الإعلانات تماماً وتجاوز الانتظار
        [defaults setInteger:0 forKey:@"ad_limit_counter"];
        [defaults setInteger:0 forKey:@"daily_ads_watched"];
        [defaults setObject:shiftedDateStr forKey:@"last_ad_watch_date"];
        
        [defaults setInteger:2 forKey:@"ATT_Tracking_Status"];
        [defaults setInteger:2 forKey:@"ump_status"];
        [defaults setInteger:1 forKey:@"consent.gdpr.value"];
        [defaults setInteger:0 forKey:@"consent.gdpr.explicit"];
        [defaults setInteger:1 forKey:@"trackedKey"];
        [defaults setInteger:1 forKey:@"STAPas"];

        [defaults setInteger:4 forKey:@"AppsFlyerCounter"];
        [defaults setInteger:4 forKey:@"AppsFlyerRealLaunchCounter"];
        [defaults setInteger:0 forKey:@"AppsFlyerReinstallCounter"];
        [defaults setInteger:1 forKey:@"AppsFlyerLaunchKey"];
        [defaults setInteger:1 forKey:@"AppsFlyerReadyToSendEvents"];

        [defaults setObject:shiftedDateStr forKey:@"AppsFlyerInstallDate"];
        [defaults setObject:shiftedDateStr forKey:@"AppsFlyerFirstLaunchDate"];
        [defaults setObject:shiftedDateStr forKey:@"AppsFlyerInstallTimestamp"];
        [defaults setObject:shiftedDateStr forKey:@"AppsFlyerInitDate"];

        [defaults setDouble:1.0 forKey:@"AppsFlyerLastSessionDuration"];
        [defaults setDouble:shiftedSeconds forKey:@"AppsFlyerTimePassedSincePrevLaunch"];
        [defaults setDouble:largeIntervalValue forKey:@"time_passed_since_last_session"];
        [defaults setDouble:largeIntervalValue forKey:@"last_activity_interval"];

        [defaults setDouble:shiftedEpochMillis forKey:@"STAFirstSessionTime"];
        [defaults setDouble:shiftedEpochMillis forKey:@"STACurrentSessionStartTime"];
        [defaults setDouble:shiftedReferenceTime forKey:@"consent.gdpr.time"];
        [defaults setDouble:shiftedReferenceTime forKey:@"SKPurchaseIntentUpdatesLastChecked"];

        [defaults synchronize];
        
        NSLog(@">>> [Manual-Refresh] BOTH TOKENS INJECTED & TIME SHIFTED 5-60 DAYS SUCCESSFUL: %@", freshID);
    }
}

// 3. نافذة مخصصة للزر العائم
@interface FloatingButtonWindow : UIWindow
@property (nonatomic, strong) UIButton *targetButton;
@end

@implementation FloatingButtonWindow
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if (!self.targetButton) return NO;
    CGPoint buttonPoint = [self convertPoint:point toView:self.targetButton];
    return [self.targetButton pointInside:buttonPoint withEvent:event];
}
@end

@interface FloatingButtonManager : NSObject
+ (instancetype)sharedInstance;
- (void)showFloatingButton;
@end

@implementation FloatingButtonManager {
    FloatingButtonWindow *floatingWindow;
    UIButton *refreshButton;
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
    
    self->refreshButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self->refreshButton setTitle:@"🔄 تطهير شامل" forState:UIControlStateNormal];
    [self->refreshButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self->refreshButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.5 blue:1.0 alpha:0.85];
    self->refreshButton.layer.cornerRadius = 20;
    self->refreshButton.layer.shadowColor = [[UIColor blackColor] CGColor];
    self->refreshButton.layer.shadowOffset = CGSizeMake(0, 2);
    self->refreshButton.layer.shadowOpacity = 0.4;
    self->refreshButton.layer.shadowRadius = 4;
    
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    CGFloat screenWidth = screenBounds.size.width;
    self->refreshButton.frame = CGRectMake(screenWidth - 160, 60, 140, 40);
    
    [self->refreshButton addTarget:self action:@selector(handleRefreshButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    
    self->floatingWindow.targetButton = self->refreshButton;
    [emptyVC.view addSubview:self->refreshButton];
    [self->floatingWindow setHidden:NO];
}

- (void)showSuccessAlertFromRoot:(UIViewController * _Nonnull)rootVC {
    UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"تم بنجاح" 
                                                                           message:@"تم تطهير البيانات، حقن مفتاحي الـ Keychain (tokenKey و deviceTokenKey) معاً، وخداع الوقت (5 إلى 60 يوماً)." 
                                                                    preferredStyle:UIAlertControllerStyleAlert];
    
    [successAlert addAction:[UIAlertAction actionWithTitle:@"حسناً" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        exit(0);
    }]];
    
    [rootVC presentViewController:successAlert animated:YES completion:nil];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        exit(0);
    });
}

- (void)handleRefreshButtonTapped {
    UIViewController *rootVC = self->floatingWindow.rootViewController;
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"تنظيف وتطهير شامل" 
                                                               message:@"جاري حقن التوكنين معاً في الـ Keychain وتطهير البيانات..." 
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

// إطلاق الزر المستقل فور بدء تشغيل التطبيق
%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[FloatingButtonManager sharedInstance] showFloatingButton];
    });
}

// بقية الهوكات والتعديلات
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
- (void)setValue:(NSString * _Nullable)value forHTTPHeaderField:(NSString *)field {
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
