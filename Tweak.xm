#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AdSupport/AdSupport.h>
#import <AppTrackingTransparency/AppTrackingTransparency.h>
#import <CoreLocation/CoreLocation.h>
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

extern void executeFullEnvironmentRefresh(BOOL rotateToken);

// قائمة التوكنات الثابتة (25 توكن)
static NSArray<NSString *> *getTokenList() {
    return @[
        @"UUwHSBHjDY4HT2NhAcCZykCz",
        @"QCtHTj1k0dOuGqW29MjiUpDy",
        @"-37n6YQgA0gluM6ehfoyb3Vt",
        @"kR4h2QCnk5evhqv7wYwZmnaG",
        @"Sxda9D0iu8F_NiZaaOd1SIzL",
        @"j6F_zFlKACZ4VCmnhTfJLptx",
        @"MNwLj8ra-1IODCNasj3fgYXf",
        @"uJ6zR8UbYGKzRHEEyHDQ6knC",
        @"VS7xjG3dSitTxYd5kcPebWIn",
        @"9FKwCpDYPTmiXQ-VZOU3pwkl",
        @"PzbNALcprLZWCXETTPfbBpP6",
        @"rwWCl0ifnXQC5VK3oVPSAsht",
        @"Mj5-GpHEreha8Omtgl3TNxrF",
        @"M55KCe0pdBCZ5MwGZx3I2WyV",
        @"AAVKVY83R8fvjZxLtX0XhOl_",
        @"LW51737_HxIT1JgmFgdyqxz3",
        @"gSWnwGEpoLrqBjm8E3YAsgGy",
        @"_DPtrQwEOd4stk8xzrFdfVJ1",
        @"bO5oTiOKAA7udZ6HzQ_emW7V",
        @"c9BZKMFkQrAHjqZE1NFLcj2R",
        @"xHsY6b0cAh9J0JoTAHcQlmS0",
        @"h8tM4zAX5DUIr5yZnnVyt9_d",
        @"9OudkYMCfp21Lluw_0pRBeLa",
        @"_VKdP0o3luEc9lJq-sLyH6a3",
        @"BvHVgcoyop4ppmp30IA3LCg_"
    ];
}

// مسار ملفات الحفظ داخل مجلد Documents (مستثناة من التطهير)
static NSString *getDocumentsFilePath(NSString *fileName) {
    NSString *docsDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    return [docsDir stringByAppendingPathComponent:fileName];
}

static NSInteger getCurrentTokenIndex() {
    NSString *path = getDocumentsFilePath(@"token_index.txt");
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
        if (content) {
            NSInteger index = [content integerValue];
            NSArray *tokens = getTokenList();
            if (index >= 0 && index < tokens.count) return index;
        }
    }
    return 0;
}

