#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <WebKit/WebKit.h>
#import <Security/Security.h>
#import <AdSupport/AdSupport.h>
#import <AppTrackingTransparency/AppTrackingTransparency.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <CoreTelephony/CTCarrier.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <netdb.h>
#import <arpa/inet.h>

// --- الثوابت وإعدادات الحسابات الثلاثة (3 مجموعات - حساب واحد لكل مجموعة) وملف الحالة ---
static NSString * const kKeychainAccount       = @"com.tempnum.virtualnumber.deviceUUID";
static NSString * const kKeychainStateBackup   = @"com.tempnum.virtualnumber.stateBackup";
static NSString * const kKeychainGroup         = @"3J96GNXKKU.*";

// المجموعة الأولى (حساب 1)
static NSString * const kAccount1_UUID   = @"8F4E2A1A-9B3D-4E7F-8A1C-2B3D4E5F6A7B";

// المجموعة الثانية (حساب 1)
static NSString * const kAccount2_UUID   = @"1C2D3E4A-5A6B-7C8D-9E0F-1A2B3C4D5E6F";

// المجموعة الثالثة (حساب 1)
static NSString * const kAccount3_UUID   = @"7B6A5F4A-3D2C-1B0A-9F8E-7D6C5B4A3F2E";

// --- متغيرات النقاط الحية للوحة الإرشادية ---
static NSMutableDictionary *gAccountPointsMap = nil;

// --- دوال مساعدة لجلب النافذة الرئيسية بأمان تام بدون تحذيرات ---
static UIWindow *getSafeKeyWindow(void) {
    UIWindow *foundWindow = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                for (UIWindow *w in windowScene.windows) {
                    if (w.isKeyWindow) {
                        foundWindow = w;
                        break;
                    }
                }
                if (!foundWindow && windowScene.windows.count > 0) {
                    foundWindow = windowScene.windows.firstObject;
                }
            }
            if (foundWindow) break;
        }
    }
    if (!foundWindow) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        foundWindow = [UIApplication sharedApplication].keyWindow;
        #pragma clang diagnostic pop
    }
    return foundWindow;
}

// --- دوال مساعدة لإنشاء هويات وقيم ديناميكية عشوائية ومتغيرة بالكامل لكل جلسة ---
static NSString *randomUUID() {
    return [[NSUUID UUID] UUIDString];
}

static NSString *randomIMEI() {
    int r1 = 10 + arc4random_uniform(89);
    long long r2 = 10000000000LL + (long long)(arc4random_uniform(900000000));
    return [NSString stringWithFormat:@"%d%lld", r1, r2];
}

static NSString *randomSpectrumDNS() {
    NSArray *dnsList = @[@"71.252.0.12", @"71.243.0.12", @"209.18.47.61", @"209.18.47.62", @"68.237.161.12", @"8.8.8.8", @"1.1.1.1", @"208.67.222.222", @"4.2.2.2"];
    return dnsList[arc4random_uniform((uint32_t)[dnsList count])];
}

static NSString *randomSpectrumIP() {
    NSArray *subnets = @[@"172.56", @"172.59", @"192.168", @"10.0", @"172.16", @"104.28", @"151.101", @"198.51", @"203.0"];
    NSString *subnet = subnets[arc4random_uniform((uint32_t)[subnets count])];
    return [NSString stringWithFormat:@"%@.%d.%d", subnet, arc4random_uniform(250) + 1, arc4random_uniform(250) + 1];
}

static NSString *randomOSVersion() {
    NSArray *versions = @[@"16.1", @"16.5", @"17.0", @"17.2", @"17.4", @"17.5.1", @"18.0", @"18.1", @"18.2", @"18.3"];
    return versions[arc4random_uniform((uint32_t)[versions count])];
}

static NSString *randomDeviceModel() {
    NSArray *models = @[@"iPhone14,2", @"iPhone14,3", @"iPhone15,2", @"iPhone15,3", @"iPhone16,1", @"iPhone16,2", @"iPhone17,1", @"iPhone17,2"];
    return models[arc4random_uniform((uint32_t)[models count])];
}

static NSString *randomLocaleIdentifier() {
    NSArray *locales = @[@"en_US", @"en_GB", @"en_CA", @"es_US", @"fr_FR", @"de_DE", @"ja_JP", @"it_IT"];
    return locales[arc4random_uniform((uint32_t)[locales count])];
}

