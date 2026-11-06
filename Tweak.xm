#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AdSupport/AdSupport.h>
#import <AppTrackingTransparency/AppTrackingTransparency.h>
#import <Security/Security.h>
#import <CoreLocation/CoreLocation.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <CoreTelephony/CTCarrier.h>
#import <SystemConfiguration/CaptiveNetwork.h>
#import <sys/utsname.h>
#import <objc/runtime.h>

extern void executeFullEnvironmentRefresh(void);

// متغيرات عامة لحفظ الـ IDFA و الـ IDFV والـ GPS المتجدد لكل جلسة
static NSString *currentRandomIDFA = nil;
static NSString *currentRandomIDFV = nil;
static double currentLatitude = 33.7490;   // خط عرض أتلانتا الافتراضي
static double currentLongitude = -84.3880; // خط طول أتلانتا الافتراضي

// توليد إحداثيات قريبة جداً في أتلانتا مع كل تدوير لتجنب الحظر
static void randomizeAtlantaCoordinates() {
    // تغيير طفيف عشوائي بأمتار معدودة داخل أتلانتا
    double latOffset = ((double)(arc4random() % 100) - 50) / 10000.0;
    double lonOffset = ((double)(arc4random() % 100) - 50) / 10000.0;
    currentLatitude = 33.7490 + latOffset;
    currentLongitude = -84.3880 + lonOffset;
}

// 1. حذف جميع عناصر الـ Keychain بالكامل ديناميكياً وجذرياً ثم إضافة التوكن الجديد
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
        NSLog(@">>> [Ultimate-Refresh] Keychain wiped & tokenKey added.");
    } else {
        [addQuery removeObjectForKey:(__bridge id)kSecAttrAccessGroup];
        SecItemDelete((__bridge CFDictionaryRef)addQuery);
        OSStatus fallbackStatus = SecItemAdd((__bridge CFDictionaryRef)addQuery, NULL);
        if (fallbackStatus == errSecSuccess) {
            NSLog(@">>> [Ultimate-Refresh] Keychain wiped via fallback.");
        } else {
            NSLog(@">>> [Ultimate-Refresh] Failed to add tokenKey, error: %d", (int)fallbackStatus);
        }
    }
}

// 2. دالة التطهير والتدوير الشاملة للبيئة بأكملها
void executeFullEnvironmentRefresh() {
    @autoreleasepool {
        currentRandomIDFA = [[NSUUID UUID] UUIDString];
        currentRandomIDFV = [[NSUUID UUID] UUIDString];
        randomizeAtlantaCoordinates();
        
        clearAllKeychainAndAddNewItem();

        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *homeDir = NSHomeDirectory();
        NSError *error = nil;
        
        // مسح الكوكيز بالكامل
        NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
        for (NSHTTPCookie *cookie in [cookieStorage cookies]) {
            [cookieStorage deleteCookie:cookie];
        }
        
        // مسح الإعدادات وموافقات الـ CMP والإعلانات
        NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleIdentifier) {
            [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:bundleIdentifier];
        }
        
        NSDictionary *defaultsDict = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
        for (NSString *key in [defaultsDict allKeys]) {
            if ([key hasPrefix:@"IABTCF_"] || [key containsString:@"CMP"] || [key containsString:@"Consent"] || [key containsString:@"FCCDCF"]) {
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
            }
        }
        [[NSUserDefaults standardUserDefaults] synchronize];

        // مسح الملفات والمجلدات المؤقتة و الـ Caches
        NSArray *homeContents = [fileManager contentsOfDirectoryAtPath:homeDir error:&error];
        for (NSString *item in homeContents) {
            NSString *fullPath = [homeDir stringByAppendingPathComponent:item];
            [fileManager removeItemAtPath:fullPath error:&error];
            error = nil;
        }
        
        // مسح الحاويات الجماعية (Group Containers)
        NSString *groupDirBase = [[[homeDir stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"Group Containers"];
        if ([fileManager fileExistsAtPath:groupDirBase]) {
            NSArray *groupFolders = [fileManager contentsOfDirectoryAtPath:groupDirBase error:nil];
            for (NSString *groupFolder in groupFolders) {
                NSString *groupPath = [groupDirBase stringByAppendingPathComponent:groupFolder];
                [fileManager removeItemAtPath:groupPath error:&error];
                error = nil;
            }
        }

        NSLog(@">>> [Ultimate-Refresh] ATLANTA ENVIRONMENT REBORN. IDFA: %@ | GPS: %f, %f", currentRandomIDFA, currentLatitude, currentLongitude);
    }
}

// 3. نافذة الزر العائم الاحترافي
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
    [self->refreshButton setTitle:@"🇺🇸 أتلانتا الخارق 🔄" forState:UIControlStateNormal];
    [self->refreshButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self->refreshButton.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.8 alpha:0.95];
    self->refreshButton.layer.cornerRadius = 20;
    self->refreshButton.layer.shadowColor = [[UIColor blackColor] CGColor];
    self->refreshButton.layer.shadowOffset = CGSizeMake(0, 2);
    self->refreshButton.layer.shadowOpacity = 0.5;
    self->refreshButton.layer.shadowRadius = 4;
    
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    CGFloat screenWidth = screenBounds.size.width;
    self->refreshButton.frame = CGRectMake(screenWidth - 195, 60, 180, 40);
    
    [self->refreshButton addTarget:self action:@selector(handleRefreshButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    
    self->floatingWindow.targetButton = self->refreshButton;
    [emptyVC.view addSubview:self->refreshButton];
    [self->floatingWindow setHidden:NO];
}

- (void)showSuccessAlertFromRoot:(UIViewController *__strong)rootVC {
    UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"تم التجديد الشامل في أتلانتا" 
                                                                           message:@"تم تغيير كافة بيانات الجوال، الشبكة، الإحداثيات، وتطهير التطبيق من الجذور بنجاح!" 
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
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"جاري إعادة تهيئة البيئة بأتلانتا..." 
                                                               message:@"محاكاة هويات أمريكية وتطهير الجذور..." 
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

// بدء التشغيل
%ctor {
    currentRandomIDFA = [[NSUUID UUID] UUIDString];
    currentRandomIDFV = [[NSUUID UUID] UUIDString];
    randomizeAtlantaCoordinates();
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[FloatingButtonManager sharedInstance] showFloatingButton];
    });
}

