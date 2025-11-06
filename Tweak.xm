#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dispatch/dispatch.h>
#import <mach-o/dyld.h>
#include <math.h>
#include <stdlib.h>
#include <strings.h>
#include <string.h>
#include <limits.h>
#include <sys/stat.h>
#include <unistd.h>
#include <stdarg.h>

@interface UIInputViewController (Private)
- (NSArray *)inputModes;
@end

@interface UIKeyboardImpl : NSObject
- (void)activate;
- (void)setInputMode:(id)mode;
- (NSArray *)inputModes;
- (id)textInputMode;
@end

static const CGFloat kWTVerticalTranslationThreshold = 25.0;
static const CGFloat kWTHorizontalTranslationTolerance = 12.0;

static NSString *const kWTPreferencesDomain = @"com.yourcompany.wxkeyboard";
static NSString *const kWTLogFilePath = @"/var/mobile/Library/Preferences/wxkeyboard.log";
static NSString *const kWTLogFileBackupPath = @"/var/mobile/Library/Preferences/wxkeyboard.log.1";
static const NSUInteger kWTLogRotateThresholdBytes = 256 * 1024;

typedef struct {
    BOOL enabled;
    BOOL debugLog;
    BOOL regionSwipe;
    BOOL globalSwipeEnabled;
    CGFloat swipeThreshold;
    BOOL nineKeyEnabled;
    BOOL numberKeyEnabled;
    BOOL spacebarEnabled;
} WTConfiguration;

static BOOL WTInterpretBoolFromObject(id value, BOOL defaultValue) {
    if (!value || value == [NSNull null]) {
        return defaultValue;
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        return ((NSNumber *)value).boolValue;
    }
    if ([value isKindOfClass:[NSString class]]) {
        NSString *lower = [(NSString *)value lowercaseString];
        if ([lower isEqualToString:@"1"] || [lower isEqualToString:@"true"] || [lower isEqualToString:@"yes"] || [lower isEqualToString:@"enabled"]) {
            return YES;
        }
        if ([lower isEqualToString:@"0"] || [lower isEqualToString:@"false"] || [lower isEqualToString:@"no"] || [lower isEqualToString:@"disabled"]) {
            return NO;
        }
    }
    return defaultValue;
}

static BOOL WTReadPreferenceBool(NSString *key, BOOL defaultValue) {
    BOOL result = defaultValue;
    CFPropertyListRef valueRef = CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)kWTPreferencesDomain);
    if (valueRef) {
        id value = CFBridgingRelease(valueRef);
        result = WTInterpretBoolFromObject(value, defaultValue);
    } else {
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:kWTPreferencesDomain];
        if (defaults) {
            id value = [defaults objectForKey:key];
            if (value) {
                result = WTInterpretBoolFromObject(value, defaultValue);
            }
        }
    }
    return result;
}

static CGFloat WTReadPreferenceFloat(NSString *key, CGFloat defaultValue) {
    CGFloat result = defaultValue;
    CFPropertyListRef valueRef = CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)kWTPreferencesDomain);
    if (valueRef) {
        id value = CFBridgingRelease(valueRef);
        if ([value isKindOfClass:[NSNumber class]]) {
            result = ((NSNumber *)value).floatValue;
        }
    } else {
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:kWTPreferencesDomain];
        if (defaults) {
            id value = [defaults objectForKey:key];
            if (value && [value isKindOfClass:[NSNumber class]]) {
                result = ((NSNumber *)value).floatValue;
            }
        }
    }
    return result;
}

static const WTConfiguration *WTCurrentConfiguration(void) {
    static dispatch_once_t onceToken;
    static WTConfiguration configuration;
    dispatch_once(&onceToken, ^{
        configuration.enabled = WTReadPreferenceBool(@"Enabled", YES);
        configuration.debugLog = WTReadPreferenceBool(@"DebugLog", YES);
        configuration.regionSwipe = WTReadPreferenceBool(@"RegionSwipe", YES);
        configuration.globalSwipeEnabled = WTReadPreferenceBool(@"GlobalSwipe", YES);
        configuration.swipeThreshold = WTReadPreferenceFloat(@"SwipeThreshold", 25.0);
        configuration.nineKeyEnabled = WTReadPreferenceBool(@"NineKeyEnabled", YES);
        configuration.numberKeyEnabled = WTReadPreferenceBool(@"NumberKeyEnabled", YES);
        configuration.spacebarEnabled = WTReadPreferenceBool(@"SpacebarEnabled", YES);
    });
    return &configuration;
}

static inline BOOL WTFeatureEnabled(void) {
    return WTCurrentConfiguration()->enabled;
}

static inline BOOL WTDebugLogEnabled(void) {
    return WTCurrentConfiguration()->debugLog;
}

static NSString *WTCurrentBundleIdentifier(void) {
    NSString *bundleIdentifier = [NSBundle mainBundle].bundleIdentifier;
    return bundleIdentifier.length > 0 ? bundleIdentifier : @"";
}

static NSString *WTExecutablePath(void) {
    uint32_t bufferSize = PATH_MAX;
    char pathBuffer[PATH_MAX];
    if (_NSGetExecutablePath(pathBuffer, &bufferSize) == 0) {
        return [[NSFileManager defaultManager] stringWithFileSystemRepresentation:pathBuffer length:strlen(pathBuffer)];
    }

    NSMutableData *data = [NSMutableData dataWithLength:bufferSize];
    if (_NSGetExecutablePath((char *)data.mutableBytes, &bufferSize) == 0) {
        char *mutablePath = (char *)data.mutableBytes;
        return [[NSFileManager defaultManager] stringWithFileSystemRepresentation:mutablePath length:strlen(mutablePath)];
    }

    NSArray<NSString *> *arguments = [NSProcessInfo processInfo].arguments;
    if (arguments.count > 0) {
        return arguments[0];
    }
    return @"";
}