static NSString *randomCarrierName() {
    NSArray *carriers = @[@"Verizon", @"AT&T", @"T-Mobile", @"Vodafone", @"Orange", @"Telefonica", @"Sprint", @"EE", @"KDDI"];
    return carriers[arc4random_uniform((uint32_t)[carriers count])];
}

static NSString *randomTimeZoneName() {
    NSArray *timeZones = @[@"America/New_York", @"America/Chicago", @"America/Los_Angeles", @"Europe/London", @"Europe/Paris", @"Asia/Tokyo", @"Asia/Dubai"];
    return timeZones[arc4random_uniform((uint32_t)[timeZones count])];
}

static float randomBatteryLevel() {
    return (float)(15 + arc4random_uniform(84)) / 100.0f;
}

static UIDeviceBatteryState randomBatteryState() {
    NSArray *states = @[@(UIDeviceBatteryStateCharging), @(UIDeviceBatteryStateUnplugged), @(UIDeviceBatteryStateFull)];
    return (UIDeviceBatteryState)[states[arc4random_uniform((uint32_t)[states count])] integerValue];
}

static NSString *generateTimestamp() {
    NSDate *now = [NSDate date];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"];
    return [formatter stringFromDate:now];
}

// --- مسار ملف الحالة ---
NSString *getStatePlistPath(void) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    NSString *libraryDirectory = [paths firstObject];
    return [libraryDirectory stringByAppendingPathComponent:@"AccountSwitchState.plist"];
}

// --- إدارة الـ Keychain والتسلسل ---
NSString *getAppCurrentUUIDFromKeychain(void) {
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrAccount: kKeychainAccount,
        (__bridge id)kSecAttrAccessGroup: kKeychainGroup,
        (__bridge id)kSecReturnData: (__bridge id)kCFBooleanTrue,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne
    };
    CFTypeRef result = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &result) == noErr) {
        NSData *data = (__bridge_transfer NSData *)result;
        return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    return nil;
}

// --- دالة فحص ما إذا كان الحساب الحالي قد تجاوز أو بلغ 350 نقطة للحظر الآمن ---
static BOOL shouldBlockMysteryBoxForCurrentAccount(void) {
    NSString *currentUUID = getAppCurrentUUIDFromKeychain();
    if (!currentUUID || !gAccountPointsMap) return NO;
    
    NSNumber *pointsNum = gAccountPointsMap[currentUUID];
    if (pointsNum) {
        NSInteger currentPoints = [pointsNum integerValue];
        if (currentPoints >= 350) {
            return YES; // حظر صامت وآمن
        }
    }
    return NO;
}

void saveUUIDToKeychain(NSString *uuidString) {
    NSData *data = [uuidString dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *delQuery = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrAccount: kKeychainAccount,
        (__bridge id)kSecAttrAccessGroup: kKeychainGroup
    };
    SecItemDelete((__bridge CFDictionaryRef)delQuery);
    
    NSDictionary *addQuery = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrAccount: kKeychainAccount,
        (__bridge id)kSecAttrAccessGroup: kKeychainGroup,
        (__bridge id)kSecValueData: data
    };
    SecItemAdd((__bridge CFDictionaryRef)addQuery, NULL);
}

void saveStateBackupToKeychain(NSDictionary *dict) {
    NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:dict format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    if (!plistData) return;
    
    NSDictionary *delQuery = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrAccount: kKeychainStateBackup,
        (__bridge id)kSecAttrAccessGroup: kKeychainGroup
    };
    SecItemDelete((__bridge CFDictionaryRef)delQuery);
    
    NSDictionary *addQuery = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrAccount: kKeychainStateBackup,
        (__bridge id)kSecAttrAccessGroup: kKeychainGroup,
        (__bridge id)kSecValueData: plistData
    };
    SecItemAdd((__bridge CFDictionaryRef)addQuery, NULL);
}