static void saveCurrentTokenIndex(NSInteger index) {
    NSString *path = getDocumentsFilePath(@"token_index.txt");
    [([NSString stringWithFormat:@"%ld", (long)index]) writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

static NSInteger moveToNextTokenIndex() {
    NSArray *tokens = getTokenList();
    NSInteger nextIndex = (getCurrentTokenIndex() + 1) % tokens.count;
    saveCurrentTokenIndex(nextIndex);
    return nextIndex;
}

static NSString *getCurrentTokenValue() {
    NSArray *tokens = getTokenList();
    NSInteger index = getCurrentTokenIndex();
    return (index >= 0 && index < tokens.count) ? tokens[index] : tokens[0];
}

// إدارة وتخزين المعرفات والبيانات الوهمية
static NSString *getStoredOrFreshValue(NSString *fileName, NSString * (^generator)(void)) {
    NSString *path = getDocumentsFilePath(fileName);
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:path]) {
        NSString *val = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
        if (val && val.length > 0) return val;
    }
    NSString *newVal = generator();
    [newVal writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    return newVal;
}

static NSString *getCurrentIDFA() {
    return getStoredOrFreshValue(@"spoof_idfa.txt", ^NSString * {
        return [[NSUUID UUID] UUIDString];
    });
}

static NSString *getCurrentVendorID() {
    return getStoredOrFreshValue(@"spoof_vendor.txt", ^NSString * {
        return [[NSUUID UUID] UUIDString];
    });
}

// توليد موديل جهاز عشوائي لأحدث إصدارات آخر سنتين (2025 - 2026)
static NSString *getCurrentDeviceModel() {
    return getStoredOrFreshValue(@"spoof_model.txt", ^NSString * {
        NSArray *models = @[
            @"iPhone17,1", // iPhone 17 Pro
            @"iPhone17,2", // iPhone 17 Pro Max
            @"iPhone17,3", // iPhone 17
            @"iPhone17,4", // iPhone Air
            @"iPhone17,5", // iPhone 17e
            @"iPhone19,2", // iPhone 18 Pro
            @"iPhone19,3", // iPhone 18 Pro Max
            @"iPhone19,4"  // iPhone Duo (Foldable)
        ];
        return models[arc4random_uniform((uint32_t)models.count)];
    });
}

// توليد إصدار نظام تشغيل عشوائي لإصدارات iOS 17 و iOS 18 فقط
static NSString *getCurrentSystemVersion() {
    return getStoredOrFreshValue(@"spoof_ios.txt", ^NSString * {
        NSArray *versions = @[
            @"17.0", @"17.1", @"17.2", @"17.3", @"17.4", @"17.5", @"17.6", @"17.7",
            @"18.0", @"18.1", @"18.2", @"18.3", @"18.4", @"18.5", @"18.6"
        ];
        return versions[arc4random_uniform((uint32_t)versions.count)];
    });
}

// توليد إحداثيات GPS عشوائية داخل هولندا
static NSString *getCurrentNetherlandsCoordinates() {
    return getStoredOrFreshValue(@"spoof_gps.txt", ^NSString * {
        double lat = 51.5 + ((double)(arc4random_uniform(170)) / 100.0); // 51.50 - 53.20
        double lon = 4.3 + ((double)(arc4random_uniform(250)) / 100.0);  // 4.30 - 6.80
        return [NSString stringWithFormat:@"%f,%f", lat, lon];
    });
}

// توليد منطقة زمنية أوروبية عشوائية
static NSString *getCurrentTimeZoneName() {
    return getStoredOrFreshValue(@"spoof_tz.txt", ^NSString * {
        NSArray *timeZones = @[
            @"Europe/Amsterdam",
            @"Europe/Rotterdam",
            @"Europe/Paris",
            @"Europe/Berlin",
            @"Europe/Brussels",
            @"Europe/Rome"
        ];
        return timeZones[arc4random_uniform((uint32_t)timeZones.count)];
    });
}

// توليد لغة عشوائية للجهاز (الهولندية أو الإنجليزية الأوروبية)
static NSString *getCurrentDeviceLanguage() {
    return getStoredOrFreshValue(@"spoof_lang.txt", ^NSString * {
        NSArray *languages = @[@"nl", @"en-NL", @"en-GB", @"fr"];
        return languages[arc4random_uniform((uint32_t)languages.count)];
    });
}

// توليد منطقة جغرافية عشوائية للجهاز (هولندا أو دول أوروبية مجاورة)
static NSString *getCurrentDeviceRegion() {
    return getStoredOrFreshValue(@"spoof_region.txt", ^NSString * {
        NSArray *regions = @[@"NL", @"BE", @"FR", @"DE"];
        return regions[arc4random_uniform((uint32_t)regions.count)];
    });
}

// تجديد كافة البصمات والمعلومات عند التطهير
static void regenerateAllSpoofedData() {
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:getDocumentsFilePath(@"spoof_idfa.txt") error:nil];
    [fm removeItemAtPath:getDocumentsFilePath(@"spoof_vendor.txt") error:nil];
    [fm removeItemAtPath:getDocumentsFilePath(@"spoof_model.txt") error:nil];
    [fm removeItemAtPath:getDocumentsFilePath(@"spoof_ios.txt") error:nil];
    [fm removeItemAtPath:getDocumentsFilePath(@"spoof_gps.txt") error:nil];
    [fm removeItemAtPath:getDocumentsFilePath(@"spoof_tz.txt") error:nil];
    [fm removeItemAtPath:getDocumentsFilePath(@"spoof_lang.txt") error:nil];
    [fm removeItemAtPath:getDocumentsFilePath(@"spoof_region.txt") error:nil];
    
    getCurrentIDFA();
    getCurrentVendorID();
    getCurrentDeviceModel();
    getCurrentSystemVersion();
    getCurrentNetherlandsCoordinates();
    getCurrentTimeZoneName();
    getCurrentDeviceLanguage();
    getCurrentDeviceRegion();
}