static NSString *WTExecutableName(void) {
    NSString *path = WTExecutablePath();
    NSString *lastComponent = path.lastPathComponent;
    if (lastComponent.length > 0) {
        return lastComponent;
    }
    NSString *processName = [[NSProcessInfo processInfo] processName];
    return processName.length > 0 ? processName : @"";
}

static NSString *WTProcessName(void) {
    NSString *processName = [[NSProcessInfo processInfo] processName];
    if (processName.length > 0) {
        return processName;
    }
    return WTExecutableName();
}

static NSString *WTTimestampString(void) {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.timeZone = [NSTimeZone localTimeZone];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    });
    return [formatter stringFromDate:[NSDate date]];
}

static void WTEnsureLogDirectoryExists(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *directory = [kWTLogFilePath stringByDeletingLastPathComponent];
        [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    });
}

static void WTRotateLogIfNeeded(NSFileManager *fileManager) {
    NSError *error = nil;
    NSDictionary<NSFileAttributeKey, id> *attributes = [fileManager attributesOfItemAtPath:kWTLogFilePath error:&error];
    if (!attributes) {
        return;
    }
    NSNumber *fileSizeNumber = attributes[NSFileSize];
    if (!fileSizeNumber) {
        return;
    }
    unsigned long long fileSize = fileSizeNumber.unsignedLongLongValue;
    if (fileSize >= kWTLogRotateThresholdBytes) {
        [fileManager removeItemAtPath:kWTLogFileBackupPath error:nil];
        [fileManager moveItemAtPath:kWTLogFilePath toPath:kWTLogFileBackupPath error:nil];
    }
}