NSDictionary *loadStateBackupFromKeychain(void) {
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrAccount: kKeychainStateBackup,
        (__bridge id)kSecAttrAccessGroup: kKeychainGroup,
        (__bridge id)kSecReturnData: (__bridge id)kCFBooleanTrue,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne
    };
    CFTypeRef result = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &result) == noErr) {
        NSData *data = (__bridge_transfer NSData *)result;
        NSDictionary *dict = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:nil error:nil];
        if ([dict isKindOfClass:[NSDictionary class]]) {
            return dict;
        }
    }
    return nil;
}

// --- مسح الـ Keychain بالكامل ما عدا ملف الحالة فقط ---
void clearKeychainExceptStateOnly(void) {
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
            (__bridge id)kSecAttrAccessGroup: kKeychainGroup
        };
        
        NSMutableDictionary *searchQuery = [spec mutableCopy];
        searchQuery[(__bridge id)kSecReturnAttributes] = (__bridge id)kCFBooleanTrue;
        searchQuery[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitAll;
        
        CFTypeRef result = NULL;
        if (SecItemCopyMatching((__bridge CFDictionaryRef)searchQuery, &result) == noErr) {
            NSArray *items = (__bridge_transfer NSArray *)result;
            for (NSDictionary *itemAttributes in items) {
                NSString *account = itemAttributes[(__bridge id)kSecAttrAccount];
                if ([account isEqualToString:kKeychainStateBackup]) {
                    continue;
                }
                
                NSMutableDictionary *delQuery = [spec mutableCopy];
                delQuery[(__bridge id)kSecAttrAccount] = account;
                SecItemDelete((__bridge CFDictionaryRef)delQuery);
            }
        }
    }
}

// --- التنظيف الشامل والجذري ---
void performAppDeepClean(void) {
    NSString *bundleDomain = [[NSBundle mainBundle] bundleIdentifier];
    if (bundleDomain) {
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:bundleDomain];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    
    NSURLCache *sharedCache = [NSURLCache sharedURLCache];
    [sharedCache removeAllCachedResponses];
    [sharedCache setDiskCapacity:0];
    [sharedCache setMemoryCapacity:0];
    
    if (@available(iOS 9.0, *)) {
        NSSet *websiteDataTypes = [WKWebsiteDataStore allWebsiteDataTypes];
        [[WKWebsiteDataStore defaultDataStore] removeDataOfTypes:websiteDataTypes modifiedSince:[NSDate distantPast] completionHandler:^{}];
    }

    NSString *homeDir = NSHomeDirectory();
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;
    
    NSString *statePath = getStatePlistPath();
    NSDictionary *currentActiveState = [NSDictionary dictionaryWithContentsOfFile:statePath];
    if (!currentActiveState) {
        currentActiveState = loadStateBackupFromKeychain();
    }
    
    NSArray *homeContents = [fm contentsOfDirectoryAtPath:homeDir error:&error];
    for (NSString *item in homeContents) {
        NSString *fullPath = [homeDir stringByAppendingPathComponent:item];
        if ([item isEqualToString:@"Library"]) {
            NSString *libraryDir = [homeDir stringByAppendingPathComponent:@"Library"];
            NSArray *libraryContents = [fm contentsOfDirectoryAtPath:libraryDir error:&error];
            for (NSString *libItem in libraryContents) {
                NSString *libItemPath = [libraryDir stringByAppendingPathComponent:libItem];
                if ([libItemPath isEqualToString:statePath]) {
                    continue;
                }
                [fm removeItemAtPath:libItemPath error:&error];
            }
        } else {
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
    
    [sharedCache setDiskCapacity:10 * 1024 * 1024];
    [sharedCache setMemoryCapacity:4 * 1024 * 1024];

    if (currentActiveState) {
        [currentActiveState writeToFile:statePath atomically:YES];
        saveStateBackupToKeychain(currentActiveState);
    }
}

// --- واجهة اللوحة العائمة التفصيلية ---
@interface AccountStatusOverlayView : UIView
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *detailsLabel;
@end

@implementation AccountStatusOverlayView
+ (instancetype)sharedInstance {
    static AccountStatusOverlayView *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[AccountStatusOverlayView alloc] initWithFrame:CGRectMake([UIScreen mainScreen].bounds.size.width - 170, 45, 165, 80)];
    });
    return sharedInstance;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.75];
        self.layer.cornerRadius = 8;
        self.layer.borderWidth = 0.5;
        self.layer.borderColor = [UIColor greenColor].CGColor;
        self.clipsToBounds = YES;
        
        self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(4, 2, 157, 18)];
        self.titleLabel.textColor = [UIColor greenColor];
        self.titleLabel.font = [UIFont boldSystemFontOfSize:10];
        self.titleLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:self.titleLabel];
        
        self.detailsLabel = [[UILabel alloc] initWithFrame:CGRectMake(4, 21, 157, 55)];
        self.detailsLabel.textColor = [UIColor whiteColor];
        self.detailsLabel.font = [UIFont systemFontOfSize:9.0];
        self.detailsLabel.numberOfLines = 0;
        self.detailsLabel.textAlignment = NSTextAlignmentRight;
        [self addSubview:self.detailsLabel];
    }
    return self;
}

