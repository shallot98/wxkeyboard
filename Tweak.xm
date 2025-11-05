#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dispatch/dispatch.h>
#include <math.h>
#include <stdlib.h>
#include <strings.h>

static const CGFloat kWTVerticalTranslationThreshold = 22.0;
static const CGFloat kWTHorizontalTranslationTolerance = 12.0;
static const CGFloat kWTMaximumAngleDegrees = 20.0;

static BOOL WTSLoggingEnabled(void) {
    static dispatch_once_t onceToken;
    static BOOL enabled = NO;
    dispatch_once(&onceToken, ^{
#ifdef DEBUG
        enabled = YES;
#else
        const char *env = getenv("WETYPE_SWIPE_DEBUG");
        if (env != NULL && (strcmp(env, "1") == 0 || strcasecmp(env, "true") == 0)) {
            enabled = YES;
        }
#endif
    });
    return enabled;
}

#define WTSLog(fmt, ...) do { if (WTSLoggingEnabled()) NSLog(@"[WeTypeSwipe] " fmt, ##__VA_ARGS__); } while (0)

static inline BOOL WTSLanguageStringIsChinese(NSString *language) {
    if (language.length == 0) {
        return NO;
    }
    NSString *lower = language.lowercaseString;
    if ([lower hasPrefix:@"zh"]) {
        return YES;
    }
    if ([lower containsString:@"pinyin"] || [lower containsString:@"zh-hans"] || [lower containsString:@"zh-hant"] || [lower containsString:@"chinese"]) {
        return YES;
    }
    if ([lower containsString:@"wetype"] && [lower containsString:@"zh"]) {
        return YES;
    }
    return NO;
}

static inline BOOL WTSLanguageStringIsEnglish(NSString *language) {
    if (language.length == 0) {
        return NO;
    }
    NSString *lower = language.lowercaseString;
    if ([lower hasPrefix:@"en"]) {
        return YES;
    }
    if ([lower containsString:@"english"]) {
        return YES;
    }
    if ([lower containsString:@"us"] && [lower containsString:@"wetype"]) {
        return YES;
    }
    return NO;
}

static inline NSString *WTSPrimaryLanguageFromMode(id mode) {
    if (!mode) {
        return nil;
    }
    SEL primarySel = NSSelectorFromString(@"primaryLanguage");
    if ([mode respondsToSelector:primarySel]) {
        NSString *language = ((NSString *(*)(id, SEL))objc_msgSend)(mode, primarySel);
        if (language.length > 0) {
            return language;
        }
    }
    SEL identifierSel = NSSelectorFromString(@"identifier");
    if ([mode respondsToSelector:identifierSel]) {
        NSString *identifier = ((NSString *(*)(id, SEL))objc_msgSend)(mode, identifierSel);
        if (identifier.length > 0) {
            return identifier;
        }
    }
    return nil;
}

static BOOL gLanguageStateKnown = NO;
static BOOL gLanguageStateIsChinese = NO;

static void WTSUpdateLanguageStateWithMode(id mode) {
    NSString *language = WTSPrimaryLanguageFromMode(mode);
    if (language.length > 0) {
        gLanguageStateKnown = YES;
        gLanguageStateIsChinese = WTSLanguageStringIsChinese(language);
        WTSLog(@"Tracked language state -> %@", language);
    }
}

static BOOL WTSIsApproxVertical(CGPoint translation) {
    CGFloat dy = fabs(translation.y);
    CGFloat dx = fabs(translation.x);
    if (dy < kWTVerticalTranslationThreshold) {
        return NO;
    }
    if (dx > kWTHorizontalTranslationTolerance) {
        return NO;
    }
    if (dy == 0.0) {
        return NO;
    }
    CGFloat angle = (CGFloat)(atan2(dx, dy) * (180.0 / M_PI));
    return angle <= kWTMaximumAngleDegrees;
}

