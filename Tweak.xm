#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AdSupport/AdSupport.h>
#import <AppTrackingTransparency/AppTrackingTransparency.h>
#import <Security/Security.h>
#import <CoreLocation/CoreLocation.h>
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

static NSString * const kStoredResidentialIPKey   = @"com.dynamic.refresh.residential.ip";
static NSString * const kStoredUserAgentKey       = @"com.dynamic.refresh.user.agent";
static NSString * const kStoredAtlantaLatitudeKey = @"com.dynamic.refresh.atlanta.lat";
static NSString * const kStoredAtlantaLongitudeKey= @"com.dynamic.refresh.atlanta.lon";

// نطاقات T-Mobile السكنية الأمريكية الحقيقية
static NSArray *getTMobileIPPools() {
    return @[
        @{@"prefix": @"172.56.", @"isp": @"T-Mobile"},
        @{@"prefix": @"172.58.", @"isp": @"T-Mobile"},
        @{@"prefix": @"172.59.", @"isp": @"T-Mobile"},
        @{@"prefix": @"174.192.", @"isp": @"T-Mobile"},
        @{@"prefix": @"174.200.", @"isp": @"T-Mobile"},
        @{@"prefix": @"174.250.", @"isp": @"T-Mobile"}
    ];
}

static NSArray *getTrustedUserAgents() {
    return @[
        @"Mozilla/5.0 (iPhone; CPU iPhone OS 17_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
        @"Mozilla/5.0 (iPhone; CPU iPhone OS 17_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
        @"Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
        @"Mozilla/5.0 (iPhone; CPU iPhone OS 17_2_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Mobile/15E148 Safari/604.1",
        @"Mozilla/5.0 (iPhone; CPU iPhone OS 17_5_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
    ];
}

static NSString *getCurrentSessionIP() {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *ip = [defaults stringForKey:kStoredResidentialIPKey];
    if (!ip || [ip length] == 0) {
        NSArray *pools = getTMobileIPPools();
        NSDictionary *selectedPool = pools[arc4random_uniform((uint32_t)pools.count)];
        NSString *prefix = selectedPool[@"prefix"];
        ip = [NSString stringWithFormat:@"%@%d.%d", prefix, arc4random_uniform(250) + 1, arc4random_uniform(250) + 1];
        [defaults setObject:ip forKey:kStoredResidentialIPKey];
        [defaults synchronize];
    }
    return ip;
}

static NSString *getCurrentSessionUserAgent() {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *ua = [defaults stringForKey:kStoredUserAgentKey];
    if (!ua || [ua length] == 0) {
        NSArray *agents = getTrustedUserAgents();
        ua = agents[arc4random_uniform((uint32_t)agents.count)];
        [defaults setObject:ua forKey:kStoredUserAgentKey];
        [defaults synchronize];
    }
    return ua;
}

// توليد إحداثيات جديدة ومختلفة في أتلانتا مع كل عملية تطهير
static CLLocationCoordinate2D getAtlantaCoordinate() {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    double lat = [defaults doubleForKey:kStoredAtlantaLatitudeKey];
    double lon = [defaults doubleForKey:kStoredAtlantaLongitudeKey];
    
    if (lat == 0.0 || lon == 0.0) {
        lat = 33.7485 + ((double)(arc4random_uniform(415)) / 10000.0);
        lon = -84.4200 + ((double)(arc4random_uniform(320)) / 10000.0);
        
        [defaults setDouble:lat forKey:kStoredAtlantaLatitudeKey];
        [defaults setDouble:lon forKey:kStoredAtlantaLongitudeKey];
        [defaults synchronize];
    }
    return CLLocationCoordinate2DMake(lat, lon);
}

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
        NSDictionary *generalQuery = @{ (__bridge id)kSecClass: secClass };
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
                NSDictionary *refQuery = @{ (__bridge id)kSecValueRef: itemRef };
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
    
    if (addStatus != errSecSuccess) {
        [addQuery removeObjectForKey:(__bridge id)kSecAttrAccessGroup];
        SecItemDelete((__bridge CFDictionaryRef)addQuery);
        SecItemAdd((__bridge CFDictionaryRef)addQuery, NULL);
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

// دالة التطهير المحدثة لحذف كل ما يتعلق بـ NSUserDefaults وتوليد هوية جديدة تماماً
void executeFullEnvironmentRefresh() {
    @autoreleasepool {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        
        // 1. مسح المفاتيح السابقة تماماً لضمان عدم ثباتها
        [defaults removeObjectForKey:kStoredResidentialIPKey];
        [defaults removeObjectForKey:kStoredUserAgentKey];
        [defaults removeObjectForKey:kStoredAtlantaLatitudeKey];
        [defaults removeObjectForKey:kStoredAtlantaLongitudeKey];
        
        [defaults removeObjectForKey:@"device.id.key"];
        [defaults removeObjectForKey:@"com.google.sso.GeneratedDeviceIdentifier"];
        [defaults removeObjectForKey:@"AppsFlyerUserId"];
        [defaults removeObjectForKey:@"com.firebase.installations.app_id_to_fiid_enforcement"];
        
        NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleIdentifier) {
            [defaults removePersistentDomainForName:bundleIdentifier];
        }
        
        [defaults synchronize];

        // 2. تطهير الـ Keychain
        clearAllKeychainAndAddNewItem();

        // 3. مسح الملفات والمجلدات من الجذور
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
        
        NSString *groupDirBase = [[[homeDir stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"Group Containers"];
        if ([fileManager fileExistsAtPath:groupDirBase]) {
            NSArray *groupFolders = [fileManager contentsOfDirectoryAtPath:groupDirBase error:nil];
            for (NSString *groupFolder in groupFolders) {
                NSString *groupPath = [groupDirBase stringByAppendingPathComponent:groupFolder];
                [fileManager removeItemAtPath:groupPath error:nil];
            }
        }

        // 4. توليد البيانات الجديدة وزرعها في NSUserDefaults
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
        
        // إجبار التوليد الفوري لهوية جديدة (T-Mobile IP + User-Agent + إحداثيات أتلانتا جديدة)
        (void)getCurrentSessionIP();
        (void)getCurrentSessionUserAgent();
        (void)getAtlantaCoordinate();
        
        [defaults synchronize];
        
        NSLog(@">>> [Dynamic-Refresh] WIPE COMPLETE & FRESH NSUSERDEFAULTS IDENTITY GENERATED.");
    }
}

// واجهة الزر العائم
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

- (void)showSuccessAlertFromRoot:(UIViewController *)rootVC {
    UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"تم بنجاح" 
                                                                           message:@"تم مسح التخزين بالكامل وتوليد هوية T-Mobile وموقع جديد في أتلانتا بنجاح." 
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
                                                               message:@"جاري مسح بيانات NSUserDefaults وتوليد آبيات جديدة..." 
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

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[FloatingButtonManager sharedInstance] showFloatingButton];
    });
}

