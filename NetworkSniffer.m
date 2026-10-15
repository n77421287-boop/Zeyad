#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <WebKit/WebKit.h>
#import <Security/Security.h>
#import <AdSupport/AdSupport.h>
#import <AppTrackingTransparency/AppTrackingTransparency.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <CoreTelephony/CTCarrier.h>

// --- الثوابت الأساسية ---
static NSString * const kKeychainAccount       = @"com.tempnum.virtualnumber.deviceUUID";
static NSString * const kKeychainStateBackup   = @"com.tempnum.virtualnumber.stateBackup";
static NSString * const kKeychainGroup         = @"3J96GNXKKU.*";

// قيم افتراضية أولية للحسابات الثلاثة
static NSString * const kDefaultAcc1_UUID = @"1A2B3C4D-5E5F-7A8B-9C0F-1E2F3A4B5C6D";
static NSString * const kDefaultAcc2_UUID = @"2B3C4E5E-6F75-8B9C-0D1E-2F3A4B5C6DFE";
static NSString * const kDefaultAcc3_UUID = @"3C4D5E6F-7A85-9C0D-1E2F-3A4B5C6D7F8F";

// --- دوال مساعدة لإنشاء هويات عشوائية ---
static NSString *randomUUID() {
    return [[NSUUID UUID] UUIDString];
}

static NSString *randomIMEI() {
    int r1 = 10 + arc4random_uniform(89);
    long long r2 = 10000000000LL + (long long)(arc4random_uniform(900000000));
    return [NSString stringWithFormat:@"%d%lld", r1, r2];
}

static NSString *randomOSVersion() {
    NSArray *versions = @[@"16.1", @"16.5", @"17.0", @"17.2", @"17.4", @"17.5.1", @"18.0", @"18.1", @"18.2", @"18.3"];
    return versions[arc4random_uniform((uint32_t)[versions count])];
}

static NSString *randomLocaleIdentifier() {
    NSArray *locales = @[@"en_US", @"en_GB", @"en_CA", @"es_US", @"fr_FR", @"de_DE", @"ja_JP", @"it_IT"];
    return locales[arc4random_uniform((uint32_t)[locales count])];
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

// --- مسار ملف الحالة ---
NSString *getStatePlistPath(void) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    NSString *libraryDirectory = [paths firstObject];
    return [libraryDirectory stringByAppendingPathComponent:@"AccountSwitchState.plist"];
}

// --- إدارة الـ Keychain للـ UUID الحالي للجهاز والنسخ الاحتياطي ---
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

// --- جلب وحفظ الـ UUIDs الثلاثة من الملف (AccountSwitchState.plist) ---
NSString *getCustomAccountUUID(NSString *key, NSString *fallback) {
    NSString *path = getStatePlistPath();
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
    if (dict && dict[key]) {
        NSString *val = dict[key];
        if (val.length > 0) return val;
    }
    return fallback;
}

void setCustomAccountUUID(NSString *key, NSString *uuid) {
    if (!uuid || uuid.length == 0) return;
    NSString *path = getStatePlistPath();
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] initWithContentsOfFile:path];
    if (!dict) {
        dict = [NSMutableDictionary dictionary];
    }
    dict[key] = uuid;
    [dict writeToFile:path atomically:YES];
    saveStateBackupToKeychain(dict);
}

// --- مسح الـ Keychain بالكامل ما عدا النسخة الاحتياطية لملف الحالة ---
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

// --- دالة تنفيذ عملية التبديل الشامل للحساب المحدد ---
void executeSwitchAndCleanToAccount(NSString *targetUUID) {
    performAppDeepClean();
    clearKeychainExceptStateOnly();
    saveUUIDToKeychain(targetUUID);
    exit(0);
}

// --- واجهة الزر العائم لإدارة الحسابات ---
@interface AccountManagerButtonView : UIView
@property (nonatomic, strong) UIButton *floatingButton;
@end

@implementation AccountManagerButtonView
+ (instancetype)sharedInstance {
    static AccountManagerButtonView *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[AccountManagerButtonView alloc] initWithFrame:CGRectMake(15, 100, 50, 50)];
    });
    return sharedInstance;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.floatingButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.floatingButton.frame = self.bounds;
        [self.floatingButton setTitle:@"⚙️" forState:UIControlStateNormal];
        self.floatingButton.titleLabel.font = [UIFont systemFontOfSize:24];
        self.floatingButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.7];
        self.layer.cornerRadius = 25;
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [UIColor greenColor].CGColor;
        self.clipsToBounds = YES;
        
        [self.floatingButton addTarget:self action:@selector(openManagerMenu) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.floatingButton];
    }
    return self;
}

- (void)openManagerMenu {
    UIWindow *keyWindow = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                for (UIWindow *w in windowScene.windows) {
                    if (w.isKeyWindow) { keyWindow = w; break; }
                }
            }
        }
    }
    if (!keyWindow) keyWindow = [UIApplication sharedApplication].keyWindow;
    UIViewController *rootVC = keyWindow.rootViewController;
    while (rootVC.presentedViewController) { rootVC = rootVC.presentedViewController; }
    
    NSString *acc1 = getCustomAccountUUID(@"Account1_UUID", kDefaultAcc1_UUID);
    NSString *acc2 = getCustomAccountUUID(@"Account2_UUID", kDefaultAcc2_UUID);
    NSString *acc3 = getCustomAccountUUID(@"Account3_UUID", kDefaultAcc3_UUID);
    NSString *currentUUID = getAppCurrentUUIDFromKeychain();
    
    NSString *msg = [NSString stringWithFormat:@"الحساب الحالي نشط:\n%@\n\nاختر الحساب للتبديل مع تنظيف جذري، أو اضغط تعديل الـ UUIDs.", currentUUID ?: @"غير معروف"];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"إدارة الحسابات الثلاثة"
                                                                   message:msg
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"🔄 التبديل إلى الحساب (1)" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        executeSwitchAndCleanToAccount(acc1);
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"🔄 التبديل إلى الحساب (2)" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        executeSwitchAndCleanToAccount(acc2);
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"🔄 التبديل إلى الحساب (3)" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        executeSwitchAndCleanToAccount(acc3);
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"✏️ تعديل الـ UUIDs للحسابات" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self openEditUUIDsPrompt:rootVC];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    
    if (rootVC) {
        [rootVC presentViewController:alert animated:YES completion:nil];
    }
}