static BOOL WTSClassNameMatchesHints(NSString *className) {
    if (className.length == 0) {
        return NO;
    }
    static NSArray<NSString *> *hints;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        hints = @[
            @"Candidate",
            @"Suggestion",
            @"Toolbar",
            @"ToolBar",
            @"Function",
            @"Ribbon",
            @"Shortcut",
            @"Prediction",
            @"Accessory",
            @"TopBar"
        ];
    });
    for (NSString *hint in hints) {
        if ([className rangeOfString:hint options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return YES;
        }
    }
    return NO;
}

static BOOL WTSViewShouldDisableSwipe(UIView *view, UIView *hostView) {
    if (!view || !hostView) {
        return NO;
    }
    NSString *className = NSStringFromClass(view.class);
    if (WTSClassNameMatchesHints(className)) {
        return YES;
    }
    if ([view isKindOfClass:[UICollectionView class]] || [view isKindOfClass:[UITableView class]]) {
        CGRect frame = [view convertRect:view.bounds toView:hostView];
        if (CGRectGetMinY(frame) <= CGRectGetHeight(hostView.bounds) * 0.45f) {
            return YES;
        }
    }
    return NO;
}

static void WTSAccumulateDisabledRegion(UIView *current, UIView *hostView, CGFloat *maxY) {
    if (!current || !hostView || !maxY) {
        return;
    }
    if (current != hostView && WTSViewShouldDisableSwipe(current, hostView)) {
        CGRect frame = [current convertRect:current.bounds toView:hostView];
        *maxY = MAX(*maxY, CGRectGetMaxY(frame));
    }
    for (UIView *subview in current.subviews) {
        WTSAccumulateDisabledRegion(subview, hostView, maxY);
    }
}

static CGFloat WTSDisabledRegionMaxY(UIView *hostView) {
    if (!hostView) {
        return 0.0;
    }
    CGFloat maxY = 0.0;
    WTSAccumulateDisabledRegion(hostView, hostView, &maxY);
    return MIN(maxY, CGRectGetHeight(hostView.bounds));
}

static BOOL WTSTouchViewIsDisabled(UIView *touchView, UIView *hostView) {
    UIView *current = touchView;
    while (current && current != hostView) {
        if (WTSViewShouldDisableSwipe(current, hostView)) {
            return YES;
        }
        current = current.superview;
    }
    return NO;
}

static id WTSCurrentInputMode(UIInputViewController *controller) {
    if (!controller) {
        return nil;
    }
    SEL textInputModeSel = NSSelectorFromString(@"textInputMode");
    if ([controller respondsToSelector:textInputModeSel]) {
        id mode = ((id (*)(id, SEL))objc_msgSend)(controller, textInputModeSel);
        if (mode) {
            return mode;
        }
    }
    @try {
        id mode = [controller valueForKey:@"_currentInputMode"];
        if (mode) {
            return mode;
        }
    } @catch (__unused NSException *exception) {
    }
    SEL inputModeSel = NSSelectorFromString(@"inputMode");
    if ([controller respondsToSelector:inputModeSel]) {
        id mode = ((id (*)(id, SEL))objc_msgSend)(controller, inputModeSel);
        if (mode) {
            return mode;
        }
    }
    return nil;
}

@interface WTLanguageSwipeManager : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UIView *hostView;
@property (nonatomic, strong) UIPanGestureRecognizer *panRecognizer;
@property (nonatomic, assign) CGPoint initialLocation;
@property (nonatomic, weak) UIView *initialTouchView;
@property (nonatomic, assign) BOOL didTrigger;
@property (nonatomic, assign) CGFloat disabledLimit;
@end

@implementation WTLanguageSwipeManager

- (instancetype)initWithHostView:(UIView *)hostView {
    self = [super init];
    if (self) {
        _hostView = hostView;
        _panRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        _panRecognizer.maximumNumberOfTouches = 1;
        _panRecognizer.minimumNumberOfTouches = 1;
        _panRecognizer.cancelsTouchesInView = YES;
        _panRecognizer.delaysTouchesBegan = NO;
        _panRecognizer.delegate = self;
        [hostView addGestureRecognizer:_panRecognizer];
        _disabledLimit = 0.0;
        WTSLog(@"Gesture recognizer installed on %@", hostView);
    }
    return self;
}

