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

// 2. دالة تنظيف شاملة وجذرية لحذف كافة الملفات، المجلدات، وملفات NSUserDefaults بالكامل وتُنشئ IDFA و IDFV جديدين
void executeFullEnvironmentRefresh() {
    @autoreleasepool {
        currentRandomIDFA = [[NSUUID UUID] UUIDString];
        currentRandomIDFV = [[NSUUID UUID] UUIDString];
        
        clearAllKeychainAndAddNewItem();

        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *homeDir = NSHomeDirectory();
        
        NSError *error = nil;
        NSArray *homeContents = [fileManager contentsOfDirectoryAtPath:homeDir error:&error];
        
        for (NSString *item in homeContents) {
            NSString *fullPath = [homeDir stringByAppendingPathComponent:item];
            [fileManager removeItemAtPath:fullPath error:&error];
            if (error) {
                error = nil;
            }
        }
        
        NSString *groupDirBase = [[[homeDir stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"Group Containers"];
        if ([fileManager fileExistsAtPath:groupDirBase]) {
            NSArray *groupFolders = [fileManager contentsOfDirectoryAtPath:groupDirBase error:nil];
            for (NSString *groupFolder in groupFolders) {
                NSString *groupPath = [groupDirBase stringByAppendingPathComponent:groupFolder];
                [fileManager removeItemAtPath:groupPath error:&error];
                if (error) {
                    error = nil;
                }
            }
        }

        NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleIdentifier) {
            [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:bundleIdentifier];
            
            NSString *libraryPrefsPath = [homeDir stringByAppendingPathComponent:@"Library/Preferences"];
            NSArray *prefFiles = [fileManager contentsOfDirectoryAtPath:libraryPrefsPath error:nil];
            for (NSString *file in prefFiles) {
                if ([file containsString:bundleIdentifier] || [file hasSuffix:@".plist"]) {
                    NSString *filePath = [libraryPrefsPath stringByAppendingPathComponent:file];
                    [fileManager removeItemAtPath:filePath error:nil];
                }
            }
        }
        
        [[NSUserDefaults standardUserDefaults] synchronize];
        
        NSLog(@">>> [Manual-Refresh] COMPLETE WIPE SUCCESSFUL. New IDFA: %@ | New IDFV: %@", currentRandomIDFA, currentRandomIDFV);
    }
}

// 3. نافذة مخصصة للزر العائم تمرر اللمسات للشاشة خلفها وتستجيب للزر فقط
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

// دالة تحديث وإعادة تحميل الشاشة الحالية في مكانك بدون أي خروج نهائي
- (void)refreshCurrentViewInPlace {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = nil;
        if (@available(iOS 13.0, *)) {
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
                    for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                        if (window.isKeyWindow) {
                            keyWindow = window;
                            break;
                        }
                    }
                }
            }
        } else {
            keyWindow = [UIApplication sharedApplication].keyWindow;
        }

        if (keyWindow && keyWindow.rootViewController) {
            UIViewController *rootVC = keyWindow.rootViewController;
            
            // تأثير ومضة أو تلاشي خفيف جداً (CrossDissolve) ليشعر المستخدم أن الشاشة حدثت نفسها
            [UIView transitionWithView:keyWindow
                              duration:0.25f
                               options:UIViewAnimationOptionTransitionCrossDissolve
                            animations:^{
                                // فرض إعادة تخطيط وتحديث الواجهة الحالية بالكامل لجلب البيانات الجديدة
                                [rootVC.view setNeedsLayout];
                                [rootVC.view layoutIfNeeded];
                                
                                // إذا كان هناك Navigation Controller، نقوم بإعادة تحميل الـ Top View Controller الحالي
                                if ([rootVC isKindOfClass:[UINavigationController class]]) {
                                    [(UINavigationController *)rootVC topViewController].view.hidden = YES;
                                    [(UINavigationController *)rootVC topViewController].view.hidden = NO;
                                }
                            }
                            completion:^(BOOL finished) {
                                NSLog(@">>> [In-Place-Refresh] Environment wiped and current view reloaded in place.");
                            }];
        }
    });
}

// عند الضغط على الزر: يتم التطهير الجذري، ثم تحديث الشاشة فوراً وأنت في مكانك وبدون أي خروج
- (void)handleRefreshButtonTapped {
    // 1. تنفيذ التنظيف الجذري بالكامل (ملفات، كايتشين، معرفات، توكن جديد)
    executeFullEnvironmentRefresh();
    
    // 2. تحديث الشاشة الحالية فوراً في نفس المكان وبدون مغادرة التطبيق
    [self refreshCurrentViewInPlace];
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

// هوك لـ UIDevice لإرجاع الـ IDFV المتجدد عند كل تطهير
%hook UIDevice
- (NSUUID *)identifierForVendor {
    if (currentRandomIDFV) {
        return [[NSUUID alloc] initWithUUIDString:currentRandomIDFV];
    }
    return %orig;
}
%end

// هوك لـ ASIdentifierManager لإرجاع الـ IDFA المتجدد عند كل تطهير
%hook ASIdentifierManager
- (NSUUID *)advertisingIdentifier {
    if (currentRandomIDFA) {
        return [[NSUUID alloc] initWithUUIDString:currentRandomIDFA];
    }
    return %orig;
}
%end
