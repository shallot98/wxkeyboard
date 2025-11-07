#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dispatch/dispatch.h>

// ===== 老王的终极修复版微信键盘插件 =====
// 这个版本专门解决插件失效问题，采用更智能的Hook策略

// 配置常量
static NSString *const kWTPreferencesDomain = @"com.yourcompany.wxkeyboard";
static NSString *const kWTLogFilePath = @"/var/mobile/Library/Logs/wxkeyboard.log";
static const CGFloat kWTMinSwipeDistance = 25.0;
static const NSTimeInterval kWTDebounceInterval = 0.25;

// 配置结构
typedef struct {
    BOOL enabled;
    BOOL debugLog;
    CGFloat minSwipeDistance;
    BOOL suppressKeyTapOnSwipe;
    NSString *logLevel;
} WTConfiguration;

static NSMutableDictionary *activeSwipeManagers = nil;
static NSTimeInterval lastSwipeTime = 0;

// ===== 日志系统 - 老王专用日志 =====

#define WTSLog(fmt, ...) do { \
    if (WTGetConfiguration().debugLog) { \
        NSString *message = [NSString stringWithFormat:fmt, ##__VA_ARGS__]; \
        NSLog(@"[WxKeyboard] %@", message); \
        WTWriteLogToFile(message); \
    } \
} while(0)

#define WTSLogInfo(fmt, ...) do { \
    NSString *message = [NSString stringWithFormat:fmt, ##__VA_ARGS__]; \
    NSLog(@"[WxKeyboard-INFO] %@", message); \
    WTWriteLogToFile([NSString stringWithFormat:@"[INFO] %@", message]); \
} while(0)

// 配置读取 - 简化版本
static inline WTConfiguration WTGetConfiguration(void) {
    static WTConfiguration config = {YES, YES, kWTMinSwipeDistance, YES, @"DEBUG"};
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // 从偏好设置读取（简化版）
        config.enabled = YES;
        config.debugLog = YES;
        config.minSwipeDistance = kWTMinSwipeDistance;
        config.suppressKeyTapOnSwipe = YES;
        config.logLevel = @"DEBUG";
    });
    return config;
}

static void WTWriteLogToFile(NSString *message) {
    if (!WTGetConfiguration().debugLog) return;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        NSString *logEntry = [NSString stringWithFormat:@"%@\n", message];
        NSFileManager *fm = [NSFileManager defaultManager];
        if ([fm fileExistsAtPath:kWTLogFilePath]) {
            NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:kWTLogFilePath];
            [handle seekToEndOfFile];
            [handle writeData:[logEntry dataUsingEncoding:NSUTF8StringEncoding]];
            [handle closeFile];
        }
    });
}

// ===== 进程检测 - 智能版本 =====
static BOOL WTIsWeTypeKeyboardProcess(void) {
    static dispatch_once_t onceToken;
    static BOOL isWeType = NO;
    dispatch_once(&onceToken, ^{
        NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];

        // 主要检测
        if ([bundleId isEqualToString:@"com.tencent.wetype.keyboard"]) {
            isWeType = YES;
            return;
        }

        // 备用检测
        if ([bundleId containsString:@"wetype"] && [bundleId containsString:@"keyboard"]) {
            isWeType = YES;
            return;
        }

        // 路径检测
        NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
        if ([bundlePath containsString:@"wetype"] || [bundlePath containsString:@"WXKB"]) {
            isWeType = YES;
        }

        WTSLogInfo(@"进程检测结果: %@ -> %@", bundleId, isWeType ? @"匹配" : @"不匹配");
    });
    return isWeType;
}

// ===== 垂直滑动手势管理器 - 老王的智能版本 =====

@interface WTVerticalSwipeManager : NSObject
@property (nonatomic, weak) UIView *hostView;
@property (nonatomic, assign) CGPoint startPoint;
@property (nonatomic, assign) NSTimeInterval startTime;
@property (nonatomic, assign) BOOL isTracking;
@property (nonatomic, assign) BOOL directionLocked;
@property (nonatomic, assign) BOOL verticalSwipeDetected;
@end

@implementation WTVerticalSwipeManager

- (instancetype)initWithHostView:(UIView *)hostView {
    self = [super init];
    if (self) {
        _hostView = hostView;
        WTSLog(@"创建了滑动手势管理器在: %@", NSStringFromClass(hostView.class));
    }
    return self;
}