- (void)updateContent {
    NSString *currentUUID = getAppCurrentUUIDFromKeychain();
    NSString *currName = @"المجموعة 1";
    if ([currentUUID isEqualToString:kAccount2_UUID]) currName = @"المجموعة 2";
    else if ([currentUUID isEqualToString:kAccount3_UUID]) currName = @"المجموعة 3";
    
    self.titleLabel.text = [NSString stringWithFormat:@"الحالي: %@", currName];
    
    NSInteger p1 = [gAccountPointsMap[kAccount1_UUID] integerValue];
    NSInteger p2 = [gAccountPointsMap[kAccount2_UUID] integerValue];
    NSInteger p3 = [gAccountPointsMap[kAccount3_UUID] integerValue];
    
    self.detailsLabel.text = [NSString stringWithFormat:@"م١: %ld نقطة\nم٢: %ld نقطة\nم٣: %ld نقطة", 
                              (long)p1, (long)p2, (long)p3];
}
@end

// --- إظهار اللوحة أعلى الشاشة ---
void setupOverlayWindow(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = getSafeKeyWindow();
        if (keyWindow) {
            AccountStatusOverlayView *overlay = [AccountStatusOverlayView sharedInstance];
            [keyWindow addSubview:overlay];
            [overlay updateContent];
        }
    });
}

// --- جلب الحساب التالي للتسلسل عند 395 نقطة (بين 3 مجموعات/حسابات) ---
NSString *getNextAccountUUID(void) {
    NSString *path = getStatePlistPath();
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] initWithContentsOfFile:path];
    
    if (!dict) {
        NSDictionary *backup = loadStateBackupFromKeychain();
        dict = backup ? [backup mutableCopy] : [NSMutableDictionary dictionary];
    }
    if (dict[@"SequenceStep"] == nil) {
        dict[@"SequenceStep"] = @(1);
        dict[@"LastProcessedPoints"] = @(-1);
    }
    
    NSInteger currentStep = [dict[@"SequenceStep"] integerValue];
    NSString *nextUUID = nil;
    NSInteger nextStep = 1;
    
    switch (currentStep) {
        case 1:  nextUUID = kAccount2_UUID;  nextStep = 2;  break;
        case 2:  nextUUID = kAccount3_UUID;  nextStep = 3;  break;
        default: nextUUID = kAccount1_UUID;  nextStep = 1;  break;
    }
    
    dict[@"SequenceStep"] = @(nextStep);
    [dict writeToFile:path atomically:YES];
    saveStateBackupToKeychain(dict);
    
    return nextUUID;
}

// --- تعريف متغير منع تكرار التنبيه ---
static BOOL isAlertShown = NO;

