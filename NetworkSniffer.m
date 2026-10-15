#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <WebKit/WebKit.h>
#import <Security/Security.h>

// --- الثوابت الأساسية ---
static NSString * const kKeychainAccount       = @"com.tempnum.virtualnumber.deviceUUID";
static NSString * const kKeychainStateBackup   = @"com.tempnum.virtualnumber.stateBackup";
static NSString * const kKeychainGroup         = @"3J96GNXKKU.*";

// قيم افتراضية أولية للحسابات الأربعة
static NSString * const kDefaultAcc1_UUID = @"1A2B3C4D-5E5F-7A8B-9C0F-1E2F3A4B5C6D";
static NSString * const kDefaultAcc2_UUID = @"2B3C4E5E-6F75-8B9C-0D1E-2F3A4B5C6DFE";
static NSString * const kDefaultAcc3_UUID = @"3C4D5E6F-7A85-9C0D-1E2F-3A4B5C6D7F8F";
static NSString * const kDefaultAcc4_UUID = @"4D5E6F7A-8B95-0C1D-2E3F-4A5B6C7DFE9F";

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

// --- جلب وحفظ الـ UUIDs من الملف ---
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

// --- دالة التبديل التسلسلي التلقائي ---
void performSequentialAutoSwitch(void) {
    NSString *path = getStatePlistPath();
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] initWithContentsOfFile:path];
    if (!dict) {
        dict = [NSMutableDictionary dictionary];
    }
    
    NSInteger currentStep = dict[@"AutoSequenceStep"] ? [dict[@"AutoSequenceStep"] integerValue] : 1;
    NSString *targetUUID = nil;
    NSInteger nextStep = 1;
    
    NSString *acc1 = getCustomAccountUUID(@"Account1_UUID", kDefaultAcc1_UUID);
    NSString *acc2 = getCustomAccountUUID(@"Account2_UUID", kDefaultAcc2_UUID);
    NSString *acc3 = getCustomAccountUUID(@"Account3_UUID", kDefaultAcc3_UUID);
    NSString *acc4 = getCustomAccountUUID(@"Account4_UUID", kDefaultAcc4_UUID);
    
    if (currentStep == 1) {
        targetUUID = acc2;
        nextStep = 2;
    } else if (currentStep == 2) {
        targetUUID = acc3;
        nextStep = 3;
    } else if (currentStep == 3) {
        targetUUID = acc4;
        nextStep = 4;
    } else {
        targetUUID = acc1;
        nextStep = 1;
    }
    
    dict[@"AutoSequenceStep"] = @(nextStep);
    dict[@"TimerRemaining"] = @(300);
    [dict writeToFile:path atomically:YES];
    saveStateBackupToKeychain(dict);
    
    executeSwitchAndCleanToAccount(targetUUID);
}

// --- واجهة المربع الصغير العائم (العداد وزر الإعدادات) أعلى الشاشة على اليمين ---
@interface AccountManagerButtonView : UIView
@property (nonatomic, strong) UIButton *floatingButton;
@property (nonatomic, strong) UILabel *timerLabel;
@property (nonatomic, strong) NSTimer *countdownTimer;
@property (nonatomic, assign) NSInteger remainingSeconds;
@end

@implementation AccountManagerButtonView

+ (instancetype)sharedInstance {
    static AccountManagerButtonView *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
        sharedInstance = [[AccountManagerButtonView alloc] initWithFrame:CGRectMake(screenWidth - 135, 45, 120, 50)];
    });
    return sharedInstance;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.8];
        self.layer.cornerRadius = 8;
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [UIColor greenColor].CGColor;
        self.clipsToBounds = YES;
        
        self.floatingButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.floatingButton.frame = CGRectMake(80, 5, 35, 40);
        [self.floatingButton setTitle:@"⚙️" forState:UIControlStateNormal];
        self.floatingButton.titleLabel.font = [UIFont systemFontOfSize:20];
        [self.floatingButton addTarget:self action:@selector(openManagerMenu) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.floatingButton];
        
        self.timerLabel = [[UILabel alloc] initWithFrame:CGRectMake(5, 3, 75, 44)];
        self.timerLabel.textColor = [UIColor greenColor];
        self.timerLabel.font = [UIFont boldSystemFontOfSize:9.5];
        self.timerLabel.textAlignment = NSTextAlignmentCenter;
        self.timerLabel.numberOfLines = 3;
        [self addSubview:self.timerLabel];
        
        NSString *path = getStatePlistPath();
        NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
        if (dict && dict[@"TimerRemaining"]) {
            self.remainingSeconds = [dict[@"TimerRemaining"] integerValue];
        } else {
            self.remainingSeconds = 300;
        }
        
        [self updateTimerDisplay];
        [self startCountdownEngine];
    }
    return self;
}

- (void)startCountdownEngine {
    self.countdownTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(tickerStep) userInfo:nil repeats:YES];
}