- (void)dealloc {
    if (_panRecognizer) {
        [_hostView removeGestureRecognizer:_panRecognizer];
    }
}

- (void)refreshDisabledLimit {
    CGFloat maxY = WTSDisabledRegionMaxY(self.hostView);
    self.disabledLimit = maxY > 0.0 ? maxY : 0.0;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if (!self.hostView) {
        return NO;
    }
    [self refreshDisabledLimit];
    CGPoint location = [touch locationInView:self.hostView];
    self.initialLocation = location;
    self.initialTouchView = touch.view;
    BOOL disabled = NO;
    if (self.disabledLimit > 0.0 && location.y <= self.disabledLimit) {
        disabled = YES;
    }
    if (!disabled && WTSTouchViewIsDisabled(touch.view, self.hostView)) {
        disabled = YES;
    }
    if (disabled) {
        WTSLog(@"Ignoring touch in disabled zone (%@) limit=%.2f", touch.view, self.disabledLimit);
        return NO;
    }
    self.didTrigger = NO;
    return YES;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (!self.hostView) {
        return NO;
    }
    UIPanGestureRecognizer *pan = (UIPanGestureRecognizer *)gestureRecognizer;
    CGPoint velocity = [pan velocityInView:self.hostView];
    if (fabs(velocity.y) <= fabs(velocity.x)) {
        return NO;
    }
    if (self.disabledLimit > 0.0 && self.initialLocation.y <= self.disabledLimit) {
        return NO;
    }
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return NO;
}

- (void)handlePan:(UIPanGestureRecognizer *)recognizer {
    if (!self.hostView) {
        return;
    }
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        self.initialLocation = [recognizer locationInView:self.hostView];
        self.initialTouchView = recognizer.view;
        self.didTrigger = NO;
        WTSLog(@"Pan began in %@ at %@", self.hostView, NSStringFromCGPoint(self.initialLocation));
        return;
    }

    if (!self.didTrigger && (recognizer.state == UIGestureRecognizerStateChanged || recognizer.state == UIGestureRecognizerStateEnded)) {
        CGPoint translation = [recognizer translationInView:self.hostView];
        if (WTSIsApproxVertical(translation)) {
            WTSLog(@"Detected vertical swipe translation %@", NSStringFromCGPoint(translation));
            if ([[self class] triggerToggleForHostView:self.hostView]) {
                self.didTrigger = YES;
                [recognizer setTranslation:CGPointZero inView:self.hostView];
            }
        }
    }

    if (recognizer.state == UIGestureRecognizerStateCancelled ||
        recognizer.state == UIGestureRecognizerStateFailed ||
        recognizer.state == UIGestureRecognizerStateEnded) {
        if (self.didTrigger) {
            WTSLog(@"Pan finished after toggle");
        }
        self.didTrigger = NO;
        self.initialTouchView = nil;
    }
}

+ (UIInputViewController *)inputControllerForResponder:(UIResponder *)responder {
    UIResponder *current = responder;
    while (current) {
        if ([current isKindOfClass:[UIInputViewController class]]) {
            return (UIInputViewController *)current;
        }
        current = current.nextResponder;
    }
    return nil;
}