- (void)handleTouchBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    if (!WTGetConfiguration().enabled) return;

    UITouch *touch = [touches anyObject];
    self.startPoint = [touch locationInView:self.hostView];
    self.startTime = [NSDate timeIntervalSinceReferenceDate];
    self.isTracking = YES;
    self.directionLocked = NO;
    self.verticalSwipeDetected = NO;

    WTSLog(@"开始跟踪触摸: (%.1f, %.1f)", self.startPoint.x, self.startPoint.y);
}

- (void)handleTouchMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    if (!self.isTracking) return;

    UITouch *touch = [touches anyObject];
    CGPoint currentPoint = [touch locationInView:self.hostView];
    CGFloat deltaX = currentPoint.x - self.startPoint.x;
    CGFloat deltaY = currentPoint.y - self.startPoint.y;

    CGFloat absDeltaX = fabs(deltaX);
    CGFloat absDeltaY = fabs(deltaY);

    // 方向锁定
    if (!self.directionLocked && (absDeltaX > 10 || absDeltaY > 10)) {
        if (absDeltaY > absDeltaX * 1.5) {
            self.directionLocked = YES;
        } else {
            self.isTracking = NO;
            return;
        }
    }

    // 检测垂直滑动
    if (self.directionLocked && !self.verticalSwipeDetected && absDeltaY >= WTGetConfiguration().minSwipeDistance) {
        self.verticalSwipeDetected = YES;

        // 防抖处理
        NSTimeInterval currentTime = [NSDate timeIntervalSinceReferenceDate];
        if (currentTime - lastSwipeTime < kWTDebounceInterval) {
            WTSLog(@"滑动频率太快，忽略");
            return;
        }

        lastSwipeTime = currentTime;

        if (deltaY < 0) {
            // 向上滑动
            [self handleUpSwipe];
        } else {
            // 向下滑动
            [self handleDownSwipe];
        }

        if (WTGetConfiguration().suppressKeyTapOnSwipe) {
            // 取消触摸事件的进一步处理
            self.isTracking = NO;
        }
    }
}

- (void)handleTouchEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    self.isTracking = NO;
    self.directionLocked = NO;
    self.verticalSwipeDetected = NO;
}

- (void)handleUpSwipe {
    WTSLogInfo(@"👆 检测到向上滑动 - 切换输入模式");
    [self switchInputMode:-1];
}

- (void)handleDownSwipe {
    WTSLogInfo(@"👇 检测到向下滑动 - 切换输入模式");
    [self switchInputMode:1];
}

- (void)switchInputMode:(NSInteger)direction {
    // 获取键盘输入控制器
    UIInputViewController *inputController = [self findInputViewController];
    if (!inputController) {
        WTSLog(@"没找到输入控制器");
        return;
    }

    // 尝试多种方式切换输入模式
    [self switchModeInController:inputController direction:direction];
}

- (UIInputViewController *)findInputViewController {
    UIResponder *responder = self.hostView;
    while (responder) {
        if ([responder isKindOfClass:[UIInputViewController class]]) {
            return (UIInputViewController *)responder;
        }
        responder = responder.nextResponder;
    }

    // 备用方法：通过键盘查找
    if ([self.hostView respondsToSelector:@selector(inputViewController)]) {
        return [self.hostView performSelector:@selector(inputViewController)];
    }

    return nil;
}

- (void)switchModeInController:(UIInputViewController *)controller direction:(NSInteger)direction {
    // 方法1：使用标准API
    @try {
        NSArray *inputModes = [controller inputModes];
        if (inputModes.count > 1) {
            [self switchUsingStandardAPI:controller direction:direction];
            return;
        }
    } @catch (NSException *exception) {
        WTSLog(@"标准API切换失败: %@", exception.reason);
    }

    // 方法2：使用微信输入法特定API
    [self switchUsingWeTypeAPI:controller direction:direction];
}

