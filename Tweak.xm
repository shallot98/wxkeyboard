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

// Constants for WeType vertical swipe implementation

static NSString *const kWTPreferencesDomain = @"com.yourcompany.wxkeyboard";
static NSString *const kWTLogFilePath = @"/var/mobile/Library/Logs/wxkeyboard.log";
static NSString *const kWTLogFileBackupPath = @"/var/mobile/Library/Logs/wxkeyboard.log.1";
static const NSUInteger kWTLogRotateThresholdBytes = 256 * 1024;

typedef struct {
    BOOL enabled;
    BOOL debugLog;
    CGFloat minTranslationY;
    BOOL suppressKeyTapOnSwipe;
    NSString *logLevel;
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

static CGFloat WTInterpretCGFloatFromObject(id value, CGFloat defaultValue) {
    if (!value || value == [NSNull null]) {
        return defaultValue;
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        return ((NSNumber *)value).floatValue;
    }
    if ([value isKindOfClass:[NSString class]]) {
        return [(NSString *)value floatValue];
    }
    return defaultValue;
}

static NSString *WTInterpretStringFromObject(id value, NSString *defaultValue) {
    if (!value || value == [NSNull null]) {
        return defaultValue;
    }
    if ([value isKindOfClass:[NSString class]]) {
        NSString *stringValue = (NSString *)value;
        return stringValue.length > 0 ? stringValue : defaultValue;
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

static CGFloat WTReadPreferenceCGFloat(NSString *key, CGFloat defaultValue) {
    CGFloat result = defaultValue;
    CFPropertyListRef valueRef = CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)kWTPreferencesDomain);
    if (valueRef) {
        id value = CFBridgingRelease(valueRef);
        result = WTInterpretCGFloatFromObject(value, defaultValue);
    } else {
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:kWTPreferencesDomain];
        if (defaults) {
            id value = [defaults objectForKey:key];
            if (value) {
                result = WTInterpretCGFloatFromObject(value, defaultValue);
            }
        }
    }
    return result;
}