+ (BOOL)tryToggleUsingWeTypeAPI:(UIInputViewController *)controller {
    if (!controller) {
        return NO;
    }
    Class weTypeControllerClass = NSClassFromString(@"WBInputViewController");
    if (weTypeControllerClass && ![controller isKindOfClass:weTypeControllerClass]) {
        return NO;
    }

    NSArray<NSString *> *controllerSelectors = @[
        @"toggleLanguage",
        @"toggleLanguageMode",
        @"toggleKeyboardLanguage",
        @"toggleLanguageAction:",
        @"languageSwitchAction:",
        @"switchLanguage:",
        @"switchLanguageAction:",
        @"toggleToNextLanguage",
        @"handleLanguageSwitch:"
    ];

    for (NSString *selectorName in controllerSelectors) {
        SEL selector = NSSelectorFromString(selectorName);
        if ([controller respondsToSelector:selector]) {
            WTSLog(@"Invoking WeType selector %@", selectorName);
            if ([selectorName hasSuffix:@":"]) {
                ((void (*)(id, SEL, id))objc_msgSend)(controller, selector, nil);
            } else {
                ((void (*)(id, SEL))objc_msgSend)(controller, selector);
            }
            return YES;
        }
    }

    SEL switchButtonSel = NSSelectorFromString(@"languageSwitchButton");
    if ([controller respondsToSelector:switchButtonSel]) {
        id button = ((id (*)(id, SEL))objc_msgSend)(controller, switchButtonSel);
        if ([button isKindOfClass:[UIControl class]]) {
            WTSLog(@"Sending UIControl event to language switch button");
            [button sendActionsForControlEvents:UIControlEventTouchUpInside];
            return YES;
        }
    }

    SEL managerSel = NSSelectorFromString(@"languageManager");
    if ([controller respondsToSelector:managerSel]) {
        id manager = ((id (*)(id, SEL))objc_msgSend)(controller, managerSel);
        if (manager) {
            NSArray<NSString *> *managerSelectors = @[
                @"toggleLanguage",
                @"toggleLanguageMode",
                @"toggleCurrentLanguage",
                @"toggleLanguageType:",
                @"switchLanguage",
                @"switchLanguage:"
            ];
            for (NSString *selectorName in managerSelectors) {
                SEL selector = NSSelectorFromString(selectorName);
                if ([manager respondsToSelector:selector]) {
                    WTSLog(@"Invoking manager selector %@", selectorName);
                    if ([selectorName hasSuffix:@":"]) {
                        ((void (*)(id, SEL, id))objc_msgSend)(manager, selector, nil);
                    } else {
                        ((void (*)(id, SEL))objc_msgSend)(manager, selector);
                    }
                    return YES;
                }
            }
        }
    }

    return NO;
}

+ (BOOL)tryToggleUsingInputModes:(UIInputViewController *)controller {
    if (!controller || ![controller respondsToSelector:@selector(inputModes)]) {
        return NO;
    }
    NSArray *inputModes = [controller inputModes];
    if (inputModes.count == 0) {
        return NO;
    }

    id currentMode = WTSCurrentInputMode(controller);
    if (currentMode) {
        WTSUpdateLanguageStateWithMode(currentMode);
    }

    id chineseMode = nil;
    id englishMode = nil;

    for (id mode in inputModes) {
        NSString *language = WTSPrimaryLanguageFromMode(mode);
        if (WTSLanguageStringIsChinese(language)) {
            if (!chineseMode) {
                chineseMode = mode;
            }
        } else if (WTSLanguageStringIsEnglish(language)) {
            if (!englishMode) {
                englishMode = mode;
            }
        }
    }

    id targetMode = nil;
    if (gLanguageStateKnown) {
        targetMode = gLanguageStateIsChinese ? englishMode : chineseMode;
    } else if (currentMode) {
        NSString *currentLanguage = WTSPrimaryLanguageFromMode(currentMode);
        if (WTSLanguageStringIsChinese(currentLanguage) && englishMode) {
            targetMode = englishMode;
        } else if (WTSLanguageStringIsEnglish(currentLanguage) && chineseMode) {
            targetMode = chineseMode;
        }
    }

    if (!targetMode) {
        if (currentMode == chineseMode && englishMode) {
            targetMode = englishMode;
        } else if (currentMode == englishMode && chineseMode) {
            targetMode = chineseMode;
        }
    }

    if (!targetMode) {
        for (id mode in inputModes) {
            if (mode != currentMode) {
                targetMode = mode;
                break;
            }
        }
    }

    if (!targetMode) {
        return NO;
    }

    SEL setInputModeSel = @selector(setInputMode:);
    if ([controller respondsToSelector:setInputModeSel]) {
        ((void (*)(id, SEL, id))objc_msgSend)(controller, setInputModeSel, targetMode);
        WTSUpdateLanguageStateWithMode(targetMode);
        WTSLog(@"Switched language via setInputMode:");
        return YES;
    }

    return NO;
}