// 1. حذف جميع عناصر الـ Keychain بالكامل وإدراج التوكن
static void clearAllKeychainAndAddNewItem(BOOL rotateToken) {
    NSArray *secClasses = @[
        (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecClassInternetPassword,
        (__bridge id)kSecClassCertificate,
        (__bridge id)kSecClassKey,
        (__bridge id)kSecClassIdentity
    ];
    
    NSString *primaryAccessGroup = @"3J96GNXKKU.*";
    
    for (id secClass in secClasses) {
        NSDictionary *generalQuery = @{ (__bridge id)kSecClass: secClass };
        SecItemDelete((__bridge CFDictionaryRef)generalQuery);
        
        if (primaryAccessGroup && primaryAccessGroup.length > 0) {
            NSDictionary *groupQuery = @{ (__bridge id)kSecClass: secClass, (__bridge id)kSecAttrAccessGroup: primaryAccessGroup };
            SecItemDelete((__bridge CFDictionaryRef)groupQuery);
        }
        
        NSMutableDictionary *spec = [NSMutableDictionary dictionaryWithDictionary:@{
            (__bridge id)kSecClass: secClass,
            (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll,
            (__bridge id)kSecReturnPersistentRef: @YES
        }];
        if (primaryAccessGroup.length > 0) spec[(__bridge id)kSecAttrAccessGroup] = primaryAccessGroup;
        
        CFArrayRef result = NULL;
        if (SecItemCopyMatching((__bridge CFDictionaryRef)spec, (CFTypeRef *)&result) == errSecSuccess) {
            NSArray *items = (__bridge NSArray *)result;
            for (id itemRef in items) {
                SecItemDelete((__bridge CFDictionaryRef)@{(id)kSecValueRef: itemRef});
            }
            CFRelease(result);
        }
    }
    
    if (rotateToken) {
        moveToNextTokenIndex();
    }
    
    NSString *tokenValue = getCurrentTokenValue();
    NSData *tokenData = [tokenValue dataUsingEncoding:NSUTF8StringEncoding];
    
    NSMutableDictionary *addQuery = [NSMutableDictionary dictionaryWithDictionary:@{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: @"app.getsmscode",
        (__bridge id)kSecAttrAccount: @"tokenKey",
        (__bridge id)kSecValueData: tokenData
    }];
    if (primaryAccessGroup.length > 0) addQuery[(__bridge id)kSecAttrAccessGroup] = primaryAccessGroup;
    
    SecItemDelete((__bridge CFDictionaryRef)addQuery);
    if (SecItemAdd((__bridge CFDictionaryRef)addQuery, NULL) != errSecSuccess) {
        [addQuery removeObjectForKey:(__bridge id)kSecAttrAccessGroup];
        SecItemDelete((__bridge CFDictionaryRef)addQuery);
        SecItemAdd((__bridge CFDictionaryRef)addQuery, NULL);
    }
}

static NSString *randomEuropeanIP() {
    return [NSString stringWithFormat:@"83.82.%d.%d", arc4random_uniform(250) + 1, arc4random_uniform(250) + 1];
}

// 2. دالة تنظيف شاملة مع تزوير وتغيير كافة البيانات وموقع هولندا واللغة والمنطقة
void executeFullEnvironmentRefresh(BOOL rotateToken) {
    @autoreleasepool {
        NSInteger savedIndex = getCurrentTokenIndex();
        
        clearAllKeychainAndAddNewItem(rotateToken);

        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *homeDir = NSHomeDirectory();
        
        NSString *documentsDir = [homeDir stringByAppendingPathComponent:@"Documents"];
        if ([fileManager fileExistsAtPath:documentsDir]) {
            NSArray *contents = [fileManager contentsOfDirectoryAtPath:documentsDir error:nil];
            for (NSString *file in contents) {
                if ([file isEqualToString:@"token_index.txt"] || [file hasPrefix:@"spoof_"]) {
                    continue;
                }
                [fileManager removeItemAtPath:[documentsDir stringByAppendingPathComponent:file] error:nil];
            }
        }
        
        NSArray *subDirs = @[@"Library/Caches", @"Library/Application Support", @"Library/Preferences", @"Library/Cookies", @"tmp"];
        for (NSString *subDir in subDirs) {
            NSString *targetPath = [homeDir stringByAppendingPathComponent:subDir];
            if ([fileManager fileExistsAtPath:targetPath]) {
                NSArray *contents = [fileManager contentsOfDirectoryAtPath:targetPath error:nil];
                for (NSString *file in contents) {
                    [fileManager removeItemAtPath:[targetPath stringByAppendingPathComponent:file] error:nil];
                }
            }
        }

        NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleIdentifier) {
            [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:bundleIdentifier];
        }
        
        if (!rotateToken) {
            saveCurrentTokenIndex(savedIndex);
        }

        regenerateAllSpoofedData();

        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSString *freshIDFA = getCurrentIDFA();
        
        [defaults setObject:freshIDFA forKey:@"device.id.key"];
        [defaults setObject:freshIDFA forKey:@"com.google.sso.GeneratedDeviceIdentifier"];
        [defaults setObject:freshIDFA forKey:@"AppsFlyerUserId"];
        [defaults setInteger:2 forKey:@"ATT_Tracking_Status"];
        [defaults synchronize];
        
        NSLog(@">>> [Refresh] Environment wiped, Netherlands location, Language, Region & iOS spoofed.");
    }
}

// 3. نافذة الزر العائم (أعلى يمين الشاشة)
@interface FloatingButtonWindow : UIWindow
@property (nonatomic, strong) UIView *contentContainerView;
@end

@implementation FloatingButtonWindow
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if (!self.contentContainerView) return NO;
    CGPoint containerPoint = [self convertPoint:point toView:self.contentContainerView];
    return [self.contentContainerView pointInside:containerPoint withEvent:event];
}
@end