// ==========================================
// 4. طبقات الخداع الأمني والتقني العميق (Deep Spoofing Hooks)
// ==========================================

%hook UIDevice
- (NSUUID *)identifierForVendor {
    if (currentRandomIDFV) {
        return [[NSUUID alloc] initWithUUIDString:currentRandomIDFV];
    }
    return %orig;
}
- (NSString *)model {
    return @"iPhone";
}
- (NSString *)systemName {
    return @"iOS";
}
%end

%hook ASIdentifierManager
- (NSUUID *)advertisingIdentifier {
    if (currentRandomIDFA) {
        return [[NSUUID alloc] initWithUUIDString:currentRandomIDFA];
    }
    return %orig;
}
%end

// خداع الـ Locale لجعل الدولة الولايات المتحدة (US) واللغة en_US
%hook NSLocale
+ (NSLocale *)currentLocale {
    return [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
}
- (NSString *)countryCode {
    return @"US";
}
- (NSString *)objectForKey:(id)key {
    if ([key isEqualToString:NSLocaleCountryCode]) {
        return @"US";
    }
    if ([key isEqualToString:NSLocaleLanguageCode]) {
        return @"en";
    }
    return %orig;
}
%end

// خداع التوقيت ليكون بتوقيت أتلانتا (America/New_York)
%hook NSTimeZone
+ (NSTimeZone *)systemTimeZone {
    return [NSTimeZone timeZoneWithName:@"America/New_York"];
}
+ (NSTimeZone *)localTimeZone {
    return [NSTimeZone timeZoneWithName:@"America/New_York"];
}
- (NSString *)name {
    return @"America/New_York";
}
%end

// خداع لغة الجهاز ومتجر التطبيقات
%hook NSBundle
- (NSArray *)preferredLocalizations {
    return @[@"en", @"en-US"];
}
+ (NSArray *)preferredLocalizationsForBundle:(NSBundle *)bundle {
    return @[@"en", @"en-US"];
}
%end

// خداع شبكة الاتصال والـ Carrier (AT&T - Atlanta, USA)
%hook CTCarrier
- (NSString *)carrierName {
    return @"AT&T";
}
- (NSString *)mobileCountryCode {
    return @"310"; // US MCC
}
- (NSString *)mobileNetworkCode {
    return @"410"; // AT&T MNC
}
- (NSString *)isoCountryCode {
    return @"us";
}
- (BOOL)allowsVOIP {
    return YES;
}
%end

// خداع إحداثيات GPS لتستقر تماماً في أتلانتا، جورجيا مع تحديث ديناميكي
%hook CLLocationManager
- (CLLocation *)location {
    CLLocation *atlantaLocation = [[CLLocation alloc] initWithLatitude:currentLatitude 
                                                              longitude:currentLongitude 
                                                             altitude:245.0 
                                                   horizontalAccuracy:3.0 
                                                     verticalAccuracy:3.0 
                                                               course:0.0 
                                                                speed:0.0 
                                                            timestamp:[NSDate date]];
    return atlantaLocation;
}
- (void)startUpdatingLocation {
    %orig;
    // محاكاة إرسال موقع أتلانتا للمندوب (Delegate) إذا طلب التطبيق التحديثات مباشرة
    id delegate = self.delegate;
    if (delegate && [delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
        CLLocation *loc = [[CLLocation alloc] initWithLatitude:currentLatitude longitude:currentLongitude];
        [delegate locationManager:self didUpdateLocations:@[loc]];
    }
}
%end