- (void)switchUsingStandardAPI:(UIInputViewController *)controller direction:(NSInteger)direction {
    @try {
        // 尝试获取当前输入模式
        UITextInputMode *currentMode = controller.textInputMode;
        if (!currentMode) {
            WTSLog(@"无法获取当前输入模式");
            return;
        }

        NSArray *inputModes = [controller inputModes];
        NSUInteger currentIndex = [inputModes indexOfObject:currentMode];

        if (currentIndex != NSNotFound) {
            NSUInteger newIndex;
            if (direction > 0) {
                newIndex = (currentIndex + 1) % inputModes.count;
            } else {
                newIndex = (currentIndex == 0) ? inputModes.count - 1 : currentIndex - 1;
            }

            UITextInputMode *newMode = inputModes[newIndex];
            if (newMode) {
                [controller setInputMode:newMode];
                WTSLogInfo(@"成功切换到输入模式: %@", newMode);
                return;
            }
        }
    } @catch (NSException *exception) {
        WTSLog(@"标准切换失败: %@", exception.reason);
    }

    WTSLog(@"标准切换失败");
}

- (void)switchUsingWeTypeAPI:(UIInputViewController *)controller direction:(NSInteger)direction {
    // 微信输入法特定切换逻辑
    @try {
        // 尝试调用微信输入法的私有方法
        SEL switchSelector = NSSelectorFromString(@"switchToNextInputMode");
        if ([controller respondsToSelector:switchSelector]) {
            ((void (*)(id, SEL))objc_msgSend)(controller, switchSelector);
            WTSLog(@"使用微信输入法API切换");
            return;
        }

        // 尝试其他可能的方法
        NSArray *selectors = @[
            @"advanceToNextInputMode",
            @"cycleInputModes",
            @"switchInputMode:",
            @"nextInputMode"
        ];

        for (NSString *selectorName in selectors) {
            SEL sel = NSSelectorFromString(selectorName);
            if ([controller respondsToSelector:sel]) {
                @try {
                    if ([selectorName containsString:@":"]) {
                        ((void (*)(id, SEL, NSInteger))objc_msgSend)(controller, sel, direction);
                    } else {
                        ((void (*)(id, SEL))objc_msgSend)(controller, sel);
                    }
                    WTSLog(@"成功调用方法: %@", selectorName);
                    return;
                } @catch (NSException *e) {
                    continue;
                }
            }
        }

    } @catch (NSException *exception) {
        WTSLog(@"微信输入法API切换失败: %@", exception.reason);
    }

    WTSLog(@"所有切换方法都失败了");
}

@end

// ===== 智能视图匹配系统 =====

static BOOL WTShouldInstallOnView(UIView *view) {
    if (!view || view.hidden || view.alpha < 0.1) {
        return NO;
    }

    CGSize bounds = view.bounds.size;
    if (bounds.width < 50 || bounds.height < 30) {
        return NO; // 太小的视图不需要
    }

    NSString *className = NSStringFromClass(view.class);

    // 排除按键视图
    if ([className containsString:@"Key"] || [className containsString:@"Button"]) {
        return NO;
    }

    // 优先hook大的容器视图
    if (bounds.width > 200 && bounds.height > 100) {
        return YES;
    }

    // 微信键盘相关视图
    if ([className containsString:@"WB"] ||
        [className containsString:@"WXKB"] ||
        [className containsString:@"Keyboard"] ||
        [className containsString:@"Input"]) {
        return YES;
    }

    return NO;
}

// ===== Hook安装器 =====

