#import <UIKit/UIKit.h>

// تعريف واجهات الإيماءات الخاصة بنظام الوصول المساعد (نفس آلية الأوامر الصوتية)
@interface AXReplayableGesture : NSObject <NSCoding, NSCopying>
+ (id)playableGestureWithPoints:(NSArray *)points;
@end

@interface AXServer : NSObject
+ (instancetype)sharedInstance;
- (void)postReplayableGesture:(AXReplayableGesture *)gesture scheduledDelivery:(BOOL)delivery completion:(void(^)(void))completion;
@end

@interface GestureAutomationManager : NSObject
@property (nonatomic, strong) NSMutableArray *pointsArray;
@property (nonatomic, assign) BOOL isRecording;
+ (instancetype)sharedManager;
- (void)startRecording;
- (void)stopRecording;
- (void)playGesture;
@end

@implementation GestureAutomationManager

+ (instancetype)sharedManager {
    static GestureAutomationManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[GestureAutomationManager alloc] init];
        manager.pointsArray = [NSMutableArray array];
    });
    return manager;
}

- (void)startRecording {
    self.isRecording = YES;
    [self.pointsArray removeAllObjects];
    NSLog(@"[Automation] بدأ تسجيل النقاط...");
}

- (void)stopRecording {
    self.isRecording = NO;
    NSLog(@"[Automation] تم الحفظ. عدد النقاط المسجلة: %lu", (unsigned long)self.pointsArray.count);
}

- (void)playGesture {
    if (self.pointsArray.count == 0) {
        NSLog(@"[Automation] لا توجد نقاط لتشغيلها!");
        return;
    }
    
    // إرسال الإيماءة تماماً مثل آلية التحكم الصوتي
    id gesture = [AXReplayableGesture playableGestureWithPoints:self.pointsArray];
    if (gesture && [[AXServer sharedInstance] respondsToSelector:@selector(postReplayableGesture:scheduledDelivery:completion:)]) {
        [[AXServer sharedInstance] postReplayableGesture:gesture scheduledDelivery:NO completion:^{
            NSLog(@"[Automation] تم تنفيذ الإيماءة بنجاح على الشاشة!");
        }];
    }
}

@end

// نافذة الزر العائم للتحكم
@interface FloatingMenuWindow : NSObject
@property (nonatomic, strong) UIWindow *window;
@end

@implementation FloatingMenuWindow

+ (instancetype)shared {
    static FloatingMenuWindow *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[FloatingMenuWindow alloc] init];
    });
    return sharedInstance;
}

- (void)show {
    dispatch_async(dispatch_get_main_async(), ^{
        UIWindowScene *scene = (UIWindowScene *)[[UIApplication sharedApplication].connectedScenes.allObjects firstObject];
        if (!scene) return;
        
        self.window = [[UIWindow alloc] initWithWindowScene:scene];
        self.window.frame = CGRectMake(15, 120, 55, 55);
        self.window.windowLevel = UIWindowLevelAlert + 100;
        self.window.backgroundColor = [UIColor clearColor];
        
        UIViewController *vc = [[UIViewController alloc] init];
        self.window.rootViewController = vc;
        
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame = CGRectMake(0, 0, 55, 55);
        btn.backgroundColor = [UIColor systemIndigoColor];
        [btn setTitle:@"ايماءة" forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        btn.layer.cornerRadius = 27.5;
        [btn addTarget:self action:@selector(openMenu) forControlEvents:UIControlEventTouchUpInside];
        
        [vc.view addSubview:btn];
        [self.window makeKeyAndVisible];
    });
}

- (void)openMenu {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"محاكي الأوامر الصوتية" 
                                                                   message:@"اختر العملية:" 
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
                                                            
    [alert addAction:[UIAlertAction actionWithTitle:@"بدء التسجيل" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [[GestureAutomationManager sharedManager] startRecording];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"حفظ التسجيل" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [[GestureAutomationManager sharedManager] stopRecording];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"تشغيل الإيماءة" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [[GestureAutomationManager sharedManager] playGesture];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    
    // إظهار القائمة على نافذة التطبيق الأساسية
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    [keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
}

@end

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_async(), ^{
        [[FloatingMenuWindow shared] show];
    });
}