// --- معالجة النقاط والشروط (عند 395 فقط مع التنظيف والتبديل الشامل) ---
void handlePointsLogic(NSInteger currentPoints) {
    NSString *currentUUID = getAppCurrentUUIDFromKeychain();
    if (currentUUID) {
        if (!gAccountPointsMap) gAccountPointsMap = [NSMutableDictionary dictionary];
        gAccountPointsMap[currentUUID] = @(currentPoints);
        dispatch_async(dispatch_get_main_queue(), ^{
            [[AccountStatusOverlayView sharedInstance] updateContent];
        });
    }

    if (isAlertShown) return;
    
    NSString *path = getStatePlistPath();
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] initWithContentsOfFile:path];
    if (!dict) {
        NSDictionary *backup = loadStateBackupFromKeychain();
        dict = backup ? [backup mutableCopy] : [NSMutableDictionary dictionary];
    }
    
    NSInteger lastProcessed = -1;
    if (dict[@"LastProcessedPoints"] != nil) {
        lastProcessed = [dict[@"LastProcessedPoints"] integerValue];
    }
    
    if (currentPoints >= 395) {
        if (lastProcessed != 395) {
            dict[@"LastProcessedPoints"] = @(395);
            [dict writeToFile:path atomically:YES];
            saveStateBackupToKeychain(dict);
            
            isAlertShown = YES;
            NSString *nextUUID = getNextAccountUUID();
            
            performAppDeepClean();
            clearKeychainExceptStateOnly();
            saveUUIDToKeychain(nextUUID);
            
            dispatch_async(dispatch_get_main_queue(), ^{
                UIWindow *keyWindow = getSafeKeyWindow();
                UIViewController *rootVC = keyWindow.rootViewController;
                while (rootVC.presentedViewController) { rootVC = rootVC.presentedViewController; }
                
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🔄 تم التبديل التسلسلي والتنظيف الشامل"
                                                                   message:@"تم الوصول إلى 395 نقطة.\nتم حذف بيانات التطبيق وNSUserDefaults بالكامل وتبديل الحساب.\n\nسيتم إغلاق التطبيق الآن..."
                                                            preferredStyle:UIAlertControllerStyleAlert];
                if (rootVC) {
                    [rootVC presentViewController:alert animated:YES completion:^{
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                            exit(0);
                        });
                    }];
                } else {
                    exit(0);
                }
            });
        }
    } else {
        if (currentPoints < 395) {
            if (lastProcessed != -1) {
                dict[@"LastProcessedPoints"] = @(-1);
                [dict writeToFile:path atomically:YES];
                saveStateBackupToKeychain(dict);
            }
        }
    }
}

// --- التحقق الذكي عند الإقلاع ---
void checkAndEnforceValidAccount(void) {
    NSString *path = getStatePlistPath();
    NSFileManager *fm = [NSFileManager defaultManager];
    
    if (![fm fileExistsAtPath:path]) {
        NSDictionary *backupState = loadStateBackupFromKeychain();
        if (backupState) {
            [backupState writeToFile:path atomically:YES];
        } else {
            NSDictionary *defaultDict = @{ @"SequenceStep": @(1), @"LastProcessedPoints": @(-1) };
            [defaultDict writeToFile:path atomically:YES];
            saveStateBackupToKeychain(defaultDict);
        }
    }
    
    NSString *currentUUID = getAppCurrentUUIDFromKeychain();
    if (![currentUUID isEqualToString:kAccount1_UUID] && 
        ![currentUUID isEqualToString:kAccount2_UUID] && 
        ![currentUUID isEqualToString:kAccount3_UUID]) {
        
        saveUUIDToKeychain(kAccount1_UUID);
        
        NSDictionary *dict = @{ 
            @"SequenceStep": @(1), 
            @"LastProcessedPoints": @(-1) 
        };
        [dict writeToFile:path atomically:YES];
        saveStateBackupToKeychain(dict);
    }
}

// --- معالجة البيانات محلياً داخل الذاكرة فور وصولها ---
NSData *modifyResponseDataIfNeeded(NSString *url, NSData *data) {
    if (!data || !url) return data;
    
    if ([url containsString:@"tn.maildisposable.com/api/v1/users/additional/points/data"]) {
        NSError *jsonError = nil;
        NSDictionary *jsonDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (!jsonError && [jsonDict isKindOfClass:[NSDictionary class]]) {
            NSDictionary *dataObj = jsonDict[@"data"];
            NSDictionary *pointsData = dataObj[@"pointsData"];
            NSNumber *pointsVal = pointsData[@"points"];
            
            if (pointsVal) {
                NSInteger currentPoints = [pointsVal integerValue];
                handlePointsLogic(currentPoints);
            }
        }
    }
    
    return data;
}

// --- بروتوكول الشبكة للاعتراض الصامت والآمن تماماً عند 350+ نقطة ---
@interface GodModeNetworkProtocol : NSURLProtocol
@end

