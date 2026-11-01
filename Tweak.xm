#import <UIKit/UIKit.h>

// إعلانات واجهات النظام الداخلية لتوليد لمسات حقيقية
@interface UIEvent (TouchAllocation)
+ (id)_eventWithTouch:(UITouch *)touch;
@end

@interface UITouch (Creation)
- (void)_setLocationInWindow:(CGPoint)location resetPrevious:(BOOL)reset;
- (void)_setWindow:(UIWindow *)window;
- (void)_setView:(UIView *)view;
- (void)_setPhase:(UITouchPhase)phase;
- (void)_setTimestamp:(NSTimeInterval)timestamp;
@end

// هيكل بيانات لتخزين النقرات والفارق الزمني
@interface TouchRecord : NSObject
@property (nonatomic, assign) CGPoint point;
@property (nonatomic, assign) NSTimeInterval timeIntervalSinceLast;
@end

@implementation TouchRecord
@end

static NSMutableArray<TouchRecord *> *recordedEvents = nil;
static BOOL isRecording = NO;
static BOOL isPlaying = NO;
static UIWindow *floatingWindow = nil;
static NSTimeInterval lastTouchTimestamp = 0;

// دالة مساعدة للحصول على النافذة النشطة بشكل آمن
UIWindow *getCurrentKeyWindow() {
    for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive) {
            for (UIWindow *window in scene.windows) {
                if (window.isKeyWindow) {
                    return window;
                }
            }
        }
    }
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        if (window.isKeyWindow) {
            return window;
        }
    }
    return [UIApplication sharedApplication].windows.firstObject;
}

// دالة لرسم دائرة حمراء مؤقتة في مكان الضغطة على الشاشة
void showTouchIndicatorAtPoint(CGPoint point) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *targetWindow = getCurrentKeyWindow();
        if (!targetWindow) return;

        UIView *indicator = [[UIView alloc] initWithFrame:CGRectMake(point.x - 15, point.y - 15, 30, 30)];
        indicator.backgroundColor = [[UIColor redColor] colorWithAlphaComponent:0.7];
        indicator.layer.cornerRadius = 15;
        indicator.layer.borderWidth = 1.5;
        indicator.layer.borderColor = [UIColor whiteColor].CGColor;
        indicator.userInteractionEnabled = NO;
        
        [targetWindow addSubview:indicator];

        [UIView animateWithDuration:0.3 animations:^{
            indicator.transform = CGAffineTransformMakeScale(1.4, 1.4);
            indicator.alpha = 0.0;
        } completion:^(BOOL finished) {
            [indicator removeFromSuperview];
        }];
    });
}

// دالة محاكاة الضغطة الحقيقية مع إظهار المؤشر الأحمر
void simulateFakeTouch(CGPoint point) {
    showTouchIndicatorAtPoint(point);

    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *targetWindow = getCurrentKeyWindow();
        if (!targetWindow) return;

        UIView *hitView = [targetWindow hitTest:point withEvent:nil];

        UITouch *touch = [[UITouch alloc] init];
        
        SEL setWindowSel = NSSelectorFromString(@"_setWindow:");
        if ([touch respondsToSelector:setWindowSel]) {
            [touch performSelector:setWindowSel withObject:targetWindow];
        }
        
        SEL setViewSel = NSSelectorFromString(@"_setView:");
        if ([touch respondsToSelector:setViewSel]) {
            [touch performSelector:setViewSel withObject:hitView];
        }
        
        SEL setLocationSel = NSSelectorFromString(@"_setLocationInWindow:resetPrevious:");
        if ([touch respondsToSelector:setLocationSel]) {
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[UITouch instanceMethodSignatureForSelector:setLocationSel]];
            [invocation setTarget:touch];
            [invocation setSelector:setLocationSel];
            [invocation setArgument:&point atIndex:2];
            BOOL reset = YES;
            [invocation setArgument:&reset atIndex:3];
            [invocation invoke];
        }
        
        SEL setTimestampSel = NSSelectorFromString(@"_setTimestamp:");
        if ([touch respondsToSelector:setTimestampSel]) {
            NSTimeInterval uptime = [NSProcessInfo processInfo].systemUptime;
            [touch performSelector:setTimestampSel withObject:@(uptime)];
        }

        SEL setPhaseSel = NSSelectorFromString(@"_setPhase:");
        if ([touch respondsToSelector:setPhaseSel]) {
            [touch performSelector:setPhaseSel withObject:@(UITouchPhaseBegan)];
        }
        
        SEL eventWithTouchSel = NSSelectorFromString(@"_eventWithTouch:");
        UIEvent *eventBegan = nil;
        if ([UIEvent respondsToSelector:eventWithTouchSel]) {
            eventBegan = [UIEvent performSelector:eventWithTouchSel withObject:touch];
        }
        
        if (eventBegan) {
            [[UIApplication sharedApplication] sendEvent:eventBegan];
            [targetWindow sendEvent:eventBegan];
        }

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.08 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if ([touch respondsToSelector:setPhaseSel]) {
                [touch performSelector:setPhaseSel withObject:@(UITouchPhaseEnded)];
            }
            if ([touch respondsToSelector:setTimestampSel]) {
                NSTimeInterval uptime = [NSProcessInfo processInfo].systemUptime;
                [touch performSelector:setTimestampSel withObject:@(uptime)];
            }
            
            UIEvent *eventEnded = nil;
            if ([UIEvent respondsToSelector:eventWithTouchSel]) {
                eventEnded = [UIEvent performSelector:eventWithTouchSel withObject:touch];
            }
            
            if (eventEnded) {
                [[UIApplication sharedApplication] sendEvent:eventEnded];
                [targetWindow sendEvent:eventEnded];
            }
        });
    });
}