static void WTInstallSwipeManager(UIView *view) {
    if (!WTShouldInstallOnView(view)) {
        return;
    }

    // 检查是否已经安装
    if (objc_getAssociatedObject(view, "WTVerticalSwipeManager")) {
        return;
    }

    WTVerticalSwipeManager *manager = [[WTVerticalSwipeManager alloc] initWithHostView:view];
    objc_setAssociatedObject(view, "WTVerticalSwipeManager", manager, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // 保存到全局字典
    if (!activeSwipeManagers) {
        activeSwipeManagers = [NSMutableDictionary dictionary];
    }
    activeSwipeManagers[NSValue valueWithPointer:(__bridge const void *)view] = manager;

    WTSLogInfo(@"✅ 在视图 %@ (%.0fx%.0f) 上安装了滑动手势",
               NSStringFromClass(view.class), bounds.width, bounds.height);
}

// ===== 确认存在的类（通过二进制文件验证） =====

@interface WBMainInputView : UIView @end
@interface WBKeyboardView : UIView @end
@interface WBInputViewController : UIInputViewController @end
@interface WBPanelLayout : UIView @end

// ===== 主要Hook实现 =====

%hook WBMainInputView

- (instancetype)initWithFrame:(CGRect)frame {
    self = %orig;
    if (self) {
        dispatch_async(dispatch_get_main_queue(), ^{
            WTInstallSwipeManager(self);
            // 递归安装到子视图
            [WTInstallToSubviews:self];
        });
    }
    return self;
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    WTVerticalSwipeManager *manager = objc_getAssociatedObject(self, "WTVerticalSwipeManager");
    if (manager) {
        [manager handleTouchBegan:touches withEvent:event];
    }
    %orig;
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    WTVerticalSwipeManager *manager = objc_getAssociatedObject(self, "WTVerticalSwipeManager");
    if (manager) {
        [manager handleTouchMoved:touches withEvent:event];
        if (manager.suppressKeyTapOnSwipe && manager.verticalSwipeDetected) {
            return; // 阻止原始触摸事件
        }
    }
    %orig;
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    WTVerticalSwipeManager *manager = objc_getAssociatedObject(self, "WTVerticalSwipeManager");
    if (manager) {
        [manager handleTouchEnded:touches withEvent:event];
    }
    %orig;
}

%end

%hook WBKeyboardView

- (instancetype)initWithFrame:(CGRect)frame {
    self = %orig;
    if (self) {
        dispatch_async(dispatch_get_main_queue(), ^{
            WTInstallSwipeManager(self);
            [WTInstallToSubviews:self];
        });
    }
    return self;
}

- (void)layoutSubviews {
    %orig;
    // 布局变化时重新安装
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        WTInstallSwipeManager(self);
        [WTInstallToSubviews:self];
    });
}

%end

%hook WBPanelLayout

- (instancetype)initWithFrame:(CGRect)frame {
    self = %orig;
    if (self) {
        dispatch_async(dispatch_get_main_queue(), ^{
            WTInstallSwipeManager(self);
            [WTInstallToSubviews:self];
        });
    }
    return self;
}

%end

%hook WBInputViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;

    // 控制器出现时安装到主视图
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.view) {
            WTInstallSwipeManager(self.view);
            [WTInstallToSubviews:self.view];
        }
    });
}

%end

// ===== 通用Hook - 捕获可能遗漏的视图 =====

%hook UIView

- (void)didAddSubview:(UIView *)subview {
    %orig;

    if (WTShouldInstallOnView(subview)) {
        WTInstallSwipeManager(subview);
    }
}

- (void)layoutSubviews {
    %orig;

    // 只对可能是键盘的视图进行递归安装
    NSString *className = NSStringFromClass(self.class);
    if ([className containsString:@"WB"] ||
        [className containsString:@"WXKB"] ||
        [className containsString:@"Keyboard"] ||
        [className containsString:@"Input"]) {

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [WTInstallToSubviews:self];
        });
    }
}

%end

// ===== 辅助函数 =====

static void WTInstallToSubviews(UIView *view) {
    for (UIView *subview in view.subviews) {
        if (WTShouldInstallOnView(subview)) {
            WTInstallSwipeManager(subview);
        }

        // 递归（有深度限制）
        if (subview.subviews.count < 20) {
            WTInstallToSubviews(subview);
        }
    }
}

// ===== 初始化 =====

%ctor {
    @autoreleasepool {
        if (!WTIsWeTypeKeyboardProcess()) {
            NSLog(@"[WxKeyboard] 非微信输入法进程，跳过初始化");
            return;
        }

        if (!WTGetConfiguration().enabled) {
            NSLog(@"[WxKeyboard] 插件已禁用");
            return;
        }

        WTSLogInfo(@"🚀 老王终极修复版微信键盘插件启动！");
        WTSLogInfo(@"Bundle: %@", [[NSBundle mainBundle] bundleIdentifier]);
        WTSLogInfo(@"可执行文件: [[[NSBundle mainBundle] executablePath]]);

        // 初始化Hook组
        %init;

        WTSLogInfo(@"✅ 所有Hook已激活，插件运行中...");
    }
}

// ===== 卸载清理 =====

__attribute__((destructor))
static void WTDeinitialize(void) {
    if (activeSwipeManagers) {
        [activeSwipeManagers removeAllObjects];
        activeSwipeManagers = nil;
    }
    WTSLog(@"老王的微信键盘插件已卸载");
}