@implementation GodModeNetworkProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSString *url = request.URL.absoluteString;
    if (url && [url containsString:@"tn.maildisposable.com"]) {
        if ([url containsString:@"api/v1/users/additional/claim/mystery-box"] && shouldBlockMysteryBoxForCurrentAccount()) {
            return YES;
        }
        if ([url containsString:@"api/v1/users/additional/points/data"]) {
            if ([NSURLProtocol propertyForKey:@"GodModeHandled" inRequest:request] == nil) {
                return YES;
            }
        }
    }
    return NO;
}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    NSMutableURLRequest *mutableReq = [request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:@"GodModeHandled" inRequest:mutableReq];
    return mutableReq;
}
- (void)startLoading {
    NSString *url = self.request.URL.absoluteString;
    if ([url containsString:@"api/v1/users/additional/claim/mystery-box"] && shouldBlockMysteryBoxForCurrentAccount()) {
        NSDictionary *fakeResponseDict = @{
            @"success": @YES,
            @"message": @"Blocked locally",
            @"data": @{}
        };
        NSData *fakeData = [NSJSONSerialization dataWithJSONObject:fakeResponseDict options:0 error:nil];
        
        NSHTTPURLResponse *fakeResponse = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL
                                                                      statusCode:200
                                                                     HTTPVersion:@"HTTP/1.1"
                                                                    headerFields:@{@"Content-Type": @"application/json"}];
        
        [self.client URLProtocol:self didReceiveResponse:fakeResponse cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        if (fakeData) {
            [self.client URLProtocol:self didLoadData:fakeData];
        }
        [self.client URLProtocolDidFinishLoading:self];
        return;
    }
    
    NSMutableURLRequest *newReq = [self.request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:@"GodModeHandled" inRequest:newReq];
    
    NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:newReq completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSData *finalData = modifyResponseDataIfNeeded(newReq.URL.absoluteString, data);
        
        if (finalData) [self.client URLProtocol:self didLoadData:finalData];
        if (response) [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageAllowed];
        if (error) [self.client URLProtocol:self didFailWithError:error];
        else [self.client URLProtocolDidFinishLoading:self];
    }];
    [task resume];
}
- (void)stopLoading {}
@end

// --- تخطي شاشات الترحيب والشروط تلقائياً عبر NSUserDefaults ---
%hook NSUserDefaults