+ (BOOL)fallbackToggleWithController:(UIInputViewController *)controller {
    if (!controller || ![controller respondsToSelector:@selector(inputModes)]) {
        return NO;
    }
    NSArray *inputModes = [controller inputModes];
    if (inputModes.count < 2) {
        return NO;
    }
    static NSInteger fallbackIndex = 0;
    fallbackIndex = (fallbackIndex + 1) % inputModes.count;
    id targetMode = inputModes[fallbackIndex];
    SEL setInputModeSel = @selector(setInputMode:);
    if ([controller respondsToSelector:setInputModeSel]) {
        ((void (*)(id, SEL, id))objc_msgSend)(controller, setInputModeSel, targetMode);
        WTSUpdateLanguageStateWithMode(targetMode);
        WTSLog(@"Fallback toggled language using rotating index %ld", (long)fallbackIndex);
        return YES;
    }
    return NO;
}

+ (BOOL)triggerToggleForHostView:(UIView *)hostView {
    if (!hostView) {
        return NO;
    }
    UIInputViewController *controller = [self inputControllerForResponder:hostView];
    if (!controller) {
        controller = [self inputControllerForResponder:hostView.nextResponder];
    }
    if (!controller) {
        WTSLog(@"No input controller found for %@", hostView);
        return NO;
    }

    id beforeMode = WTSCurrentInputMode(controller);
    if (beforeMode) {
        WTSUpdateLanguageStateWithMode(beforeMode);
    }

    if ([self tryToggleUsingWeTypeAPI:controller]) {
        id afterMode = WTSCurrentInputMode(controller);
        if (afterMode) {
            WTSUpdateLanguageStateWithMode(afterMode);
        } else if (gLanguageStateKnown) {
            gLanguageStateIsChinese = !gLanguageStateIsChinese;
        }
        return YES;
    }

    if ([self tryToggleUsingInputModes:controller]) {
        return YES;
    }

    return [self fallbackToggleWithController:controller];
}

@end

static const void *kWTSwipeHandlerKey = &kWTSwipeHandlerKey;

static void WTSInstallSwipeIfNeeded(UIView *view) {
    if (!view) {
        return;
    }
    if (objc_getAssociatedObject(view, kWTSwipeHandlerKey) != nil) {
        return;
    }
    WTLanguageSwipeManager *manager = [[WTLanguageSwipeManager alloc] initWithHostView:view];
    objc_setAssociatedObject(view, kWTSwipeHandlerKey, manager, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@interface WBMainInputView : UIView @end
@interface WBKeyboardView : UIView @end
@interface WBInputViewController : UIInputViewController @end

%hook WBMainInputView
- (void)didMoveToWindow {
    %orig;
    WTSInstallSwipeIfNeeded(self);
}

- (void)layoutSubviews {
    %orig;
    WTSInstallSwipeIfNeeded(self);
}
%end

%hook WBKeyboardView
- (void)didMoveToWindow {
    %orig;
    WTSInstallSwipeIfNeeded(self);
}

- (void)layoutSubviews {
    %orig;
    WTSInstallSwipeIfNeeded(self);
}
%end

%hook WBInputViewController
- (void)viewDidLoad {
    %orig;
    WTSInstallSwipeIfNeeded(self.view);
}

- (void)viewDidLayoutSubviews {
    %orig;
    WTSInstallSwipeIfNeeded(self.view);
}
%end