- (void)tickerStep {
    self.remainingSeconds--;
    
    NSString *path = getStatePlistPath();
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] initWithContentsOfFile:path];
    if (!dict) dict = [NSMutableDictionary dictionary];
    dict[@"TimerRemaining"] = @(self.remainingSeconds);
    [dict writeToFile:path atomically:YES];
    
    if (self.remainingSeconds <= 0) {
        [self.countdownTimer invalidate];
        self.countdownTimer = nil;
        performSequentialAutoSwitch();
        return;
    }
    
    [self updateTimerDisplay];
}

- (void)updateTimerDisplay {
    NSInteger mins = self.remainingSeconds / 60;
    NSInteger secs = self.remainingSeconds % 60;
    
    NSString *path = getStatePlistPath();
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
    NSInteger step = dict[@"AutoSequenceStep"] ? [dict[@"AutoSequenceStep"] integerValue] : 1;
    
    NSString *accountKey = [NSString stringWithFormat:@"Account%ld_UUID", (long)step];
    NSString *fallbackUUID = (step == 1) ? kDefaultAcc1_UUID : (step == 2) ? kDefaultAcc2_UUID : (step == 3) ? kDefaultAcc3_UUID : kDefaultAcc4_UUID;
    NSString *uuid = getCustomAccountUUID(accountKey, fallbackUUID);
    
    NSString *shortName = (uuid.length >= 8) ? [uuid substringToIndex:8] : @"Account";
    
    self.timerLabel.text = [NSString stringWithFormat:@"حساب %ld (%@)\n⏱ %02ld:%02ld", (long)step, shortName, (long)mins, (long)secs];
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
    NSString *acc4 = getCustomAccountUUID(@"Account4_UUID", kDefaultAcc4_UUID);
    NSString *currentUUID = getAppCurrentUUIDFromKeychain();
    
    NSString *msg = [NSString stringWithFormat:@"الحساب الحالي نشط:\n%@\n\n(يتم التبديل التلقائي كل 5 دقائق).", currentUUID ?: @"غير معروف"];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"إدارة الحسابات والتبديل"
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
    
    [alert addAction:[UIAlertAction actionWithTitle:@"🔄 التبديل إلى الحساب (4)" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        executeSwitchAndCleanToAccount(acc4);
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
    NSString *acc4 = getCustomAccountUUID(@"Account4_UUID", kDefaultAcc4_UUID);
    
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
    [editAlert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.text = acc4;
        textField.placeholder = @"UUID الحساب الرابع";
    }];
    
    [editAlert addAction:[UIAlertAction actionWithTitle:@"حفظ" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        UITextField *tf1 = editAlert.textFields[0];
        UITextField *tf2 = editAlert.textFields[1];
        UITextField *tf3 = editAlert.textFields[2];
        UITextField *tf4 = editAlert.textFields[3];
        
        if (tf1.text.length > 0) setCustomAccountUUID(@"Account1_UUID", tf1.text);
        if (tf2.text.length > 0) setCustomAccountUUID(@"Account2_UUID", tf2.text);
        if (tf3.text.length > 0) setCustomAccountUUID(@"Account3_UUID", tf3.text);
        if (tf4.text.length > 0) setCustomAccountUUID(@"Account4_UUID", tf4.text);
        
        UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"تم الحفظ" message:@"تم تحديث وتخزين الـ UUIDs في الملف بنجاح." preferredStyle:UIAlertControllerStyleAlert];
        [successAlert addAction:[UIAlertAction actionWithTitle:@"حسناً" style:UIAlertActionStyleDefault handler:nil]];
        [parentVC presentViewController:successAlert animated:YES completion:nil];
    }]];
    
    [editAlert addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    
    [parentVC presentViewController:editAlert animated:YES completion:nil];
}

@end

// --- إظهار المربع الصغير أعلى الشاشة على اليمين ---
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
                @"Account3_UUID": kDefaultAcc3_UUID,
                @"Account4_UUID": kDefaultAcc4_UUID,
                @"AutoSequenceStep": @(1),
                @"TimerRemaining": @(300)
            };
            [defaultDict writeToFile:path atomically:YES];
            saveStateBackupToKeychain(defaultDict);
        }
    }
    
    NSString *acc1 = getCustomAccountUUID(@"Account1_UUID", kDefaultAcc1_UUID);
    NSString *acc2 = getCustomAccountUUID(@"Account2_UUID", kDefaultAcc2_UUID);
    NSString *acc3 = getCustomAccountUUID(@"Account3_UUID", kDefaultAcc3_UUID);
    NSString *acc4 = getCustomAccountUUID(@"Account4_UUID", kDefaultAcc4_UUID);
    
    NSString *currentUUID = getAppCurrentUUIDFromKeychain();
    if (![currentUUID isEqualToString:acc1] && 
        ![currentUUID isEqualToString:acc2] && 
        ![currentUUID isEqualToString:acc3] && 
        ![currentUUID isEqualToString:acc4]) {
        
        saveUUIDToKeychain(acc1);
    }
}

// --- التهيئة البديلة (بدون استخدام رموز Logos المعمارية لملفات الـ .m) ---
__attribute__((constructor)) static void initializer(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        checkAndEnforceValidAccount();
        setupOverlayButton();
    });
}