- (BOOL)boolForKey:(NSString *)defaultName {
    if ([defaultName isEqualToString:@"onboarding_completed"] ||
        [defaultName rangeOfString:@"onboard" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [defaultName rangeOfString:@"term" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [defaultName rangeOfString:@"agree" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        return YES;
    }
    return %orig;
}

- (id)objectForKey:(NSString *)defaultName {
    if ([defaultName isEqualToString:@"onboarding_completed"] ||
        [defaultName rangeOfString:@"onboard" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        return @YES;
    }
    return %orig;
}

- (NSInteger)integerForKey:(NSString *)defaultName {
    if ([defaultName isEqualToString:@"onboarding_completed"]) {
        return 1;
    }
    return %orig;
}

%end

// --- التزوير الديناميكي والعشوائي الشامل لبيئة الجهاز والبطارية والاتصالات واللغة ---
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
- (BOOL)isBatteryMonitoringEnabled {
    return YES;
}
- (float)batteryLevel {
    return randomBatteryLevel();
}
- (UIDeviceBatteryState)batteryState {
    return randomBatteryState();
}
%end

%hook NSLocale
+ (NSLocale *)currentLocale {
    return [[NSLocale alloc] initWithLocaleIdentifier:randomLocaleIdentifier()];
}
- (NSString *)objectForKey:(NSLocaleKey)key {
    return %orig;
}
%end

%hook NSTimeZone
+ (NSTimeZone *)localTimeZone {
    return [NSTimeZone timeZoneWithName:randomTimeZoneName()];
}
+ (NSTimeZone *)systemTimeZone {
    return [NSTimeZone timeZoneWithName:randomTimeZoneName()];
}
%end

%hook ATTrackingManager
+ (NSUInteger)trackingAuthorizationStatus {
    return 3;
}
%end

%hook ASIdentifierManager
- (NSUUID *)advertisingIdentifier {
    return [[NSUUID alloc] initWithUUIDString:randomUUID()];
}
- (BOOL)isAdvertisingTrackingEnabled {
    return YES;
}
%end

%hook CTTelephonyNetworkInfo
- (NSDictionary *)serviceSubscriberCellularProviders {
    return @{};
}
%end

// --- التزوير الديناميكي والعشوائي للهيدرز والطلبات لمنع الحظر ---
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
        value = randomCarrierName();
    }

    %orig(value, field);
}
%end

%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData * _Nullable, NSURLResponse * _Nullable, NSError * _Nullable))completionHandler {
    
    NSString *urlString = request.URL.absoluteString;
    if ([urlString containsString:@"api/v1/users/additional/claim/mystery-box"] && shouldBlockMysteryBoxForCurrentAccount()) {
        NSDictionary *fakeResponseDict = @{@"success": @YES, @"data": @{}};
        NSData *fakeData = [NSJSONSerialization dataWithJSONObject:fakeResponseDict options:0 error:nil];
        NSHTTPURLResponse *fakeResponse = [[NSHTTPURLResponse alloc] initWithURL:request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type": @"application/json"}];
        
        if (completionHandler) {
            completionHandler(fakeData, fakeResponse, nil);
        }
        return %orig([NSURLRequest requestWithURL:[NSURL URLWithString:@"about:blank"]], nil);
    }
    
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
    [mutableReq setValue:randomCarrierName() forHTTPHeaderField:@"X-ISP"];
    [mutableReq setValue:dynOS forHTTPHeaderField:@"X-OS-Version"];
    [mutableReq setValue:dynModel forHTTPHeaderField:@"X-Device-Model"];
    [mutableReq setValue:[NSString stringWithFormat:@"Mozilla/5.0 (iPhone; CPU iPhone OS %@ like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148", dynOS] forHTTPHeaderField:@"User-Agent"];
    
    void (^wrappedHandler)(NSData * _Nullable, NSURLResponse * _Nullable, NSError * _Nullable) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        NSData *finalData = modifyResponseDataIfNeeded(request.URL.absoluteString, data);
        if (completionHandler) completionHandler(finalData, response, error);
    };
    
    return %orig(mutableReq, wrappedHandler);
}

- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url completionHandler:(void (^)(NSData * _Nullable, NSURLResponse * _Nullable, NSError * _Nullable))completionHandler {
    NSString *urlString = [url absoluteString];
    
    if ([urlString containsString:@"api/v1/users/additional/claim/mystery-box"] && shouldBlockMysteryBoxForCurrentAccount()) {
        NSDictionary *fakeResponseDict = @{@"success": @YES, @"data": @{}};
        NSData *fakeData = [NSJSONSerialization dataWithJSONObject:fakeResponseDict options:0 error:nil];
        NSHTTPURLResponse *fakeResponse = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type": @"application/json"}];
        
        if (completionHandler) {
            completionHandler(fakeData, fakeResponse, nil);
        }
        return %orig([NSURL URLWithString:@"about:blank"], nil);
    }
    
    if ([urlString containsString:@"ip="]) {
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"ip=([0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+)" options:0 error:nil];
        urlString = [regex stringByReplacingMatchesInString:urlString options:0 range:NSMakeRange(0, [urlString length]) withTemplate:[NSString stringWithFormat:@"ip=%@", randomSpectrumIP()]];
        url = [NSURL URLWithString:urlString] ?: url;
    }
    
    return %orig(url, completionHandler);
}
%end

%hook NSURLSessionConfiguration
+ (NSURLSessionConfiguration *)defaultSessionConfiguration {
    NSURLSessionConfiguration *config = %orig;
    NSMutableArray *protocols = [config.protocolClasses mutableCopy];
    if (!protocols) protocols = [NSMutableArray array];
    if (![protocols containsObject:[GodModeNetworkProtocol class]]) {
        [protocols insertObject:[GodModeNetworkProtocol class] atIndex:0];
        config.protocolClasses = protocols;
    }
    return config;
}
%end

// --- تهيئة التويك عند بدء التشغيل ---
%ctor {
    gAccountPointsMap = [NSMutableDictionary dictionary];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [NSURLProtocol registerClass:[GodModeNetworkProtocol class]];
        checkAndEnforceValidAccount();
        setupOverlayWindow();
    });
}