- (void)openEditUUIDsPrompt:(UIViewController *)parentVC {
    NSString *acc1 = getCustomAccountUUID(@"Account1_UUID", kDefaultAcc1_UUID);
    NSString *acc2 = getCustomAccountUUID(@"Account2_UUID", kDefaultAcc2_UUID);
    NSString *acc3 = getCustomAccountUUID(@"Account3_UUID", kDefaultAcc3_UUID);
    
    UIAlertController *editAlert = [UIAlertController alertControllerWithTitle:@"تعديل قيم الـ UUID"
                                                                      message:@"أدخل الـ UUID الجديد لكل حساب (يحفظ في الملف):"
                                                               preferredStyle:UIAlertControllerStyleAlert];
    
    [editAlert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.text = acc1;
        textField.placeholder = @"UUID الحساب الأول";
    }];
    [editAlert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.text = acc2;
        textField.placeholder = @"UUID الحساب الثاني";
    }];
    [editAlert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.text = acc3;
        textField.placeholder = @"UUID الحساب الثالث";
    }];
    
    void (^saveHandler)(UIAlertAction *) = ^(UIAlertAction *action) {
        UITextField *tf1 = editAlert.textFields[0];
        UITextField *tf2 = editAlert.textFields[1];
        UITextField *tf3 = editAlert.textFields[2];
        
        if (tf1.text.length > 0) setCustomAccountUUID(@"Account1_UUID", tf1.text);
        if (tf2.text.length > 0) setCustomAccountUUID(@"Account2_UUID", tf2.text);
        if (tf3.text.length > 0) setCustomAccountUUID(@"Account3_UUID", tf3.text);
        
        UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"تم الحفظ" message:@"تم تحديث وتخزين الـ UUIDs في الملف بنجاح." preferredStyle:UIAlertControllerStyleAlert];
        [successAlert addAction:[UIAlertAction actionWithTitle:@"حسناً" style:UIAlertActionStyleDefault handler:nil]];
        [parentVC presentViewController:successAlert animated:YES completion:nil];
    };
    
    [editAlert addAction:[UIAlertAction actionWithTitle:@"حفظ" style:UIAlertActionStyleDefault handler:saveHandler]];
    [editAlert addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    
    [parentVC presentViewController:editAlert animated:YES completion:nil];
}
@end

// --- إظهار الزر العائم أعلى الشاشة ---
void setupOverlayButton(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = nil;
        if (@available(iOS 13.0, *)) {
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
                    UIWindowScene *windowScene = (UIWindowScene *)scene;
                    for (UIWindow *w in windowScene.windows) {
                        if (w.isKeyWindow) { keyWindow = w; break; }
                    }
                }
            }
        }
        if (!keyWindow) keyWindow = [UIApplication sharedApplication].keyWindow;
        if (keyWindow) {
            AccountManagerButtonView *btnView = [AccountManagerButtonView sharedInstance];
            [keyWindow addSubview:btnView];
        }
    });
}

// --- التحقق الذكي عند الإقلاع وضبط الحساب الأول إذا لزم الأمر ---
void checkAndEnforceValidAccount(void) {
    NSString *path = getStatePlistPath();
    NSFileManager *fm = [NSFileManager defaultManager];
    
    if (![fm fileExistsAtPath:path]) {
        NSDictionary *backupState = loadStateBackupFromKeychain();
        if (backupState) {
            [backupState writeToFile:path atomically:YES];
        } else {
            NSDictionary *defaultDict = @{
                @"Account1_UUID": kDefaultAcc1_UUID,
                @"Account2_UUID": kDefaultAcc2_UUID,
                @"Account3_UUID": kDefaultAcc3_UUID
            };
            [defaultDict writeToFile:path atomically:YES];
            saveStateBackupToKeychain(defaultDict);
        }
    }
    
    NSString *acc1 = getCustomAccountUUID(@"Account1_UUID", kDefaultAcc1_UUID);
    NSString *acc2 = getCustomAccountUUID(@"Account2_UUID", kDefaultAcc2_UUID);
    NSString *acc3 = getCustomAccountUUID(@"Account3_UUID", kDefaultAcc3_UUID);
    
    NSString *currentUUID = getAppCurrentUUIDFromKeychain();
    if (![currentUUID isEqualToString:acc1] && 
        ![currentUUID isEqualToString:acc2] && 
        ![currentUUID isEqualToString:acc3]) {
        
        saveUUIDToKeychain(acc1);
    }
}

// --- التزوير الديناميكي والعشوائي لبيئة الجهاز ---
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

// --- تهيئة التويك عند بدء التشغيل ---
%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        checkAndEnforceValidAccount();
        setupOverlayButton();
    });
}