void replayRecordedTouches() {
    if (!recordedEvents || recordedEvents.count == 0 || isPlaying) return;
    isPlaying = YES;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        for (TouchRecord *record in recordedEvents) {
            if (!isPlaying) break;
            
            if (record.timeIntervalSinceLast > 0) {
                useconds_t delayMicroseconds = (useconds_t)(record.timeIntervalSinceLast * 1000000.0);
                if (delayMicroseconds > 5000000) delayMicroseconds = 5000000;
                usleep(delayMicroseconds);
            }
            
            if (!isPlaying) break;
            simulateFakeTouch(record.point);
        }
        isPlaying = NO;
    });
}

@interface FloatingController : UIViewController
@end

@implementation FloatingController {
    UIButton *recordButton;
    UIButton *playButton;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.9];
    self.view.layer.cornerRadius = 14;
    self.view.layer.borderWidth = 1.0;
    self.view.layer.borderColor = [UIColor whiteColor].CGColor;
    
    recordButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [recordButton setTitle:@"بدء التسجيل" forState:UIControlStateNormal];
    [recordButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    recordButton.frame = CGRectMake(10, 10, 130, 40);
    recordButton.backgroundColor = [UIColor systemRedColor];
    recordButton.layer.cornerRadius = 8;
    [recordButton addTarget:self action:@selector(toggleRecord) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:recordButton];
    
    playButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [playButton setTitle:@"تشغيل التكرار" forState:UIControlStateNormal];
    [playButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    playButton.frame = CGRectMake(150, 10, 130, 40);
    playButton.backgroundColor = [UIColor systemGreenColor];
    playButton.layer.cornerRadius = 8;
    [playButton addTarget:self action:@selector(togglePlay) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:playButton];
    
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self.view addGestureRecognizer:pan];
}

- (void)toggleRecord {
    isRecording = !isRecording;
    if (isRecording) {
        if (!recordedEvents) recordedEvents = [[NSMutableArray alloc] init];
        [recordedEvents removeAllObjects];
        lastTouchTimestamp = 0;
        [recordButton setTitle:@"إيقاف التسجيل" forState:UIControlStateNormal];
        recordButton.backgroundColor = [UIColor systemOrangeColor];
    } else {
        [recordButton setTitle:@"بدء التسجيل" forState:UIControlStateNormal];
        recordButton.backgroundColor = [UIColor systemRedColor];
    }
}

- (void)togglePlay {
    if (isPlaying) {
        isPlaying = NO;
        [playButton setTitle:@"تشغيل التكرار" forState:UIControlStateNormal];
    } else {
        [playButton setTitle:@"إيقاف التشغيل" forState:UIControlStateNormal];
        replayRecordedTouches();
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self.view.superview];
    CGPoint center = self.view.center;
    self.view.center = CGPointMake(center.x + translation.x, center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:self.view.superview];
}

@end

%hook UIApplication

- (void)sendEvent:(UIEvent *)event {
    if (event.type == UIEventTypeTouches) {
        NSSet *touches = [event allTouches];
        UITouch *touch = [touches anyObject];
        
        if (isRecording && touch.phase == UITouchPhaseBegan) {
            CGPoint location = [touch locationInView:touch.window];
            
            if (touch.window != floatingWindow) {
                showTouchIndicatorAtPoint(location);

                NSTimeInterval currentTime = [NSProcessInfo processInfo].systemUptime;
                NSTimeInterval interval = 0;
                
                if (lastTouchTimestamp > 0) {
                    interval = currentTime - lastTouchTimestamp;
                }
                lastTouchTimestamp = currentTime;
                
                TouchRecord *record = [[TouchRecord alloc] init];
                record.point = location;
                record.timeIntervalSinceLast = interval;
                
                if (!recordedEvents) recordedEvents = [[NSMutableArray alloc] init];
                [recordedEvents addObject:record];
            }
        }
    }
    %orig(event);
}

- (void)setDelegate:(id)delegate {
    %orig;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!floatingWindow) {
            UIWindowScene *targetScene = nil;
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]]) {
                    targetScene = (UIWindowScene *)scene;
                    break;
                }
            }
            
            if (targetScene) {
                floatingWindow = [[UIWindow alloc] initWithWindowScene:targetScene];
            } else {
                floatingWindow = [[UIWindow alloc] initWithFrame:CGRectMake(50, 100, 290, 60)];
            }
            floatingWindow.frame = CGRectMake(50, 100, 290, 60);
            floatingWindow.windowLevel = UIWindowLevelAlert + 100;
            floatingWindow.rootViewController = [[FloatingController alloc] init];
            [floatingWindow setHidden:NO];
        }
    });
}

%end