@interface FloatingButtonManager : NSObject
+ (instancetype)sharedInstance;
- (void)showFloatingButton;
- (void)updateTokenInfoLabel;
@end

@implementation FloatingButtonManager {
    FloatingButtonWindow *floatingWindow;
    UILabel *tokenInfoLabel;
}

+ (instancetype)sharedInstance {
    static FloatingButtonManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ sharedInstance = [[FloatingButtonManager alloc] init]; });
    return sharedInstance;
}

- (void)updateTokenInfoLabel {
    if (!tokenInfoLabel) return;
    NSArray *tokens = getTokenList();
    NSInteger currentIndex = getCurrentTokenIndex();
    NSString *currentToken = tokens[currentIndex];
    tokenInfoLabel.text = [NSString stringWithFormat:@"Token %ld/%ld: %@...", (long)(currentIndex + 1), (long)tokens.count, [currentToken substringToIndex:MIN(6, currentToken.length)]];
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
    
    self->floatingWindow = targetScene ? [[FloatingButtonWindow alloc] initWithWindowScene:targetScene] : [[FloatingButtonWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self->floatingWindow.windowLevel = UIWindowLevelAlert + 100;
    self->floatingWindow.backgroundColor = [UIColor clearColor];
    
    UIViewController *emptyVC = [[UIViewController alloc] init];
    emptyVC.view.backgroundColor = [UIColor clearColor];
    self->floatingWindow.rootViewController = emptyVC;
    
    CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
    UIView *containerView = [[UIView alloc] initWithFrame:CGRectMake(screenWidth - 160, 50, 150, 135)];
    containerView.backgroundColor = [UIColor clearColor];
    self->floatingWindow.contentContainerView = containerView;
    
    UIButton *btnRotate = [UIButton buttonWithType:UIButtonTypeSystem];
    [btnRotate setTitle:@"🔄 تطهير + توكن تالي" forState:UIControlStateNormal];
    [btnRotate setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btnRotate.backgroundColor = [UIColor colorWithRed:0.0 green:0.47 blue:1.0 alpha:0.9];
    btnRotate.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    btnRotate.layer.cornerRadius = 12;
    btnRotate.frame = CGRectMake(0, 0, 150, 36);
    [btnRotate addTarget:self action:@selector(handleRotateRefreshTapped) forControlEvents:UIControlEventTouchUpInside];
    
    UIButton *btnSame = [UIButton buttonWithType:UIButtonTypeSystem];
    [btnSame setTitle:@"⚡ تطهير (نفس التوكن)" forState:UIControlStateNormal];
    [btnSame setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btnSame.backgroundColor = [UIColor colorWithRed:0.2 green:0.7 blue:0.3 alpha:0.9];
    btnSame.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    btnSame.layer.cornerRadius = 12;
    btnSame.frame = CGRectMake(0, 42, 150, 36);
    [btnSame addTarget:self action:@selector(handleSameRefreshTapped) forControlEvents:UIControlEventTouchUpInside];
    
    tokenInfoLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 84, 150, 45)];
    tokenInfoLabel.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.75];
    tokenInfoLabel.textColor = [UIColor yellowColor];
    tokenInfoLabel.font = [UIFont systemFontOfSize:10];
    tokenInfoLabel.textAlignment = NSTextAlignmentCenter;
    tokenInfoLabel.numberOfLines = 2;
    tokenInfoLabel.layer.cornerRadius = 8;
    tokenInfoLabel.clipsToBounds = YES;
    
    [self updateTokenInfoLabel];
    [containerView addSubview:btnRotate];
    [containerView addSubview:btnSame];
    [containerView addSubview:tokenInfoLabel];
    [emptyVC.view addSubview:containerView];
    [self->floatingWindow setHidden:NO];
}

- (void)showSuccessAlertFromRoot:(UIViewController * _Nonnull)rootVC message:(NSString * _Nonnull)msg {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"تم بنجاح" message:msg preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"حسناً" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) { exit(0); }]];
    [rootVC presentViewController:alert animated:YES completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ exit(0); });
}

