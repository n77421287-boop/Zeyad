#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

// هوك لطبقات الرسوم المتحركة للتحكم بالسرعة العامة لتكون مثل فلكس (9999.0)
%hook CALayer

- (void)setSpeed:(float)speed {
    // فرض سرعة 9999 على أي رسوم متحركة يتم إنشاؤها
    %orig(9999.0f);
}

- (float)speed {
    return 9999.0f;
}

%end

// التأكد من تطبيق السرعة على الواجهات الحالية عند تحميلها
%hook UIView

- (void)didMoveToWindow {
    %orig;
    self.layer.speed = 9999.0f;
}

%end
