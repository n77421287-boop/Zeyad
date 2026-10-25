#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AdSupport/AdSupport.h>
#import <AppTrackingTransparency/AppTrackingTransparency.h>
#import <Security/Security.h>
#import <objc/runtime.h>

extern void executeFullEnvironmentRefresh(void);

static NSString *currentRandomIDFA = nil;
static NSString *currentRandomIDFV = nil;

// مسار ملف الحفظ في مجلد الـ Documents
static NSString * getRestoreStateFilePath() {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    return [documentsDirectory stringByAppendingPathComponent:@"AppRestoreState.txt"];
}

// 1. مسح الكايتشين بالكامل وزرع التوكن الجديد
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
    
    SecItemAdd((__bridge CFDictionaryRef)addQuery, NULL);
}

// 2. التنظيف الجذري مع الاستثناء التام لملف الحالة في الـ Documents
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
            // استثناء مجلد Documents من الحذف المباشر لكي نحمي ملف الاستثناء داخله
            if ([item isEqualToString:@"Documents"]) {
                NSString *docsPath = [homeDir stringByAppendingPathComponent:@"Documents"];
                NSArray *docContents = [fileManager contentsOfDirectoryAtPath:docsPath error:nil];
                for (NSString *docItem in docContents) {
                    // احذف كل شيء في الـ Documents ما عدا ملف الاستعادة الخاص بنا
                    if (![docItem isEqualToString:@"AppRestoreState.txt"]) {
                        NSString *fullDocItemPath = [docsPath stringByAppendingPathComponent:docItem];
                        [fileManager removeItemAtPath:fullDocItemPath error:&error];
                    }
                }
                continue;
            }
            
            NSString *fullPath = [homeDir stringByAppendingPathComponent:item];
            [fileManager removeItemAtPath:fullPath error:&error];
        }
        
        NSString *groupDirBase = [[[homeDir stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"Group Containers"];
        if ([fileManager fileExistsAtPath:groupDirBase]) {
            NSArray *groupFolders = [fileManager contentsOfDirectoryAtPath:groupDirBase error:nil];
            for (NSString *groupFolder in groupFolders) {
                NSString *groupPath = [groupDirBase stringByAppendingPathComponent:groupFolder];
                [fileManager removeItemAtPath:groupPath error:&error];
            }
        }

        NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleIdentifier) {
            [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:bundleIdentifier];
            NSString *libraryPrefsPath = [homeDir stringByAppendingPathComponent:@"Library/Preferences"];
            NSArray *prefFiles = [fileManager contentsOfDirectoryAtPath:libraryPrefsPath error:nil];
            for (NSString *file in prefFiles) {
                if ([file containsString:bundleIdentifier] || [file hasSuffix:@".plist"]) {
                    [fileManager removeItemAtPath:[libraryPrefsPath stringByAppendingPathComponent:file] error:nil];
                }
            }
        }
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

// 3. النافذة والزر العائم
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
    self->refreshButton.frame = CGRectMake(screenBounds.size.width - 160, 60, 140, 40);
    
    [self->refreshButton addTarget:self action:@selector(handleRefreshButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    self->floatingWindow.targetButton = self->refreshButton;
    [emptyVC.view addSubview:self->refreshButton];
    [self->floatingWindow setHidden:NO];
}

// دالة الضغط: حفظ مكان الـ Tab في الـ Documents، ثم التنظيف (مع استثناء الملف)، ثم الإغلاق
- (void)handleRefreshButtonTapped {
    UIWindow *targetWindow = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
            for (UIWindow *win in ((UIWindowScene *)scene).windows) {
                if (win.isKeyWindow) { targetWindow = win; break; }
            }
        }
    }
    
    // 1. حفظ رقم الـ Tab الحالي في ملف داخل مجلد الـ Documents مباشرة قبل أي شيء
    if (targetWindow && [targetWindow.rootViewController isKindOfClass:[UITabBarController class]]) {
        NSInteger selectedIndex = ((UITabBarController *)targetWindow.rootViewController).selectedIndex;
        NSString *stateData = [NSString stringWithFormat:@"TAB:%ld", (long)selectedIndex];
        
        NSString *docsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        [[NSFileManager defaultManager] createDirectoryAtPath:docsPath withIntermediateDirectories:YES attributes:nil error:nil];
        [stateData writeToFile:getRestoreStateFilePath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    
    // 2. تنفيذ التنظيف الجذري (والذي سيستثني هذا الملف تماماً من الحذف)
    executeFullEnvironmentRefresh();
    
    // 3. إغلاق التطبيق طبيعياً لتفتحه أنت يدوياً
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        exit(0);
    });
}

@end

// استعادة مكان المستخدم فور فتح التطبيق يدوياً
%hook UIResponder
- (void)didMoveToWindow {
    %orig;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSString *path = getRestoreStateFilePath();
            NSString *stateData = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
            if (stateData) {
                // حذف الملف فوراً بعد إرجاعك لمكانك حتى لا يتكرر الانتقال في الفتحات العادية القادمة
                [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
                
                UIWindow *targetWindow = nil;
                for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                    if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
                        for (UIWindow *win in ((UIWindowScene *)scene).windows) {
                            if (win.isKeyWindow) { targetWindow = win; break; }
                        }
                    }
                }
                
                if (targetWindow && [targetWindow.rootViewController isKindOfClass:[UITabBarController class]]) {
                    if ([stateData hasPrefix:@"TAB:"]) {
                        NSInteger index = [[stateData substringFromIndex:4] integerValue];
                        ((UITabBarController *)targetWindow.rootViewController).selectedIndex = index;
                    }
                }
            }
        });
    });
}
%end

%ctor {
    currentRandomIDFA = [[NSUUID UUID] UUIDString];
    currentRandomIDFV = [[NSUUID UUID] UUIDString];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[FloatingButtonManager sharedInstance] showFloatingButton];
    });
}

%hook UIDevice
- (NSUUID *)identifierForVendor {
    return currentRandomIDFV ? [[NSUUID alloc] initWithUUIDString:currentRandomIDFV] : %orig;
}
%end

%hook ASIdentifierManager
- (NSUUID *)advertisingIdentifier {
    return currentRandomIDFA ? [[NSUUID alloc] initWithUUIDString:currentRandomIDFA] : %orig;
}
%end
