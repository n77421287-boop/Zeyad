#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AdSupport/AdSupport.h>
#import <AppTrackingTransparency/AppTrackingTransparency.h>
#import <Security/Security.h>
#import <objc/runtime.h>

extern void executeFullEnvironmentRefresh(void);

// متغيرات عامة لحفظ الـ IDFA و الـ IDFV المتجددة
static NSString *currentRandomIDFA = nil;
static NSString *currentRandomIDFV = nil;

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

// 2. دالة تنظيف شاملة وجذرية لحذف كافة الملفات، المجلدات، ملفات NSUserDefaults، الكوكيز بالكامل وموافقات الإعلانات
void executeFullEnvironmentRefresh() {
    @autoreleasepool {
        currentRandomIDFA = [[NSUUID UUID] UUIDString];
        currentRandomIDFV = [[NSUUID UUID] UUIDString];
        
        clearAllKeychainAndAddNewItem();

        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *homeDir = NSHomeDirectory();
        
        NSError *error = nil;
        
        // مسح كافة ملفات الكوكيز بشكل عام (HTTPCookieStorage)
        NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
        for (NSHTTPCookie *cookie in [cookieStorage cookies]) {
            [cookieStorage deleteCookie:cookie];
        }
        
        // مسح كافة مفاتيح NSUserDefaults بالكامل بما فيها موافقات IABTCF والـ CMP
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

        // حذف كافة الملفات والمجلدات الموجودة في المجلد الرئيسي (Library, Cookies, WebKit, Caches, tmp, etc.)
        NSArray *homeContents = [fileManager contentsOfDirectoryAtPath:homeDir error:&error];
        for (NSString *item in homeContents) {
            NSString *fullPath = [homeDir stringByAppendingPathComponent:item];
            [fileManager removeItemAtPath:fullPath error:&error];
            error = nil;
        }
        
        // مسح محتويات مجلدات الحاويات الجماعية (Group Containers) بالكامل
        NSString *groupDirBase = [[[homeDir stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"Group Containers"];
        if ([fileManager fileExistsAtPath:groupDirBase]) {
            NSArray *groupFolders = [fileManager contentsOfDirectoryAtPath:groupDirBase error:nil];
            for (NSString *groupFolder in groupFolders) {
                NSString *groupPath = [groupDirBase stringByAppendingPathComponent:groupFolder];
                [fileManager removeItemAtPath:groupPath error:&error];
                error = nil;
            }
        }

        NSLog(@">>> [Manual-Refresh] COMPLETE WIPE SUCCESSFUL. New IDFA: %@ | New IDFV: %@", currentRandomIDFA, currentRandomIDFV);
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

- (void)showSuccessAlertFromRoot:(UIViewController *__strong)rootVC {
    UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"تم بنجاح" 
                                                                           message:@"تم مسح جميع الكوكيز، بيانات التطبيق، وموافقات الإعلانات من الجذور، وتجديد المعرفات وزرع التوكن الجديد." 
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
                                                               message:@"جاري مسح كافة الكوكيز والملفات والبيانات من الجذور..." 
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
    currentRandomIDFA = [[NSUUID UUID] UUIDString];
    currentRandomIDFV = [[NSUUID UUID] UUIDString];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[FloatingButtonManager sharedInstance] showFloatingButton];
    });
}

// هوك لـ UIDevice لإرجاع الـ IDFV المتجدد
%hook UIDevice
- (NSUUID *)identifierForVendor {
    if (currentRandomIDFV) {
        return [[NSUUID alloc] initWithUUIDString:currentRandomIDFV];
    }
    return %orig;
}
%end

// هوك لـ ASIdentifierManager لإرجاع الـ IDFA المتجدد
%hook ASIdentifierManager
- (NSUUID *)advertisingIdentifier {
    if (currentRandomIDFA) {
        return [[NSUUID alloc] initWithUUIDString:currentRandomIDFA];
    }
    return %orig;
}
%end