static void WTWriteDebugLogLine(NSString *message) {
    if (!WTDebugLogEnabled()) {
        return;
    }
    NSString *timestamp = WTTimestampString();
    NSString *processName = WTProcessName();
    NSString *executableName = WTExecutableName();
    NSString *executablePath = WTExecutablePath();
    NSString *bundleIdentifier = WTCurrentBundleIdentifier();
    NSString *line = [NSString stringWithFormat:@"%@ pid=%d proc=%@ exec=%@ (%@) bundle=%@ -- %@",
                      timestamp,
                      getpid(),
                      processName.length > 0 ? processName : @"<unknown>",
                      executableName.length > 0 ? executableName : @"<unknown>",
                      executablePath.length > 0 ? executablePath : @"<unknown>",
                      bundleIdentifier.length > 0 ? bundleIdentifier : @"<none>",
                      message ?: @"<no message>"];
    WTEnsureLogDirectoryExists();
    NSFileManager *fileManager = [NSFileManager defaultManager];
    WTRotateLogIfNeeded(fileManager);
    if (![fileManager fileExistsAtPath:kWTLogFilePath]) {
        [fileManager createFileAtPath:kWTLogFilePath contents:nil attributes:@{ NSFilePosixPermissions: @(0644) }];
    }
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:kWTLogFilePath];
    if (handle) {
        @try {
            [handle seekToEndOfFile];
            NSData *data = [[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
            [handle writeData:data];
        } @catch (__unused NSException *exception) {
        } @finally {
            [handle closeFile];
        }
    }
    NSLog(@"[wxkeyboard] %@", line);
}

static void WTSLog(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);
static void WTSLog(NSString *format, ...) {
    if (!WTDebugLogEnabled()) {
        return;
    }
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    WTWriteDebugLogLine(message);
}

static void WTLogLaunchDiagnostics(void) {
    if (!WTDebugLogEnabled()) {
        return;
    }
    const WTConfiguration *configuration = WTCurrentConfiguration();
    NSString *bundleIdentifier = WTCurrentBundleIdentifier();
    NSString *bundlePath = [NSBundle mainBundle].bundlePath ?: @"";
    NSString *execPath = WTExecutablePath();
    NSString *processName = WTProcessName();
    WTSLog(@"================================================================================");
    WTSLog(@"WeType Vertical Swipe Toggle v1.0.1 - Launch Diagnostics");
    WTSLog(@"================================================================================");
    WTSLog(@"Tweak Configuration:");
    WTSLog(@"  - Enabled: %@", configuration->enabled ? @"YES" : @"NO");
    WTSLog(@"  - Debug Logging: %@ (ALWAYS ENABLED in v1.0.1+)", configuration->debugLog ? @"YES" : @"NO");
    WTSLog(@"  - Global Swipe: %@", configuration->globalSwipeEnabled ? @"YES" : @"NO");
    WTSLog(@"  - Region Swipe: %@ (IGNORED in v1.0.1 - always CN/EN toggle)", configuration->regionSwipe ? @"YES" : @"NO");
    WTSLog(@"  - Swipe Threshold: %.1f", configuration->swipeThreshold);
    WTSLog(@"  - NineKey Enabled: %@ (LEGACY)", configuration->nineKeyEnabled ? @"YES" : @"NO");
    WTSLog(@"  - NumberKey Enabled: %@ (LEGACY)", configuration->numberKeyEnabled ? @"YES" : @"NO");
    WTSLog(@"  - Spacebar Enabled: %@ (LEGACY)", configuration->spacebarEnabled ? @"YES" : @"NO");
    WTSLog(@"Process Information:");
    WTSLog(@"  - Process Name: %@", processName.length > 0 ? processName : @"<unknown>");
    WTSLog(@"  - Bundle ID: %@", bundleIdentifier.length > 0 ? bundleIdentifier : @"<none>");
    WTSLog(@"  - Bundle Path: %@", bundlePath.length > 0 ? bundlePath : @"<unknown>");
    WTSLog(@"  - Executable: %@", execPath.length > 0 ? execPath : @"<unknown>");
    WTSLog(@"Behavior Changes in v1.0.1:");
    WTSLog(@"  - Swipe ANYWHERE (except top taskbar) now switches CN/EN keyboards ONLY");
    WTSLog(@"  - Gesture has HIGHEST priority (cancelsTouchesInView=YES)");
    WTSLog(@"  - Region-based actions (number/symbol keyboards) are DISABLED");
    WTSLog(@"  - Logging enabled in RELEASE builds for better debugging");
    WTSLog(@"================================================================================");
}

#ifdef DEBUG
static BOOL WTProcessExecutableMatchesDebugFallback(NSString *executableName) {
    if (executableName.length == 0) {
        return NO;
    }
    NSString *lowercase = executableName.lowercaseString;
    if ([lowercase hasPrefix:@"uikitapplication:com.tencent.wetype"]) {
        return YES;
    }
    if ([lowercase containsString:@"wetypekeyboard"]) {
        return YES;
    }
    if ([lowercase containsString:@"wetype"] && [lowercase containsString:@"keyboard"]) {
        return YES;
    }
    return NO;
}
#endif

static BOOL WTShouldInstallForCurrentProcess(void) {
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *bundleIdentifier = WTCurrentBundleIdentifier();
    NSString *bundlePath = bundle.bundlePath ?: @"";
    BOOL isKeyboardCandidate = NO;

    if (bundleIdentifier.length > 0) {
        if ([bundleIdentifier isEqualToString:@"com.tencent.wetype.keyboard"]) {
            isKeyboardCandidate = YES;
        } else if ([bundleIdentifier hasPrefix:@"com.tencent.wetype"] &&
                   [bundleIdentifier rangeOfString:@"keyboard" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            isKeyboardCandidate = YES;
        }
    }

    if (!isKeyboardCandidate) {
        if ([bundlePath rangeOfString:@".appex" options:NSCaseInsensitiveSearch].location != NSNotFound &&
            [bundlePath rangeOfString:@"wetype" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            isKeyboardCandidate = YES;
        }
    }

    BOOL useDebugFallback = NO;
#ifdef DEBUG
    if (!isKeyboardCandidate) {
        NSString *executableName = WTExecutableName();
        if (WTProcessExecutableMatchesDebugFallback(executableName)) {
            useDebugFallback = YES;
        } else if (bundleIdentifier.length > 0 &&
                   [bundleIdentifier hasPrefix:@"com.tencent.wetype"]) {
            useDebugFallback = YES;
        }
    }
#endif

    if (WTDebugLogEnabled()) {
        WTSLog(@"Process match evaluation: bundle=%@ bundlePath=%@ keyboardCandidate=%@ debugFallback=%@",
               bundleIdentifier.length > 0 ? bundleIdentifier : @"<none>",
               bundlePath.length > 0 ? bundlePath : @"<unknown>",
               isKeyboardCandidate ? @"YES" : @"NO",
               useDebugFallback ? @"YES" : @"NO");
    }

#ifdef DEBUG
    if (useDebugFallback) {
        return YES;
    }
#endif
    return isKeyboardCandidate;
}

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

static BOOL gWTKeyboardImplDiagnosticsLogged = NO;
static BOOL gWTVoiceOverSuppressedLogged = NO;

static void WTMaybeEmitKeyboardImplDiagnostics(id keyboardImpl, NSString *entryPoint, id mode) {
    if (!WTDebugLogEnabled() || gWTKeyboardImplDiagnosticsLogged) {
        return;
    }

    NSArray *inputModes = nil;
    SEL inputModesSel = NSSelectorFromString(@"inputModes");
    if ([keyboardImpl respondsToSelector:inputModesSel]) {
        inputModes = ((NSArray *(*)(id, SEL))objc_msgSend)(keyboardImpl, inputModesSel);
    }

    if (inputModes.count == 0 && mode == nil) {
        return;
    }

    gWTKeyboardImplDiagnosticsLogged = YES;

    NSMutableArray<NSString *> *modeSummaries = [NSMutableArray array];
    for (id candidate in inputModes) {
        NSString *summary = WTSPrimaryLanguageFromMode(candidate);
        if (summary.length == 0) {
            summary = [candidate description];
        }
        if (summary.length == 0) {
            summary = @"<unknown>";
        }
        [modeSummaries addObject:summary];
    }

    NSString *currentSummary = nil;
    if (mode) {
        currentSummary = WTSPrimaryLanguageFromMode(mode);
        if (currentSummary.length == 0) {
            currentSummary = [mode description];
        }
    } else {
        SEL textInputModeSel = NSSelectorFromString(@"textInputMode");
        if ([keyboardImpl respondsToSelector:textInputModeSel]) {
            id currentMode = ((id (*)(id, SEL))objc_msgSend)(keyboardImpl, textInputModeSel);
            currentSummary = WTSPrimaryLanguageFromMode(currentMode);
            if (currentSummary.length == 0) {
                currentSummary = [currentMode description];
            }
        }
    }

    NSString *bundleIdentifier = WTCurrentBundleIdentifier();
    WTSLog(@"UIKeyboardImpl %@ hook triggered. bundle=%@ currentMode=%@ availableModes=%@",
           entryPoint.length > 0 ? entryPoint : @"<unknown>",
           bundleIdentifier.length > 0 ? bundleIdentifier : @"<none>",
           currentSummary.length > 0 ? currentSummary : @"<unknown>",
           modeSummaries.count > 0 ? modeSummaries : @[]);
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

static BOOL WTSProcessIsWeTypeKeyboard(void) {
    static dispatch_once_t onceToken;
    static BOOL shouldInstall = NO;
    dispatch_once(&onceToken, ^{
        shouldInstall = WTShouldInstallForCurrentProcess();
        NSString *bundleIdentifier = WTCurrentBundleIdentifier();
        NSString *bundlePath = [NSBundle mainBundle].bundlePath ?: @"";
        if (shouldInstall) {
            WTSLog(@"[v1.0.1] Process matched WeType targets; enabling hooks (bundle=%@ bundlePath=%@).",
                   bundleIdentifier.length > 0 ? bundleIdentifier : @"<none>",
                   bundlePath.length > 0 ? bundlePath : @"<unknown>");
        } else {
            WTSLog(@"[v1.0.1] Process did not match WeType keyboard targets (bundle=%@ bundlePath=%@).",
                   bundleIdentifier.length > 0 ? bundleIdentifier : @"<none>",
                   bundlePath.length > 0 ? bundlePath : @"<unknown>");
        }
    });
    return shouldInstall;
}

static CGFloat WTSResolvedSwipeThreshold(const WTConfiguration *configuration) {
    if (!configuration) {
        return kWTVerticalTranslationThreshold;
    }
    CGFloat threshold = configuration->swipeThreshold;
    if (threshold <= 0.0f) {
        threshold = kWTVerticalTranslationThreshold;
    }
    return threshold;
}

static BOOL WTSIsApproxVertical(CGPoint translation) {
    const WTConfiguration *config = WTCurrentConfiguration();
    CGFloat dy = fabs(translation.y);
    CGFloat dx = fabs(translation.x);
    CGFloat threshold = WTSResolvedSwipeThreshold(config);
    if (dy < threshold) {
        return NO;
    }
    if (dy <= dx) {
        return NO;
    }
    if (dx > kWTHorizontalTranslationTolerance && (dy - dx) < (kWTHorizontalTranslationTolerance * 0.5f)) {
        return NO;
    }
    return YES;
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

typedef NS_ENUM(NSInteger, WTKeyboardRegion) {
    WTKeyboardRegionUnknown = 0,
    WTKeyboardRegionNineKey,
    WTKeyboardRegionNumberKey,
    WTKeyboardRegionSpacebar
};

static WTKeyboardRegion WTDetectKeyboardRegion(UIView *touchView, UIView *hostView, CGPoint location) {
    if (!touchView || !hostView) {
        return WTKeyboardRegionUnknown;
    }
    
    // Get the keyboard bounds for region calculations
    CGRect keyboardBounds = hostView.bounds;
    if (CGRectIsEmpty(keyboardBounds)) {
        return WTKeyboardRegionUnknown;
    }
    
    CGFloat keyboardHeight = CGRectGetHeight(keyboardBounds);
    CGFloat keyboardWidth = CGRectGetWidth(keyboardBounds);
    
    // Get the actual touch location in host view coordinates
    CGPoint actualLocation = [touchView convertPoint:CGPointMake(CGRectGetMidX(touchView.bounds), CGRectGetMidY(touchView.bounds)) toView:hostView];
    
    // First, try to identify by view class names and accessibility properties
    NSString *className = NSStringFromClass(touchView.class);
    NSString *viewDescription = [touchView description];
    
    // Check accessibility label and identifier if available
    NSString *accessibilityLabel = nil;
    NSString *accessibilityIdentifier = nil;
    if ([touchView respondsToSelector:@selector(accessibilityLabel)]) {
        accessibilityLabel = [(UIView *)touchView accessibilityLabel];
    }
    if ([touchView respondsToSelector:@selector(accessibilityIdentifier)]) {
        accessibilityIdentifier = [(UIView *)touchView accessibilityIdentifier];
    }
    
    // Check for spacebar by various identifiers
    if ([className containsString:@"Space"] || [className containsString:@"space"] ||
        [viewDescription containsString:@"space"] || [viewDescription containsString:@"Space"] ||
        (accessibilityLabel && [accessibilityLabel containsString:@"space"]) ||
        (accessibilityIdentifier && [accessibilityIdentifier containsString:@"space"])) {
        return WTKeyboardRegionSpacebar;
    }
    
    // Check for number switch key
    if ([className containsString:@"Number"] || [className containsString:@"123"] ||
        [viewDescription containsString:@"number"] || [viewDescription containsString:@"123"] ||
        (accessibilityLabel && ([accessibilityLabel containsString:@"number"] || [accessibilityLabel containsString:@"123"])) ||
        (accessibilityIdentifier && ([accessibilityIdentifier containsString:@"number"] || [accessibilityIdentifier containsString:@"123"]))) {
        return WTKeyboardRegionNumberKey;
    }
    
    // Check for symbol/emoji keys
    if ([className containsString:@"Symbol"] || [className containsString:@"Emoji"] ||
        [viewDescription containsString:@"symbol"] || [viewDescription containsString:@"emoji"] ||
        (accessibilityLabel && ([accessibilityLabel containsString:@"symbol"] || [accessibilityLabel containsString:@"emoji"])) ||
        (accessibilityIdentifier && ([accessibilityIdentifier containsString:@"symbol"] || [accessibilityIdentifier containsString:@"emoji"]))) {
        return WTKeyboardRegionSpacebar; // Treat symbol keys as spacebar region
    }
    
    // Check for letter/character keys (part of nine-key area)
    if ([className containsString:@"Key"] || [className containsString:@"Letter"] || [className containsString:@"Character"] ||
        [viewDescription containsString:@"key"] || [viewDescription containsString:@"letter"] ||
        (accessibilityLabel && ([accessibilityLabel containsString:@"key"] || [accessibilityLabel containsString:@"letter"]))) {
        // Verify it's in the central area
        if (actualLocation.y >= keyboardHeight * 0.25 && actualLocation.y <= keyboardHeight * 0.75 &&
            actualLocation.x >= keyboardWidth * 0.05 && actualLocation.x <= keyboardWidth * 0.95) {
            return WTKeyboardRegionNineKey;
        }
    }
    
    // Geometric region detection as fallback
    // Define adaptive region boundaries based on keyboard size
    CGRect nineKeyRegion = CGRectMake(keyboardWidth * 0.05, keyboardHeight * 0.25, keyboardWidth * 0.9, keyboardHeight * 0.5);
    CGRect numberKeyRegion = CGRectMake(keyboardWidth * 0.02, keyboardHeight * 0.72, keyboardWidth * 0.25, keyboardHeight * 0.25);
    CGRect spacebarRegion = CGRectMake(keyboardWidth * 0.1, keyboardHeight * 0.82, keyboardWidth * 0.8, keyboardHeight * 0.18);
    
    // Priority-based region checking
    if (CGRectContainsPoint(spacebarRegion, actualLocation)) {
        return WTKeyboardRegionSpacebar;
    }
    
    if (CGRectContainsPoint(numberKeyRegion, actualLocation)) {
        return WTKeyboardRegionNumberKey;
    }
    
    if (CGRectContainsPoint(nineKeyRegion, actualLocation)) {
        return WTKeyboardRegionNineKey;
    }
    
    // Final fallback: check if it's roughly in the nine-key area by position
    if (actualLocation.y >= keyboardHeight * 0.2 && actualLocation.y <= keyboardHeight * 0.8 &&
        actualLocation.x >= keyboardWidth * 0.05 && actualLocation.x <= keyboardWidth * 0.95) {
        return WTKeyboardRegionNineKey;
    }
    
    return WTKeyboardRegionUnknown;
}

static NSString *WTStringFromKeyboardRegion(WTKeyboardRegion region) {
    switch (region) {
        case WTKeyboardRegionNineKey:
            return @"NineKey";
        case WTKeyboardRegionNumberKey:
            return @"NumberKey";
        case WTKeyboardRegionSpacebar:
            return @"Spacebar";
        case WTKeyboardRegionUnknown:
        default:
            return @"Unknown";
    }
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

static NSString *WTLanguageSummaryFromMode(id mode) {
    if (!mode) {
        return @"<none>";
    }
    NSString *language = WTSPrimaryLanguageFromMode(mode);
    if (language.length > 0) {
        return language;
    }
    NSString *description = [mode description];
    return description.length > 0 ? description : @"<unknown>";
}

static NSString *WTLanguageSummaryForController(UIInputViewController *controller) {
    if (!controller) {
        return @"<none>";
    }
    id mode = WTSCurrentInputMode(controller);
    if (mode) {
        return WTLanguageSummaryFromMode(mode);
    }
    return @"<unknown>";
}

@interface WTLanguageSwipeManager : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UIView *hostView;
@property (nonatomic, strong) UIPanGestureRecognizer *panRecognizer;
@property (nonatomic, assign) CGPoint initialLocation;
@property (nonatomic, weak) UIView *initialTouchView;
@property (nonatomic, assign) BOOL didTrigger;
@property (nonatomic, assign) CGFloat disabledLimit;
@property (nonatomic, assign) WTKeyboardRegion detectedRegion;
@property (nonatomic, assign) CGPoint capturedTranslation;
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
        _panRecognizer.delaysTouchesEnded = NO;
        _panRecognizer.delegate = self;
        [hostView addGestureRecognizer:_panRecognizer];
        _disabledLimit = 0.0;
        _capturedTranslation = CGPointZero;
        _detectedRegion = WTKeyboardRegionUnknown;
        WTSLog(@"[v1.0.1] Gesture recognizer installed with HIGHEST priority (cancelsTouchesInView=YES) on %@", hostView);
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

    const WTConfiguration *config = WTCurrentConfiguration();
    if (!config->globalSwipeEnabled && !config->regionSwipe) {
        return NO;
    }

    if (UIAccessibilityIsVoiceOverRunning()) {
        if (!gWTVoiceOverSuppressedLogged) {
            WTSLog(@"VoiceOver active; suppressing language swipe recognizer.");
            gWTVoiceOverSuppressedLogged = YES;
        }
        return NO;
    }
    gWTVoiceOverSuppressedLogged = NO;

    UIInputViewController *controller = [self activeInputController];
    if (!controller) {
        return NO;
    }

    if (!self.hostView.window || self.hostView.hidden || self.hostView.alpha < 0.1f) {
        return NO;
    }

    self.detectedRegion = WTKeyboardRegionUnknown;
    [self refreshDisabledLimit];
    CGPoint location = [touch locationInView:self.hostView];
    WTKeyboardRegion region = WTDetectKeyboardRegion(touch.view, self.hostView, location);

    BOOL regionSwipeActive = config->regionSwipe && !config->globalSwipeEnabled;
    if (regionSwipeActive) {
        BOOL regionEnabled = NO;
        switch (region) {
            case WTKeyboardRegionNineKey:
                regionEnabled = config->nineKeyEnabled;
                break;
            case WTKeyboardRegionNumberKey:
                regionEnabled = config->numberKeyEnabled;
                break;
            case WTKeyboardRegionSpacebar:
                regionEnabled = config->spacebarEnabled;
                break;
            case WTKeyboardRegionUnknown:
            default:
                regionEnabled = NO;
                break;
        }
        if (!regionEnabled) {
            WTSLog(@"Region %@ disabled, ignoring touch", WTStringFromKeyboardRegion(region));
            return NO;
        }
    }

    BOOL disabled = NO;
    if (self.disabledLimit > 0.0 && location.y <= self.disabledLimit) {
        disabled = YES;
    }
    if (!disabled && WTSTouchViewIsDisabled(touch.view, self.hostView)) {
        disabled = YES;
    }

    if (!disabled && touch.view) {
        NSString *className = NSStringFromClass(touch.view.class);
        if ([className containsString:@"UI"] && ([className containsString:@"Panel"] || [className containsString:@"Toolbar"] || [className containsString:@"Bar"])) {
            disabled = YES;
        }
    }

    if (disabled) {
        WTSLog(@"Ignoring touch in disabled zone (%@) limit=%.2f", touch.view, self.disabledLimit);
        return NO;
    }

    self.initialLocation = location;
    self.initialTouchView = touch.view;
    self.detectedRegion = region;
    self.didTrigger = NO;
    self.capturedTranslation = CGPointZero;
    return YES;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (!self.hostView) {
        return NO;
    }
    const WTConfiguration *config = WTCurrentConfiguration();
    if (!config->globalSwipeEnabled && !config->regionSwipe) {
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
    if (gestureRecognizer != self.panRecognizer || !otherGestureRecognizer) {
        return NO;
    }
    UIView *otherView = otherGestureRecognizer.view;
    if (otherView && ![otherView isDescendantOfView:self.hostView]) {
        return NO;
    }
    if ([otherGestureRecognizer isKindOfClass:[UILongPressGestureRecognizer class]] ||
        [otherGestureRecognizer isKindOfClass:[UITapGestureRecognizer class]]) {
        return YES;
    }
    NSString *className = NSStringFromClass(otherGestureRecognizer.class);
    if ([className containsString:@"LongPress"] ||
        [className containsString:@"Tap"] ||
        [className containsString:@"Press"]) {
        return YES;
    }
    return NO;
}

- (void)handlePan:(UIPanGestureRecognizer *)recognizer {
    if (!self.hostView) {
        return;
    }

    const WTConfiguration *config = WTCurrentConfiguration();
    if (!config->globalSwipeEnabled && !config->regionSwipe) {
        return;
    }

    if (recognizer.state == UIGestureRecognizerStateBegan) {
        self.initialLocation = [recognizer locationInView:self.hostView];
        self.initialTouchView = recognizer.view;
        self.didTrigger = NO;
        self.capturedTranslation = CGPointZero;
        NSString *modeSummary = [self currentModeSummary];
        WTSLog(@"[v1.0.1] Pan began at %@ (detected region=%@ - will be IGNORED, always CN/EN toggle, mode=%@)",
               NSStringFromCGPoint(self.initialLocation),
               WTStringFromKeyboardRegion(self.detectedRegion),
               modeSummary);
        return;
    }

    CGPoint translation = [recognizer translationInView:self.hostView];

    if (!self.didTrigger &&
        (recognizer.state == UIGestureRecognizerStateChanged ||
         recognizer.state == UIGestureRecognizerStateEnded)) {
        if (WTSIsApproxVertical(translation)) {
            UIInputViewController *controller = [self activeInputController];
            NSString *beforeMode = WTLanguageSummaryForController(controller);
            BOOL success = NO;

            // Always trigger language toggle (Chinese/English) regardless of region
            // This ensures swipe anywhere except top taskbar switches CN/EN keyboards
            success = [[self class] triggerLanguageToggleForHostView:self.hostView];
            WTSLog(@"[v1.0.1] Force language toggle mode: ignoring region-specific actions");

            if (success) {
                self.didTrigger = YES;
                self.capturedTranslation = translation;
                NSString *afterMode = WTLanguageSummaryForController(controller);
                NSString *direction = translation.y < 0.0 ? @"Up" : @"Down";
                WTSLog(@"[v1.0.1] ✓ CN/EN toggle triggered (%@) dy=%.1f dx=%.1f detected_region=%@ (ignored) mode=%@ -> %@",
                       direction,
                       translation.y,
                       translation.x,
                       WTStringFromKeyboardRegion(self.detectedRegion),
                       beforeMode,
                       afterMode);
                [recognizer setTranslation:CGPointZero inView:self.hostView];
            } else {
                NSString *direction = translation.y < 0.0 ? @"Up" : @"Down";
                WTSLog(@"[v1.0.1] ✗ Gesture vertical but CN/EN toggle failed (%@) dy=%.1f dx=%.1f detected_region=%@ (ignored) mode=%@",
                       direction,
                       translation.y,
                       translation.x,
                       WTStringFromKeyboardRegion(self.detectedRegion),
                       beforeMode);
            }
        }
    }

    if (recognizer.state == UIGestureRecognizerStateCancelled ||
        recognizer.state == UIGestureRecognizerStateFailed ||
        recognizer.state == UIGestureRecognizerStateEnded) {
        BOOL triggered = self.didTrigger;
        CGPoint loggedTranslation = triggered ? self.capturedTranslation : translation;
        NSString *direction = loggedTranslation.y < 0.0 ? @"Up" : (loggedTranslation.y > 0.0 ? @"Down" : @"None");
        NSString *modeSummary = [self currentModeSummary];

        if (recognizer.state == UIGestureRecognizerStateEnded) {
            if (triggered) {
                WTSLog(@"[v1.0.1] Pan ended after CN/EN toggle (direction=%@ dy=%.1f dx=%.1f detected_region=%@ (ignored) mode=%@)",
                       direction,
                       loggedTranslation.y,
                       loggedTranslation.x,
                       WTStringFromKeyboardRegion(self.detectedRegion),
                       modeSummary);
            } else {
                CGFloat threshold = WTSResolvedSwipeThreshold(config);
                BOOL vertical = WTSIsApproxVertical(loggedTranslation);
                WTSLog(@"[v1.0.1] Pan ended without action (direction=%@ dy=%.1f dx=%.1f threshold=%.1f vertical=%@ detected_region=%@ (ignored) mode=%@)",
                       direction,
                       loggedTranslation.y,
                       loggedTranslation.x,
                       threshold,
                       vertical ? @"YES" : @"NO",
                       WTStringFromKeyboardRegion(self.detectedRegion),
                       modeSummary);
            }
        } else {
            NSString *stateName = recognizer.state == UIGestureRecognizerStateCancelled ? @"cancelled" : @"failed";
            WTSLog(@"[v1.0.1] Pan %@ (triggered=%@ direction=%@ dy=%.1f dx=%.1f detected_region=%@ (ignored) mode=%@)",
                   stateName,
                   triggered ? @"YES" : @"NO",
                   direction,
                   loggedTranslation.y,
                   loggedTranslation.x,
                   WTStringFromKeyboardRegion(self.detectedRegion),
                   modeSummary);
        }

        self.didTrigger = NO;
        self.initialTouchView = nil;
        self.capturedTranslation = CGPointZero;
        self.detectedRegion = WTKeyboardRegionUnknown;
        self.initialLocation = CGPointZero;
    }
}

- (UIInputViewController *)activeInputController {
    UIInputViewController *controller = [[self class] inputControllerForResponder:self.hostView];
    if (!controller && self.hostView.nextResponder) {
        controller = [[self class] inputControllerForResponder:self.hostView.nextResponder];
    }
    return controller;
}

- (NSString *)currentModeSummary {
    return WTLanguageSummaryForController([self activeInputController]);
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
            WTSLog(@"[v1.0.1] Invoking WeType language toggle selector: %@", selectorName);
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
            WTSLog(@"[v1.0.1] Sending UIControl event to language switch button");
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
                    WTSLog(@"[v1.0.1] Invoking language manager selector: %@", selectorName);
                    if ([selectorName hasSuffix:@:"]) {
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
        WTSLog(@"[v1.0.1] Switched language via setInputMode:");
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
        WTSLog(@"[v1.0.1] Fallback toggled language using rotating index %ld", (long)fallbackIndex);
        return YES;
    }
    return NO;
}

+ (BOOL)triggerLanguageToggleForHostView:(UIView *)hostView {
    if (!hostView) {
        return NO;
    }
    UIInputViewController *controller = [self inputControllerForResponder:hostView];
    if (!controller) {
        controller = [self inputControllerForResponder:hostView.nextResponder];
    }
    if (!controller) {
        WTSLog(@"[v1.0.1] No input controller found for %@", hostView);
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

+ (BOOL)triggerNumericSwitchForHostView:(UIView *)hostView {
    if (!hostView) {
        return NO;
    }
    UIInputViewController *controller = [self inputControllerForResponder:hostView];
    if (!controller) {
        controller = [self inputControllerForResponder:hostView.nextResponder];
    }
    if (!controller) {
        WTSLog(@"No input controller found for numeric switch");
        return NO;
    }

    // Try WeType-specific numeric switch methods
    Class weTypeControllerClass = NSClassFromString(@"WBInputViewController");
    if (weTypeControllerClass && ![controller isKindOfClass:weTypeControllerClass]) {
        WTSLog(@"Not a WeType controller for numeric switch");
        return NO;
    }

    NSArray<NSString *> *numericSelectors = @[
        @"switchToNumericKeyboard",
        @"switchToNumberKeyboard",
        @"showNumericKeyboard",
        @"presentNumericKeyboard:",
        @"switchToNumbers",
        @"switchToNumbers:",
        @"showNumberKeyboard",
        @"presentNumberKeyboard:",
        @"setKeyboardTypeNumeric:",
        @"setKeyboardTypeNumbers:",
        @"changeKeyboardTypeToNumeric:",
        @"changeKeyboardTypeToNumbers:"
    ];

    for (NSString *selectorName in numericSelectors) {
        SEL selector = NSSelectorFromString(selectorName);
        if ([controller respondsToSelector:selector]) {
            WTSLog(@"Invoking numeric selector %@", selectorName);
            if ([selectorName hasSuffix:@":"]) {
                ((void (*)(id, SEL, id))objc_msgSend)(controller, selector, nil);
            } else {
                ((void (*)(id, SEL))objc_msgSend)(controller, selector);
            }
            return YES;
        }
    }

    // Try to find and press the numeric switch button
    NSArray<NSString *> *buttonSelectors = @[
        @"numericSwitchButton",
        @"numberSwitchButton",
        @"numbersButton",
        @"numberKeyboardButton",
        @"numericKeyboardButton",
        @"switchToNumbersButton",
        @"switchToNumericButton"
    ];

    for (NSString *selectorName in buttonSelectors) {
        SEL selector = NSSelectorFromString(selectorName);
        if ([controller respondsToSelector:selector]) {
            id button = ((id (*)(id, SEL))objc_msgSend)(controller, selector);
            if ([button isKindOfClass:[UIControl class]]) {
                WTSLog(@"Sending UIControl event to numeric switch button (%@)", selectorName);
                [button sendActionsForControlEvents:UIControlEventTouchUpInside];
                return YES;
            }
        }
    }

    // Try generic keyboard type switching
    SEL setKeyboardTypeSel = @selector(setKeyboardType:);
    if ([controller respondsToSelector:setKeyboardTypeSel]) {
        // UIKeyboardTypeNumbersAndPunctuation = 2, UIKeyboardTypeNumberPad = 4
        WTSLog(@"Setting keyboard type to numeric");
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(controller, setKeyboardTypeSel, 2); // NumbersAndPunctuation
        return YES;
    }

    WTSLog(@"No numeric switch method found");
    return NO;
}

+ (BOOL)triggerSymbolSwitchForHostView:(UIView *)hostView {
    if (!hostView) {
        return NO;
    }
    UIInputViewController *controller = [self inputControllerForResponder:hostView];
    if (!controller) {
        controller = [self inputControllerForResponder:hostView.nextResponder];
    }
    if (!controller) {
        WTSLog(@"No input controller found for symbol switch");
        return NO;
    }

    // Try WeType-specific symbol switch methods
    Class weTypeControllerClass = NSClassFromString(@"WBInputViewController");
    if (weTypeControllerClass && ![controller isKindOfClass:weTypeControllerClass]) {
        WTSLog(@"Not a WeType controller for symbol switch");
        return NO;
    }

    NSArray<NSString *> *symbolSelectors = @[
        @"switchToSymbolKeyboard",
        @"switchToSymbolsKeyboard",
        @"showSymbolKeyboard",
        @"presentSymbolKeyboard:",
        @"switchToSymbols",
        @"switchToSymbols:",
        @"showSymbolsKeyboard",
        @"presentSymbolsKeyboard:",
        @"setKeyboardTypeSymbols:",
        @"setKeyboardTypeSymbol:",
        @"changeKeyboardTypeToSymbol:",
        @"changeKeyboardTypeToSymbols:",
        @"showMoreSymbols",
        @"showMoreSymbols:"
    ];

    for (NSString *selectorName in symbolSelectors) {
        SEL selector = NSSelectorFromString(selectorName);
        if ([controller respondsToSelector:selector]) {
            WTSLog(@"Invoking symbol selector %@", selectorName);
            if ([selectorName hasSuffix:@":"]) {
                ((void (*)(id, SEL, id))objc_msgSend)(controller, selector, nil);
            } else {
                ((void (*)(id, SEL))objc_msgSend)(controller, selector);
            }
            return YES;
        }
    }

    // Try to find and press the symbol switch button
    NSArray<NSString *> *buttonSelectors = @[
        @"symbolSwitchButton",
        @"symbolsButton",
        @"symbolKeyboardButton",
        @"symbolsKeyboardButton",
        @"switchToSymbolsButton",
        @"switchToSymbolButton",
        @"moreSymbolsButton",
        @"moreButton"
    ];

    for (NSString *selectorName in buttonSelectors) {
        SEL selector = NSSelectorFromString(selectorName);
        if ([controller respondsToSelector:selector]) {
            id button = ((id (*)(id, SEL))objc_msgSend)(controller, selector);
            if ([button isKindOfClass:[UIControl class]]) {
                WTSLog(@"Sending UIControl event to symbol switch button (%@)", selectorName);
                [button sendActionsForControlEvents:UIControlEventTouchUpInside];
                return YES;
            }
        }
    }

    // Try generic keyboard type switching
    SEL setKeyboardTypeSel = @selector(setKeyboardType:);
    if ([controller respondsToSelector:setKeyboardTypeSel]) {
        WTSLog(@"Setting keyboard type to symbols");
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(controller, setKeyboardTypeSel, 5); // UIKeyboardTypeURL (approximate symbol keyboard)
        return YES;
    }

    WTSLog(@"No symbol switch method found");
    return NO;
}

// Backward compatibility method
+ (BOOL)triggerToggleForHostView:(UIView *)hostView {
    return [self triggerLanguageToggleForHostView:hostView];
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

%group WTSWeTypeHooks

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

%hook UIKeyboardImpl
- (void)activate {
    %orig;
    WTMaybeEmitKeyboardImplDiagnostics(self, NSStringFromSelector(_cmd), nil);
}

- (void)setInputMode:(id)mode {
    %orig(mode);
    WTMaybeEmitKeyboardImplDiagnostics(self, NSStringFromSelector(_cmd), mode);
}
%end

%end

%ctor {
    @autoreleasepool {
        WTLogLaunchDiagnostics();
        if (!WTFeatureEnabled()) {
            WTSLog(@"[v1.0.1] wxkeyboard tweak disabled via preferences; skipping initialization.");
            return;
        }
        if (WTSProcessIsWeTypeKeyboard()) {
            WTSLog(@"[v1.0.1] ✓ Initializing WeType hook group with CN/EN-only swipe mode.");
            %init(WTSWeTypeHooks);
        } else {
            WTSLog(@"[v1.0.1] Process not matched for WeType hooks; initialization skipped.");
        }
    }
}