// الهوكات الأساسية
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

// هوكات الموقع الجغرافي لأتلانتا
%hook CLLocation
- (CLLocationCoordinate2D)coordinate {
    return getAtlantaCoordinate();
}
%end

%hook CLLocationManager
- (CLLocation *)location {
    CLLocationCoordinate2D coord = getAtlantaCoordinate();
    return [[CLLocation alloc] initWithLatitude:coord.latitude longitude:coord.longitude];
}
%end

// دالة الحقن المضمونة 100%
static void injectTMobileAndUA(NSMutableURLRequest *request) {
    if (![request isKindOfClass:[NSMutableURLRequest class]]) return;
    
    NSString *currentIP = getCurrentSessionIP();
    NSString *currentUA = getCurrentSessionUserAgent();
    
    [request setValue:currentIP forHTTPHeaderField:@"X-Forwarded-For"];
    [request setValue:currentIP forHTTPHeaderField:@"Client-IP"];
    [request setValue:currentIP forHTTPHeaderField:@"True-Client-IP"];
    [request setValue:currentIP forHTTPHeaderField:@"X-Client-IP"];
    [request setValue:currentIP forHTTPHeaderField:@"CF-Connecting-IP"];
    [request setValue:currentUA forHTTPHeaderField:@"User-Agent"];
}

%hook NSMutableURLRequest
- (instancetype)initWithURL:(NSURL *)URL {
    NSMutableURLRequest *req = %orig;
    injectTMobileAndUA(req);
    return req;
}

- (instancetype)initWithURL:(NSURL *)URL cachePolicy:(NSURLRequestCachePolicy)cachePolicy timeoutInterval:(NSTimeInterval)timeoutInterval {
    NSMutableURLRequest *req = %orig;
    injectTMobileAndUA(req);
    return req;
}

- (void)setValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
    NSString *upperField = [field uppercaseString];
    if ([upperField isEqualToString:@"X-FORWARDED-FOR"] || 
        [upperField isEqualToString:@"CLIENT-IP"] || 
        [upperField isEqualToString:@"TRUE-CLIENT-IP"] || 
        [upperField isEqualToString:@"X-CLIENT-IP"] ||
        [upperField isEqualToString:@"CF-CONNECTING-IP"]) {
        value = getCurrentSessionIP();
    } else if ([upperField isEqualToString:@"USER-AGENT"]) {
        value = getCurrentSessionUserAgent();
    }
    %orig(value, field);
}

- (void)setAllHTTPHeaderFields:(NSDictionary<NSString *,NSString *> *)headers {
    NSMutableDictionary *mutableHeaders = [headers mutableCopy];
    if (!mutableHeaders) {
        mutableHeaders = [NSMutableDictionary dictionary];
    }
    
    NSString *currentIP = getCurrentSessionIP();
    NSString *currentUA = getCurrentSessionUserAgent();
    
    mutableHeaders[@"X-Forwarded-For"] = currentIP;
    mutableHeaders[@"Client-IP"] = currentIP;
    mutableHeaders[@"True-Client-IP"] = currentIP;
    mutableHeaders[@"User-Agent"] = currentUA;
    
    %orig(mutableHeaders);
}
%end

%hook NSURLRequest
- (instancetype)initWithURL:(NSURL *)URL {
    id req = %orig;
    if ([req isKindOfClass:[NSMutableURLRequest class]]) {
        injectTMobileAndUA((NSMutableURLRequest *)req);
    }
    return req;
}
%end

%hook NSURLSessionConfiguration
- (void)setHTTPAdditionalHeaders:(NSDictionary *)headers {
    NSMutableDictionary *mutableHeaders = headers ? [headers mutableCopy] : [NSMutableDictionary dictionary];
    NSString *currentIP = getCurrentSessionIP();
    NSString *currentUA = getCurrentSessionUserAgent();
    
    mutableHeaders[@"X-Forwarded-For"] = currentIP;
    mutableHeaders[@"Client-IP"] = currentIP;
    mutableHeaders[@"True-Client-IP"] = currentIP;
    mutableHeaders[@"User-Agent"] = currentUA;
    
    %orig(mutableHeaders);
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