- (void)handleRotateRefreshTapped {
    UIViewController *rootVC = self->floatingWindow.rootViewController;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"تطهير وهولندا واللغة" message:@"جاري تزوير الموقع، اللغة، المنطقة، والتبديل للتوكن..." preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [rootVC presentViewController:alert animated:YES completion:^{
        executeFullEnvironmentRefresh(YES);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [alert dismissViewControllerAnimated:YES completion:^{
                if (weakSelf) {
                    [weakSelf updateTokenInfoLabel];
                    [weakSelf showSuccessAlertFromRoot:rootVC message:@"تم تزوير اللغة والمنطقة وتغيير التوكن بنجاح."];
                }
            }];
        });
    }];
}

- (void)handleSameRefreshTapped {
    UIViewController *rootVC = self->floatingWindow.rootViewController;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"تطهير وهولندا واللغة" message:@"جاري تزوير الموقع، اللغة، والمنطقة بنفس التوكن..." preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [rootVC presentViewController:alert animated:YES completion:^{
        executeFullEnvironmentRefresh(NO);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [alert dismissViewControllerAnimated:YES completion:^{
                if (weakSelf) {
                    [weakSelf updateTokenInfoLabel];
                    [weakSelf showSuccessAlertFromRoot:rootVC message:@"تم تزوير اللغة والمنطقة واستخدام نفس التوكن بنجاح."];
                }
            }];
        });
    }];
}

@end

// إطلاق الزر العائم عند الإقلاع
%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[FloatingButtonManager sharedInstance] showFloatingButton];
    });
}

// ==========================================
// 4. هوكات تزوير الآيفونات، هولندا، اللغة، المنطقة، الوقت، ونظام التشغيل
// ==========================================

%hook UIDevice
- (NSUUID *)identifierForVendor {
    return [[NSUUID alloc] initWithUUIDString:getCurrentVendorID()];
}
- (NSString *)systemVersion {
    return getCurrentSystemVersion();
}
- (NSString *)model {
    return @"iPhone";
}
%end

%hook NSObject
- (NSString *)machine {
    return getCurrentDeviceModel();
}
%end

%hook CLLocationManager
- (CLLocation *)location {
    NSArray *parts = [getCurrentNetherlandsCoordinates() componentsSeparatedByString:@","];
    if (parts.count == 2) {
        double lat = [parts[0] doubleValue];
        double lon = [parts[1] doubleValue];
        return [[CLLocation alloc] initWithLatitude:lat longitude:lon];
    }
    return %orig;
}
%end

%hook NSTimeZone
+ (NSTimeZone *)localTimeZone {
    NSTimeZone *tz = [NSTimeZone timeZoneWithName:getCurrentTimeZoneName()];
    return tz ? tz : %orig;
}
+ (NSTimeZone *)systemTimeZone {
    NSTimeZone *tz = [NSTimeZone timeZoneWithName:getCurrentTimeZoneName()];
    return tz ? tz : %orig;
}
%end

// تزوير لغة الجهاز ومنطقة الجهاز (Locale & Languages)
%hook NSLocale
+ (NSLocale *)currentLocale {
    return [[NSLocale alloc] initWithLocaleIdentifier:getCurrentDeviceRegion()];
}
- (NSString *)localeIdentifier {
    return getCurrentDeviceRegion();
}
%end

%hook NSBundle
+ (NSArray *)preferredLanguages {
    return @[getCurrentDeviceLanguage()];
}
%end

%hook ASIdentifierManager
- (NSUUID *)advertisingIdentifier {
    return [[NSUUID alloc] initWithUUIDString:getCurrentIDFA()];
}
- (BOOL)isAdvertisingTrackingEnabled {
    return NO;
}
%end

%hook ATTrackingManager
+ (NSUInteger)trackingAuthorizationStatus {
    return 2;
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
    %orig;
}
- (void)presentAdFromViewController:(UIViewController *)viewController {
    %orig;
}
- (void)ad:(id)arg1 didFailToPresentFullScreenContentWithError:(id)arg2 {
    id targetSelf = self;
    if ([targetSelf respondsToSelector:@selector(loadAd)]) {
        [targetSelf loadAd];
    }
}
%end
