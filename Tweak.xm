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
static NSString *const kWTLogFilePath = @"/var/mobile/Library/Preferences/wxkeyboard.log";
static NSString *const kWTLogFileBackupPath = @"/var/mobile/Library/Preferences/wxkeyboard.log.1";
static const NSUInteger kWTLogRotateThresholdBytes = 256 * 1024;

typedef struct {
    BOOL enabled;
    BOOL debugLog;
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
    });
    return &configuration;
}

static inline BOOL WTFeatureEnabled(void) {
    return WTCurrentConfiguration()->enabled;
}

static inline BOOL WTDebugLogEnabled(void) {
#ifdef DEBUG
    return WTCurrentConfiguration()->debugLog;
#else
    return NO;
#endif
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
    WTSLog(@"Launch diagnostics: enabled=%@ debugLog=%@ processName=%@ bundleIdentifier=%@ bundlePath=%@ execPath=%@",
           configuration->enabled ? @"YES" : @"NO",
           configuration->debugLog ? @"YES" : @"NO",
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

@interface WTVerticalSwipeManager : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UIView *hostView;
@property (nonatomic, strong) UISwipeGestureRecognizer *upSwipeRecognizer;
@property (nonatomic, strong) UISwipeGestureRecognizer *downSwipeRecognizer;
@end

@implementation WTVerticalSwipeManager

- (instancetype)initWithHostView:(UIView *)hostView {
    self = [super init];
    if (self) {
        _hostView = hostView;
        
        // Set up up swipe recognizer
        _upSwipeRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleUpSwipe:)];
        _upSwipeRecognizer.direction = UISwipeGestureRecognizerDirectionUp;
        _upSwipeRecognizer.numberOfTouchesRequired = 1;
        _upSwipeRecognizer.cancelsTouchesInView = NO;
        _upSwipeRecognizer.delegate = self;
        [hostView addGestureRecognizer:_upSwipeRecognizer];
        
        // Set up down swipe recognizer
        _downSwipeRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleDownSwipe:)];
        _downSwipeRecognizer.direction = UISwipeGestureRecognizerDirectionDown;
        _downSwipeRecognizer.numberOfTouchesRequired = 1;
        _downSwipeRecognizer.cancelsTouchesInView = NO;
        _downSwipeRecognizer.delegate = self;
        [hostView addGestureRecognizer:_downSwipeRecognizer];
        
        WTSLog(@"Vertical swipe gesture recognizers installed on %@", hostView);
    }
    return self;
}

- (void)dealloc {
    if (_upSwipeRecognizer) {
        [_hostView removeGestureRecognizer:_upSwipeRecognizer];
    }
    if (_downSwipeRecognizer) {
        [_hostView removeGestureRecognizer:_downSwipeRecognizer];
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if (!self.hostView) {
        return NO;
    }
    
    // Ensure WeType keyboard is active and visible
    UIInputViewController *controller = [[self class] inputControllerForResponder:self.hostView];
    if (!controller) {
        controller = [[self class] inputControllerForResponder:self.hostView.nextResponder];
    }
    if (!controller) {
        return NO;
    }
    
    // Additional check: ensure the host view is actually visible and part of the keyboard
    if (!self.hostView.window || self.hostView.hidden || self.hostView.alpha < 0.1) {
        return NO;
    }
    
    // Basic safety: ignore touches on system UI elements like emoji/clipboard panels
    if (touch.view) {
        NSString *className = NSStringFromClass(touch.view.class);
        if ([className containsString:@"UI"] && ([className containsString:@"Panel"] || [className containsString:@"Toolbar"] || [className containsString:@"Bar"])) {
            return NO;
        }
    }
    
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return NO;
}

- (void)handleUpSwipe:(UISwipeGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateRecognized) {
        WTSLog(@"Up swipe detected on %@", self.hostView);
        [[self class] switchToPreviousModeForHostView:self.hostView];
    }
}

- (void)handleDownSwipe:(UISwipeGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateRecognized) {
        WTSLog(@"Down swipe detected on %@", self.hostView);
        [[self class] switchToNextModeForHostView:self.hostView];
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
        WTSLog(@"Insufficient modes for previous/next switching (%ld available)", (long)(modes ? modes.count : 0));
        return;
    }
    
    id currentMode = [self getCurrentWeTypeInputMode:controller];
    NSString *currentModeName = [self getModeDisplayName:currentMode];
    
    // Find current mode index
    NSInteger currentIndex = -1;
    if (currentMode) {
        for (NSInteger i = 0; i < modes.count; i++) {
            if (modes[i] == currentMode) {
                currentIndex = i;
                break;
            }
        }
    }
    
    // Calculate previous index (circular)
    NSInteger previousIndex = currentIndex > 0 ? currentIndex - 1 : modes.count - 1;
    if (currentIndex == -1) {
        previousIndex = modes.count - 1; // If current not found, go to last
    }
    
    id previousMode = modes[previousIndex];
    NSString *previousModeName = [self getModeDisplayName:previousMode];
    
    if ([self setWeTypeInputMode:controller mode:previousMode]) {
        WTSLog(@"Switched to previous mode: %@ (from %@)", previousModeName, currentModeName);
    } else {
        WTSLog(@"Failed to switch to previous mode: %@", previousModeName);
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
        WTSLog(@"Insufficient modes for previous/next switching (%ld available)", (long)(modes ? modes.count : 0));
        return;
    }
    
    id currentMode = [self getCurrentWeTypeInputMode:controller];
    NSString *currentModeName = [self getModeDisplayName:currentMode];
    
    // Find current mode index
    NSInteger currentIndex = -1;
    if (currentMode) {
        for (NSInteger i = 0; i < modes.count; i++) {
            if (modes[i] == currentMode) {
                currentIndex = i;
                break;
            }
        }
    }
    
    // Calculate next index (circular)
    NSInteger nextIndex = (currentIndex + 1) % modes.count;
    if (currentIndex == -1) {
        nextIndex = 0; // If current not found, go to first
    }
    
    id nextMode = modes[nextIndex];
    NSString *nextModeName = [self getModeDisplayName:nextMode];
    
    if ([self setWeTypeInputMode:controller mode:nextMode]) {
        WTSLog(@"Switched to next mode: %@ (from %@)", nextModeName, currentModeName);
    } else {
        WTSLog(@"Failed to switch to next mode: %@", nextModeName);
    }
}

// Legacy method removed - replaced by new WeType-specific mode switching

// Legacy methods removed - replaced by new WeType-specific mode switching with proper previous/next logic

@end

static const void *kWTSwipeHandlerKey = &kWTSwipeHandlerKey;

static void WTSInstallSwipeIfNeeded(UIView *view) {
    if (!view) {
        return;
    }
    if (objc_getAssociatedObject(view, kWTSwipeHandlerKey) != nil) {
        return;
    }
    WTVerticalSwipeManager *manager = [[WTVerticalSwipeManager alloc] initWithHostView:view];
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