static NSString *WTReadPreferenceString(NSString *key, NSString *defaultValue) {
    NSString *result = defaultValue;
    CFPropertyListRef valueRef = CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)kWTPreferencesDomain);
    if (valueRef) {
        id value = CFBridgingRelease(valueRef);
        result = WTInterpretStringFromObject(value, defaultValue);
    } else {
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:kWTPreferencesDomain];
        if (defaults) {
            id value = [defaults objectForKey:key];
            if (value) {
                result = WTInterpretStringFromObject(value, defaultValue);
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
        configuration.minTranslationY = WTReadPreferenceCGFloat(@"MinTranslationY", 28.0);
        configuration.suppressKeyTapOnSwipe = WTReadPreferenceBool(@"SuppressKeyTapOnSwipe", YES);
        configuration.logLevel = WTReadPreferenceString(@"LogLevel", @"DEBUG");
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

static BOOL WTShouldLogLevel(NSString *level) {
    if (!WTDebugLogEnabled()) {
        return NO;
    }
    NSString *currentLevel = WTCurrentConfiguration()->logLevel;
    if ([currentLevel isEqualToString:@"DEBUG"]) {
        return YES;
    } else if ([currentLevel isEqualToString:@"INFO"]) {
        return [level isEqualToString:@"INFO"] || [level isEqualToString:@"ERROR"];
    } else if ([currentLevel isEqualToString:@"ERROR"]) {
        return [level isEqualToString:@"ERROR"];
    }
    return YES;
}

static void WTSLog(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);
static void WTSLog(NSString *format, ...) {
    if (!WTShouldLogLevel(@"DEBUG")) {
        return;
    }
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    WTWriteDebugLogLine(message);
}

static void WTSLogInfo(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);
static void WTSLogInfo(NSString *format, ...) {
    if (!WTShouldLogLevel(@"INFO")) {
        return;
    }
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSString *prefixedMessage = [NSString stringWithFormat:@"[INFO] %@", message];
    WTWriteDebugLogLine(prefixedMessage);
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
    WTSLogInfo(@"Launch diagnostics: enabled=%@ debugLog=%@ minTranslationY=%.1f suppressKeyTapOnSwipe=%@ logLevel=%@ processName=%@ bundleIdentifier=%@ bundlePath=%@ execPath=%@",
           configuration->enabled ? @"YES" : @"NO",
           configuration->debugLog ? @"YES" : @"NO",
           configuration->minTranslationY,
           configuration->suppressKeyTapOnSwipe ? @"YES" : @"NO",
           configuration->logLevel,
           processName.length > 0 ? processName : @"<unknown>",
           bundleIdentifier.length > 0 ? bundleIdentifier : @"<none>",
           bundlePath.length > 0 ? bundlePath : @"<unknown>",
           execPath.length > 0 ? execPath : @"<unknown>");
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

// Language detection functions removed - using WeType's internal mode management instead

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

// Language tracking removed - using WeType's internal mode management instead

static BOOL WTSProcessIsWeTypeKeyboard(void) {
    static dispatch_once_t onceToken;
    static BOOL shouldInstall = NO;
    dispatch_once(&onceToken, ^{
        shouldInstall = WTShouldInstallForCurrentProcess();
        NSString *bundleIdentifier = WTCurrentBundleIdentifier();
        NSString *bundlePath = [NSBundle mainBundle].bundlePath ?: @"";
        if (shouldInstall) {
            WTSLog(@"Process matched WeType targets; enabling hooks (bundle=%@ bundlePath=%@).",
                   bundleIdentifier.length > 0 ? bundleIdentifier : @"<none>",
                   bundlePath.length > 0 ? bundlePath : @"<unknown>");
        } else {
            WTSLog(@"Process did not match WeType keyboard targets (bundle=%@ bundlePath=%@).",
                   bundleIdentifier.length > 0 ? bundleIdentifier : @"<none>",
                   bundlePath.length > 0 ? bundlePath : @"<unknown>");
        }
    });
    return shouldInstall;
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

typedef struct {
    CGPoint startPoint;
    NSTimeInterval startTime;
    NSTimeInterval lastTriggerTime;
    BOOL directionLocked;
    BOOL verticalSwipeDetected;
} WTTouchState;

@interface WTVerticalSwipeManager : NSObject
@property (nonatomic, weak) UIView *hostView;
@property (nonatomic, assign) WTTouchState touchState;
@end

@implementation WTVerticalSwipeManager

- (instancetype)initWithHostView:(UIView *)hostView {
    self = [super init];
    if (self) {
        _hostView = hostView;
        memset(&_touchState, 0, sizeof(WTTouchState));
        WTSLogInfo(@"Touch state tracker initialized on %@", hostView);
    }
    return self;
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

+ (NSArray *)getWeTypeInputModes:(UIInputViewController *)controller {
    if (!controller) {
        return nil;
    }
    
    // Try to get WeType's mode manager first
    Class weTypeControllerClass = NSClassFromString(@"WBInputViewController");
    if (weTypeControllerClass && [controller isKindOfClass:weTypeControllerClass]) {
        // Try to get the mode manager
        SEL managerSel = NSSelectorFromString(@"inputModeManager");
        if ([controller respondsToSelector:managerSel]) {
            id manager = ((id (*)(id, SEL))objc_msgSend)(controller, managerSel);
            if (manager) {
                SEL modesSel = NSSelectorFromString(@"availableInputModes");
                if ([manager respondsToSelector:modesSel]) {
                    NSArray *modes = ((NSArray *(*)(id, SEL))objc_msgSend)(manager, modesSel);
                    if (modes.count > 0) {
                        WTSLog(@"Got %ld modes from WeType mode manager", (long)modes.count);
                        return modes;
                    }
                }
            }
        }
        
        // Try direct mode access on controller
        NSArray<NSString *> *modeSelectors = @[
            @"availableInputModes",
            @"inputModes",
            @"supportedInputModes",
            @"enabledInputModes"
        ];
        
        for (NSString *selectorName in modeSelectors) {
            SEL selector = NSSelectorFromString(selectorName);
            if ([controller respondsToSelector:selector]) {
                NSArray *modes = ((NSArray *(*)(id, SEL))objc_msgSend)(controller, selector);
                if (modes.count > 0) {
                    WTSLog(@"Got %ld modes from controller selector %@", (long)modes.count, selectorName);
                    return modes;
                }
            }
        }
    }
    
    // Fallback to standard iOS input modes
    if ([controller respondsToSelector:@selector(inputModes)]) {
        NSArray *modes = [controller inputModes];
        if (modes.count > 0) {
            WTSLog(@"Got %ld modes from standard iOS inputModes", (long)modes.count);
            return modes;
        }
    }
    
    return nil;
}

+ (id)getCurrentWeTypeInputMode:(UIInputViewController *)controller {
    if (!controller) {
        return nil;
    }
    
    // Try WeType-specific current mode methods
    Class weTypeControllerClass = NSClassFromString(@"WBInputViewController");
    if (weTypeControllerClass && [controller isKindOfClass:weTypeControllerClass]) {
        NSArray<NSString *> *currentModeSelectors = @[
            @"currentInputMode",
            @"activeInputMode",
            @"selectedInputMode",
            @"currentMode"
        ];
        
        for (NSString *selectorName in currentModeSelectors) {
            SEL selector = NSSelectorFromString(selectorName);
            if ([controller respondsToSelector:selector]) {
                id mode = ((id (*)(id, SEL))objc_msgSend)(controller, selector);
                if (mode) {
                    WTSLog(@"Got current mode from WeType selector %@", selectorName);
                    return mode;
                }
            }
        }
    }
    
    // Fallback to standard iOS methods
    return WTSCurrentInputMode(controller);
}

+ (BOOL)setWeTypeInputMode:(UIInputViewController *)controller mode:(id)mode {
    if (!controller || !mode) {
        return NO;
    }
    
    // Try WeType-specific mode setting methods
    Class weTypeControllerClass = NSClassFromString(@"WBInputViewController");
    if (weTypeControllerClass && [controller isKindOfClass:weTypeControllerClass]) {
        NSArray<NSString *> *setModeSelectors = @[
            @"setInputMode:",
            @"switchToInputMode:",
            @"changeToInputMode:",
            @"selectInputMode:",
            @"activateInputMode:"
        ];
        
        for (NSString *selectorName in setModeSelectors) {
            SEL selector = NSSelectorFromString(selectorName);
            if ([controller respondsToSelector:selector]) {
                WTSLog(@"Setting mode using WeType selector %@", selectorName);
                ((void (*)(id, SEL, id))objc_msgSend)(controller, selector, mode);
                return YES;
            }
        }
    }
    
    // Fallback to standard iOS method
    SEL setInputModeSel = @selector(setInputMode:);
    if ([controller respondsToSelector:setInputModeSel]) {
        WTSLog(@"Setting mode using standard setInputMode:");
        ((void (*)(id, SEL, id))objc_msgSend)(controller, setInputModeSel, mode);
        return YES;
    }
    
    return NO;
}

+ (NSString *)getModeDisplayName:(id)mode {
    if (!mode) {
        return @"<unknown>";
    }
    
    // Try to get display name from mode object
    SEL displayNameSel = NSSelectorFromString(@"displayName");
    if ([mode respondsToSelector:displayNameSel]) {
        NSString *displayName = ((NSString *(*)(id, SEL))objc_msgSend)(mode, displayNameSel);
        if (displayName.length > 0) {
            return displayName;
        }
    }
    
    SEL localizedNameSel = NSSelectorFromString(@"localizedName");
    if ([mode respondsToSelector:localizedNameSel]) {
        NSString *localizedName = ((NSString *(*)(id, SEL))objc_msgSend)(mode, localizedNameSel);
        if (localizedName.length > 0) {
            return localizedName;
        }
    }
    
    // Fallback to primary language
    NSString *language = WTSPrimaryLanguageFromMode(mode);
    if (language.length > 0) {
        return language;
    }
    
    // Final fallback to description
    return [mode description];
}

+ (BOOL)isChineseMode:(id)mode {
    if (!mode) {
        return NO;
    }
    
    NSString *displayName = [self getModeDisplayName:mode];
    NSString *lowerName = [displayName lowercaseString];
    
    // Check if mode is Chinese by various indicators
    return [lowerName containsString:@"chinese"] || 
           [lowerName containsString:@"zh"] || 
           [lowerName containsString:@"中文"] ||
           [lowerName containsString:@"简体"] ||
           [lowerName containsString:@"繁体"] ||
           [lowerName containsString:@"拼音"] ||
           [lowerName containsString:@"pinyin"];
}

+ (BOOL)isEnglishMode:(id)mode {
    if (!mode) {
        return NO;
    }
    
    NSString *displayName = [self getModeDisplayName:mode];
    NSString *lowerName = [displayName lowercaseString];
    
    // Check if mode is English by various indicators
    return [lowerName containsString:@"english"] || 
           [lowerName containsString:@"en"] || 
           [lowerName containsString:@"英文"] ||
           [lowerName containsString:@"英语"];
}

+ (id)findChineseMode:(NSArray *)modes {
    for (id mode in modes) {
        if ([self isChineseMode:mode]) {
            return mode;
        }
    }
    return nil;
}

+ (id)findEnglishMode:(NSArray *)modes {
    for (id mode in modes) {
        if ([self isEnglishMode:mode]) {
            return mode;
        }
    }
    return nil;
}

+ (void)switchToPreviousModeForHostView:(UIView *)hostView {
    UIInputViewController *controller = [self inputControllerForResponder:hostView];
    if (!controller) {
        controller = [self inputControllerForResponder:hostView.nextResponder];
    }
    if (!controller) {
        WTSLog(@"No input controller found for previous mode switch");
        return;
    }
    
    NSArray *modes = [self getWeTypeInputModes:controller];
    if (!modes || modes.count < 2) {
        WTSLog(@"Insufficient modes for switching (%ld available)", (long)(modes ? modes.count : 0));
        return;
    }
    
    // Log all available modes for debugging
    NSMutableArray *modeNames = [NSMutableArray array];
    for (id mode in modes) {
        [modeNames addObject:[self getModeDisplayName:mode]];
    }
    WTSLog(@"Available modes: %@", [modeNames componentsJoinedByString:@", "]);
    
    id currentMode = [self getCurrentWeTypeInputMode:controller];
    NSString *currentModeName = [self getModeDisplayName:currentMode];
    BOOL isCurrentChinese = [self isChineseMode:currentMode];
    BOOL isCurrentEnglish = [self isEnglishMode:currentMode];
    
    WTSLog(@"Up swipe: Current mode=%@ (isChinese=%@ isEnglish=%@)", 
           currentModeName, isCurrentChinese ? @"YES" : @"NO", isCurrentEnglish ? @"YES" : @"NO");
    
    // Find Chinese and English modes
    id chineseMode = [self findChineseMode:modes];
    id englishMode = [self findEnglishMode:modes];
    
    if (!chineseMode || !englishMode) {
        WTSLog(@"Could not find both Chinese and English modes (chinese=%@ english=%@)", 
               chineseMode ? @"found" : @"not found", englishMode ? @"found" : @"not found");
        // Fallback to circular switching if we can't identify Chinese/English modes
        NSInteger currentIndex = [modes indexOfObject:currentMode];
        if (currentIndex == NSNotFound) {
            currentIndex = 0;
        }
        NSInteger previousIndex = currentIndex > 0 ? currentIndex - 1 : modes.count - 1;
        id previousMode = modes[previousIndex];
        NSString *previousModeName = [self getModeDisplayName:previousMode];
        
        if ([self setWeTypeInputMode:controller mode:previousMode]) {
            WTSLog(@"Fallback: Switched to previous mode: %@ (from %@)", previousModeName, currentModeName);
        } else {
            WTSLog(@"Fallback: Failed to switch to previous mode: %@", previousModeName);
        }
        return;
    }
    
    // Toggle between Chinese and English only
    id targetMode = nil;
    if (isCurrentChinese) {
        targetMode = englishMode;
        WTSLog(@"Up swipe: Switching from Chinese to English");
    } else {
        targetMode = chineseMode;
        WTSLog(@"Up swipe: Switching to Chinese (current is not Chinese)");
    }
    
    NSString *targetModeName = [self getModeDisplayName:targetMode];
    if ([self setWeTypeInputMode:controller mode:targetMode]) {
        WTSLog(@"Successfully switched to %@ (from %@)", targetModeName, currentModeName);
    } else {
        WTSLog(@"Failed to switch to %@", targetModeName);
    }
}

+ (void)switchToNextModeForHostView:(UIView *)hostView {
    UIInputViewController *controller = [self inputControllerForResponder:hostView];
    if (!controller) {
        controller = [self inputControllerForResponder:hostView.nextResponder];
    }
    if (!controller) {
        WTSLog(@"No input controller found for next mode switch");
        return;
    }
    
    NSArray *modes = [self getWeTypeInputModes:controller];
    if (!modes || modes.count < 2) {
        WTSLog(@"Insufficient modes for switching (%ld available)", (long)(modes ? modes.count : 0));
        return;
    }
    
    // Log all available modes for debugging
    NSMutableArray *modeNames = [NSMutableArray array];
    for (id mode in modes) {
        [modeNames addObject:[self getModeDisplayName:mode]];
    }
    WTSLog(@"Available modes: %@", [modeNames componentsJoinedByString:@", "]);
    
    id currentMode = [self getCurrentWeTypeInputMode:controller];
    NSString *currentModeName = [self getModeDisplayName:currentMode];
    BOOL isCurrentChinese = [self isChineseMode:currentMode];
    BOOL isCurrentEnglish = [self isEnglishMode:currentMode];
    
    WTSLog(@"Down swipe: Current mode=%@ (isChinese=%@ isEnglish=%@)", 
           currentModeName, isCurrentChinese ? @"YES" : @"NO", isCurrentEnglish ? @"YES" : @"NO");
    
    // Find Chinese and English modes
    id chineseMode = [self findChineseMode:modes];
    id englishMode = [self findEnglishMode:modes];
    
    if (!chineseMode || !englishMode) {
        WTSLog(@"Could not find both Chinese and English modes (chinese=%@ english=%@)", 
               chineseMode ? @"found" : @"not found", englishMode ? @"found" : @"not found");
        // Fallback to circular switching if we can't identify Chinese/English modes
        NSInteger currentIndex = [modes indexOfObject:currentMode];
        if (currentIndex == NSNotFound) {
            currentIndex = 0;
        }
        NSInteger nextIndex = (currentIndex + 1) % modes.count;
        id nextMode = modes[nextIndex];
        NSString *nextModeName = [self getModeDisplayName:nextMode];
        
        if ([self setWeTypeInputMode:controller mode:nextMode]) {
            WTSLog(@"Fallback: Switched to next mode: %@ (from %@)", nextModeName, currentModeName);
        } else {
            WTSLog(@"Fallback: Failed to switch to next mode: %@", nextModeName);
        }
        return;
    }
    
    // Toggle between Chinese and English only
    id targetMode = nil;
    if (isCurrentEnglish) {
        targetMode = chineseMode;
        WTSLog(@"Down swipe: Switching from English to Chinese");
    } else {
        targetMode = englishMode;
        WTSLog(@"Down swipe: Switching to English (current is not English)");
    }
    
    NSString *targetModeName = [self getModeDisplayName:targetMode];
    if ([self setWeTypeInputMode:controller mode:targetMode]) {
        WTSLog(@"Successfully switched to %@ (from %@)", targetModeName, currentModeName);
    } else {
        WTSLog(@"Failed to switch to %@", targetModeName);
    }
}

// Legacy method removed - replaced by new WeType-specific mode switching

// Legacy methods removed - replaced by new WeType-specific mode switching with proper previous/next logic

@end

static const void *kWTTouchTrackerKey = &kWTTouchTrackerKey;

static BOOL WTSShouldInstallOnView(UIView *view) {
    if (!view) {
        return NO;
    }
    
    // Skip if already installed
    if (objc_getAssociatedObject(view, kWTTouchTrackerKey) != nil) {
        return NO;
    }
    
    // Check if view is large enough to be worth installing on
    CGSize boundsSize = view.bounds.size;
    if (boundsSize.width < 20.0 || boundsSize.height < 20.0) {
        return NO;
    }
    
    // Check if view is visible
    if (view.hidden || view.alpha < 0.1) {
        return NO;
    }
    
    // Prioritize larger views and keyboard-related views
    NSString *className = NSStringFromClass(view.class);
    BOOL isKeyboardRelated = [className containsString:@"Keyboard"] || 
                             [className containsString:@"Key"] ||
                             [className containsString:@"Input"] ||
                             [className containsString:@"WB"] ||
                             [className containsString:@"WXKB"];
    
    // Install on keyboard-related views or larger views
    BOOL isLargeEnough = boundsSize.width > 100.0 && boundsSize.height > 50.0;
    
    return isKeyboardRelated || isLargeEnough;
}

static void WTSInstallTouchTrackerIfNeeded(UIView *view) {
    if (!WTSShouldInstallOnView(view)) {
        return;
    }
    
    WTVerticalSwipeManager *manager = [[WTVerticalSwipeManager alloc] initWithHostView:view];
    objc_setAssociatedObject(view, kWTTouchTrackerKey, manager, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    WTSLog(@"Installed touch tracker on view: %@ (%.1fx%.1f)", 
           NSStringFromClass(view.class), view.bounds.size.width, view.bounds.size.height);
}

// WeType keyboard view classes to hook for comprehensive gesture coverage
@interface WBMainInputView : UIView @end
@interface WBKeyboardView : UIView @end
@interface WBInputViewController : UIInputViewController @end
@interface WXKBKeyboardView : UIView @end  // Additional WeType keyboard view
@interface WXKBMainKeyboardView : UIView @end  // Main keyboard container
@interface WXKBKeyContainerView : UIView @end  // Key container view
@interface WBKeyView : UIView @end  // Individual key view
@interface WXKBKeyView : UIView @end  // Alternative key view class

static void WTSProcessTouchMovedForView(UIView *view, NSSet<UITouch *> *touches) {
    if (!view || touches.count == 0) {
        return;
    }
    
    WTVerticalSwipeManager *tracker = objc_getAssociatedObject(view, kWTTouchTrackerKey);
    if (!tracker) {
        return;
    }
    
    const WTConfiguration *config = WTCurrentConfiguration();
    UITouch *touch = touches.anyObject;
    CGPoint currentPoint = [touch locationInView:view];
    NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
    
    CGFloat dy = currentPoint.y - tracker.touchState.startPoint.y;
    CGFloat dx = currentPoint.x - tracker.touchState.startPoint.x;
    
    if (!tracker.touchState.directionLocked) {
        CGFloat absDx = fabs(dx);
        CGFloat absDy = fabs(dy);
        
        if (absDy > absDx * 1.5 && absDy > 10.0) {
            tracker.touchState.directionLocked = YES;
            WTSLog(@"Direction locked to vertical (dx=%.1f, dy=%.1f)", dx, dy);
        } else if (absDx > absDy * 2.0 && absDx > 15.0) {
            WTSLog(@"Horizontal movement detected, releasing tracker (dx=%.1f, dy=%.1f)", dx, dy);
            tracker.touchState.directionLocked = NO;
            return;
        }
    }
    
    if (tracker.touchState.directionLocked && !tracker.touchState.verticalSwipeDetected) {
        CGFloat absDy = fabs(dy);
        if (absDy >= config->minTranslationY) {
            tracker.touchState.verticalSwipeDetected = YES;
            
            if (currentTime - tracker.touchState.lastTriggerTime < 0.25) {
                WTSLog(@"Swipe detected but too soon since last trigger (%.3fs), ignoring", 
                       currentTime - tracker.touchState.lastTriggerTime);
                return;
            }
            
            if (dy < 0) {
                WTSLogInfo(@"Up swipe detected: dy=%.1f, distance=%.1f", dy, absDy);
                [[WTVerticalSwipeManager class] switchToPreviousModeForHostView:view];
            } else {
                WTSLogInfo(@"Down swipe detected: dy=%.1f, distance=%.1f", dy, absDy);
                [[WTVerticalSwipeManager class] switchToNextModeForHostView:view];
            }
            
            tracker.touchState.lastTriggerTime = currentTime;
        }
    }
}

%group WTSWeTypeHooks

%hook WBMainInputView
- (void)didMoveToWindow {
    %orig;
    WTSInstallTouchTrackerIfNeeded(self);
}

- (void)layoutSubviews {
    %orig;
    WTSInstallTouchTrackerIfNeeded(self);
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    WTVerticalSwipeManager *tracker = objc_getAssociatedObject(self, kWTTouchTrackerKey);
    if (tracker && touches.count > 0) {
        UITouch *touch = touches.anyObject;
        tracker.touchState.startPoint = [touch locationInView:self];
        tracker.touchState.startTime = [[NSDate date] timeIntervalSince1970];
        tracker.touchState.directionLocked = NO;
        tracker.touchState.verticalSwipeDetected = NO;
        WTSLog(@"Touch began at (%.1f, %.1f)", tracker.touchState.startPoint.x, tracker.touchState.startPoint.y);
    }
    %orig;
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    WTSProcessTouchMovedForView(self, touches);
    %orig;
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    WTVerticalSwipeManager *tracker = objc_getAssociatedObject(self, kWTTouchTrackerKey);
    if (tracker) {
        WTSLog(@"Touch ended, resetting state");
        tracker.touchState.directionLocked = NO;
        tracker.touchState.verticalSwipeDetected = NO;
    }
    %orig;
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    WTVerticalSwipeManager *tracker = objc_getAssociatedObject(self, kWTTouchTrackerKey);
    if (tracker) {
        WTSLog(@"Touch cancelled, resetting state");
        tracker.touchState.directionLocked = NO;
        tracker.touchState.verticalSwipeDetected = NO;
    }
    %orig;
}
%end

%hook WBKeyboardView
- (void)didMoveToWindow {
    %orig;
    WTSInstallTouchTrackerIfNeeded(self);
}

- (void)layoutSubviews {
    %orig;
    WTSInstallTouchTrackerIfNeeded(self);
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    WTVerticalSwipeManager *tracker = objc_getAssociatedObject(self, kWTTouchTrackerKey);
    if (tracker && touches.count > 0) {
        UITouch *touch = touches.anyObject;
        tracker.touchState.startPoint = [touch locationInView:self];
        tracker.touchState.startTime = [[NSDate date] timeIntervalSince1970];
        tracker.touchState.directionLocked = NO;
        tracker.touchState.verticalSwipeDetected = NO;
        WTSLog(@"Touch began at (%.1f, %.1f)", tracker.touchState.startPoint.x, tracker.touchState.startPoint.y);
    }
    %orig;
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    WTSProcessTouchMovedForView(self, touches);
    %orig;
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    WTVerticalSwipeManager *tracker = objc_getAssociatedObject(self, kWTTouchTrackerKey);
    if (tracker) {
        WTSLog(@"Touch ended, resetting state");
        tracker.touchState.directionLocked = NO;
        tracker.touchState.verticalSwipeDetected = NO;
    }
    %orig;
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    WTVerticalSwipeManager *tracker = objc_getAssociatedObject(self, kWTTouchTrackerKey);
    if (tracker) {
        WTSLog(@"Touch cancelled, resetting state");
        tracker.touchState.directionLocked = NO;
        tracker.touchState.verticalSwipeDetected = NO;
    }
    %orig;
}
%end

%hook WBInputViewController
- (void)viewDidLoad {
    %orig;
    WTSInstallTouchTrackerIfNeeded(self.view);
}

- (void)viewDidLayoutSubviews {
    %orig;
    WTSInstallTouchTrackerIfNeeded(self.view);
}
%end

%hook WXKBKeyboardView
- (void)didMoveToWindow {
    %orig;
    WTSInstallTouchTrackerIfNeeded(self);
}

- (void)layoutSubviews {
    %orig;
    WTSInstallTouchTrackerIfNeeded(self);
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    WTVerticalSwipeManager *tracker = objc_getAssociatedObject(self, kWTTouchTrackerKey);
    if (tracker && touches.count > 0) {
        UITouch *touch = touches.anyObject;
        tracker.touchState.startPoint = [touch locationInView:self];
        tracker.touchState.startTime = [[NSDate date] timeIntervalSince1970];
        tracker.touchState.directionLocked = NO;
        tracker.touchState.verticalSwipeDetected = NO;
        WTSLog(@"Touch began at (%.1f, %.1f)", tracker.touchState.startPoint.x, tracker.touchState.startPoint.y);
    }
    %orig;
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    WTSProcessTouchMovedForView(self, touches);
    %orig;
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    WTVerticalSwipeManager *tracker = objc_getAssociatedObject(self, kWTTouchTrackerKey);
    if (tracker) {
        WTSLog(@"Touch ended, resetting state");
        tracker.touchState.directionLocked = NO;
        tracker.touchState.verticalSwipeDetected = NO;
    }
    %orig;
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    WTVerticalSwipeManager *tracker = objc_getAssociatedObject(self, kWTTouchTrackerKey);
    if (tracker) {
        WTSLog(@"Touch cancelled, resetting state");
        tracker.touchState.directionLocked = NO;
        tracker.touchState.verticalSwipeDetected = NO;
    }
    %orig;
}
%end

%hook WXKBMainKeyboardView
- (void)didMoveToWindow {
    %orig;
    WTSInstallTouchTrackerIfNeeded(self);
}

- (void)layoutSubviews {
    %orig;
    WTSInstallTouchTrackerIfNeeded(self);
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    WTVerticalSwipeManager *tracker = objc_getAssociatedObject(self, kWTTouchTrackerKey);
    if (tracker && touches.count > 0) {
        UITouch *touch = touches.anyObject;
        tracker.touchState.startPoint = [touch locationInView:self];
        tracker.touchState.startTime = [[NSDate date] timeIntervalSince1970];
        tracker.touchState.directionLocked = NO;
        tracker.touchState.verticalSwipeDetected = NO;
        WTSLog(@"Touch began at (%.1f, %.1f)", tracker.touchState.startPoint.x, tracker.touchState.startPoint.y);
    }
    %orig;
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    WTSProcessTouchMovedForView(self, touches);
    %orig;
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    WTVerticalSwipeManager *tracker = objc_getAssociatedObject(self, kWTTouchTrackerKey);
    if (tracker) {
        WTSLog(@"Touch ended, resetting state");
        tracker.touchState.directionLocked = NO;
        tracker.touchState.verticalSwipeDetected = NO;
    }
    %orig;
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    WTVerticalSwipeManager *tracker = objc_getAssociatedObject(self, kWTTouchTrackerKey);
    if (tracker) {
        WTSLog(@"Touch cancelled, resetting state");
        tracker.touchState.directionLocked = NO;
        tracker.touchState.verticalSwipeDetected = NO;
    }
    %orig;
}
%end

%hook WXKBKeyContainerView
- (void)didMoveToWindow {
    %orig;
    WTSInstallTouchTrackerIfNeeded(self);
}

- (void)layoutSubviews {
    %orig;
    WTSInstallTouchTrackerIfNeeded(self);
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    WTVerticalSwipeManager *tracker = objc_getAssociatedObject(self, kWTTouchTrackerKey);
    if (tracker && touches.count > 0) {
        UITouch *touch = touches.anyObject;
        tracker.touchState.startPoint = [touch locationInView:self];
        tracker.touchState.startTime = [[NSDate date] timeIntervalSince1970];
        tracker.touchState.directionLocked = NO;
        tracker.touchState.verticalSwipeDetected = NO;
        WTSLog(@"Touch began at (%.1f, %.1f)", tracker.touchState.startPoint.x, tracker.touchState.startPoint.y);
    }
    %orig;
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    WTSProcessTouchMovedForView(self, touches);
    %orig;
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    WTVerticalSwipeManager *tracker = objc_getAssociatedObject(self, kWTTouchTrackerKey);
    if (tracker) {
        WTSLog(@"Touch ended, resetting state");
        tracker.touchState.directionLocked = NO;
        tracker.touchState.verticalSwipeDetected = NO;
    }
    %orig;
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    WTVerticalSwipeManager *tracker = objc_getAssociatedObject(self, kWTTouchTrackerKey);
    if (tracker) {
        WTSLog(@"Touch cancelled, resetting state");
        tracker.touchState.directionLocked = NO;
        tracker.touchState.verticalSwipeDetected = NO;
    }
    %orig;
}
%end

%hook WBKeyView
- (void)didMoveToWindow {
    %orig;
    WTSInstallTouchTrackerIfNeeded(self);
}

- (void)layoutSubviews {
    %orig;
    WTSInstallTouchTrackerIfNeeded(self);
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    WTVerticalSwipeManager *tracker = objc_getAssociatedObject(self, kWTTouchTrackerKey);
    if (tracker && touches.count > 0) {
        UITouch *touch = touches.anyObject;
        tracker.touchState.startPoint = [touch locationInView:self];
        tracker.touchState.startTime = [[NSDate date] timeIntervalSince1970];
        tracker.touchState.directionLocked = NO;
        tracker.touchState.verticalSwipeDetected = NO;
        WTSLog(@"Touch began at (%.1f, %.1f)", tracker.touchState.startPoint.x, tracker.touchState.startPoint.y);
    }
    %orig;
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    WTSProcessTouchMovedForView(self, touches);
    %orig;
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    WTVerticalSwipeManager *tracker = objc_getAssociatedObject(self, kWTTouchTrackerKey);
    if (tracker) {
        WTSLog(@"Touch ended, resetting state");
        tracker.touchState.directionLocked = NO;
        tracker.touchState.verticalSwipeDetected = NO;
    }
    %orig;
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    WTVerticalSwipeManager *tracker = objc_getAssociatedObject(self, kWTTouchTrackerKey);
    if (tracker) {
        WTSLog(@"Touch cancelled, resetting state");
        tracker.touchState.directionLocked = NO;
        tracker.touchState.verticalSwipeDetected = NO;
    }
    %orig;
}
%end

%hook WXKBKeyView
- (void)didMoveToWindow {
    %orig;
    WTSInstallTouchTrackerIfNeeded(self);
}

- (void)layoutSubviews {
    %orig;
    WTSInstallTouchTrackerIfNeeded(self);
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    WTVerticalSwipeManager *tracker = objc_getAssociatedObject(self, kWTTouchTrackerKey);
    if (tracker && touches.count > 0) {
        UITouch *touch = touches.anyObject;
        tracker.touchState.startPoint = [touch locationInView:self];
        tracker.touchState.startTime = [[NSDate date] timeIntervalSince1970];
        tracker.touchState.directionLocked = NO;
        tracker.touchState.verticalSwipeDetected = NO;
        WTSLog(@"Touch began at (%.1f, %.1f)", tracker.touchState.startPoint.x, tracker.touchState.startPoint.y);
    }
    %orig;
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    WTSProcessTouchMovedForView(self, touches);
    %orig;
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    WTVerticalSwipeManager *tracker = objc_getAssociatedObject(self, kWTTouchTrackerKey);
    if (tracker) {
        WTSLog(@"Touch ended, resetting state");
        tracker.touchState.directionLocked = NO;
        tracker.touchState.verticalSwipeDetected = NO;
    }
    %orig;
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    WTVerticalSwipeManager *tracker = objc_getAssociatedObject(self, kWTTouchTrackerKey);
    if (tracker) {
        WTSLog(@"Touch cancelled, resetting state");
        tracker.touchState.directionLocked = NO;
        tracker.touchState.verticalSwipeDetected = NO;
    }
    %orig;
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
            WTSLog(@"wxkeyboard tweak disabled via preferences; skipping initialization.");
            return;
        }
        if (WTSProcessIsWeTypeKeyboard()) {
            WTSLog(@"Initializing WeType hook group.");
            %init(WTSWeTypeHooks);
        } else {
            WTSLog(@"Process not matched for WeType hooks; initialization skipped.");
        }
    }
}
