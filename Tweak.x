#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <substrate.h>
#import <dlfcn.h>

typedef CFTypeRef (*MGCopyAnswerFunction)(CFStringRef key);
typedef CFStringRef (*MGGetStringAnswerFunction)(CFStringRef key);
typedef CFDictionaryRef (*CFCopySystemVersionDictionaryFunction)(void);

static MGCopyAnswerFunction OriginalMGCopyAnswer;
static MGGetStringAnswerFunction OriginalMGGetStringAnswer;
static CFCopySystemVersionDictionaryFunction OriginalCFCopySystemVersionDictionary;
static void *MobileGestaltHandle;

static NSString *const kSpoofedVersion = @"26.0";
static NSString *const kSpoofedVersionString = @"Version 26.0 (Build 23A000)";
static NSString *RealSystemVersion;
static CFStringRef const kPreferencesDomain = CFSTR("com.roboa.ios26spoofer");
static CFStringRef const kPreferencesChangedNotification =
    CFSTR("com.roboa.ios26spoofer/preferences.changed");

typedef NS_ENUM(NSInteger, SpoofScope) {
    SpoofScopeAboutOnly,
    SpoofScopeAppsOnly,
    SpoofScopeBoth,
};

static BOOL PreferencesEnabled = NO;
static SpoofScope PreferencesScope = SpoofScopeBoth;
static BOOL IsWritingDiagnostic;

static NSString *ScopeName(void) {
    switch (PreferencesScope) {
        case SpoofScopeAboutOnly:
            return @"about";
        case SpoofScopeAppsOnly:
            return @"apps";
        case SpoofScopeBoth:
            return @"both";
    }
    return @"unknown";
}

static void AppendDiagnostic(NSString *event) {
    if (IsWritingDiagnostic || !event) {
        return;
    }

    IsWritingDiagnostic = YES;
    @autoreleasepool {
        CFTypeRef existingValue = CFPreferencesCopyAppValue(
            CFSTR("diagnosticLog"), kPreferencesDomain);
        NSString *existing = existingValue &&
            CFGetTypeID(existingValue) == CFStringGetTypeID()
            ? (__bridge NSString *)existingValue
            : @"";
        NSString *process = [[NSProcessInfo processInfo] processName] ?: @"?";
        NSString *line = [NSString stringWithFormat:@"%@ [%@] %@\n",
            [NSDate date], process, event];
        NSString *updated = [existing stringByAppendingString:line];
        if ([updated length] > 12000) {
            updated = [updated substringFromIndex:[updated length] - 12000];
        }

        CFPreferencesSetAppValue(CFSTR("diagnosticLog"),
            (__bridge CFStringRef)updated, kPreferencesDomain);
        CFPreferencesAppSynchronize(kPreferencesDomain);
        if (existingValue) {
            CFRelease(existingValue);
        }
    }
    IsWritingDiagnostic = NO;
}

static void ReloadPreferences(void) {
    CFPreferencesAppSynchronize(kPreferencesDomain);

    CFTypeRef initialized = CFPreferencesCopyAppValue(
        CFSTR("initializedForVersion120"), kPreferencesDomain);
    BOOL needsInitialization = !initialized ||
        CFGetTypeID(initialized) != CFBooleanGetTypeID() ||
        !CFBooleanGetValue((CFBooleanRef)initialized);
    if (initialized) {
        CFRelease(initialized);
    }
    BOOL isSettings = [[[NSBundle mainBundle] bundleIdentifier]
        isEqualToString:@"com.apple.Preferences"];
    if (needsInitialization && isSettings) {
        CFPreferencesSetAppValue(CFSTR("enabled"), kCFBooleanFalse,
                                 kPreferencesDomain);
        CFPreferencesSetAppValue(CFSTR("initializedForVersion120"),
                                 kCFBooleanTrue, kPreferencesDomain);
        CFPreferencesAppSynchronize(kPreferencesDomain);
    }

    CFTypeRef enabled = CFPreferencesCopyAppValue(CFSTR("enabled"),
                                                   kPreferencesDomain);
    PreferencesEnabled = enabled &&
        (CFGetTypeID(enabled) == CFBooleanGetTypeID() &&
         CFBooleanGetValue((CFBooleanRef)enabled));
    if (enabled) {
        CFRelease(enabled);
    }

    CFTypeRef scope = CFPreferencesCopyAppValue(CFSTR("scope"),
                                                 kPreferencesDomain);
    PreferencesScope = SpoofScopeBoth;
    if (scope && CFGetTypeID(scope) == CFStringGetTypeID()) {
        if (CFEqual(scope, CFSTR("about"))) {
            PreferencesScope = SpoofScopeAboutOnly;
        } else if (CFEqual(scope, CFSTR("apps"))) {
            PreferencesScope = SpoofScopeAppsOnly;
        }
    }
    if (scope) {
        CFRelease(scope);
    }
}

static void PreferencesChanged(CFNotificationCenterRef center, void *observer,
                               CFStringRef name, const void *object,
                               CFDictionaryRef userInfo) {
    ReloadPreferences();
    AppendDiagnostic([NSString stringWithFormat:
        @"preferences changed; enabled=%@ scope=%@",
        PreferencesEnabled ? @"yes" : @"no", ScopeName()]);
}

static BOOL ShouldSpoofCurrentProcess(void) {
    if (!PreferencesEnabled) {
        return NO;
    }

    BOOL isSettings = [[[NSBundle mainBundle] bundleIdentifier]
        isEqualToString:@"com.apple.Preferences"];
    switch (PreferencesScope) {
        case SpoofScopeAboutOnly:
            return isSettings;
        case SpoofScopeAppsOnly:
            return !isSettings;
        case SpoofScopeBoth:
            return YES;
    }
    return NO;
}

static BOOL IsVersionKey(CFStringRef key) {
    return CFEqual(key, CFSTR("ProductVersion")) ||
           CFEqual(key, CFSTR("HumanReadableProductVersionString"));
}

static const NSOperatingSystemVersion kSpoofedOperatingSystemVersion = {
    .majorVersion = 26,
    .minorVersion = 0,
    .patchVersion = 0,
};

static BOOL SpoofedVersionIsAtLeast(NSOperatingSystemVersion requestedVersion) {
    if (kSpoofedOperatingSystemVersion.majorVersion != requestedVersion.majorVersion) {
        return kSpoofedOperatingSystemVersion.majorVersion > requestedVersion.majorVersion;
    }
    if (kSpoofedOperatingSystemVersion.minorVersion != requestedVersion.minorVersion) {
        return kSpoofedOperatingSystemVersion.minorVersion > requestedVersion.minorVersion;
    }
    return kSpoofedOperatingSystemVersion.patchVersion >= requestedVersion.patchVersion;
}

static BOOL LoggedUIDeviceHook;
static BOOL LoggedOperatingSystemVersionHook;
static BOOL LoggedOperatingSystemVersionStringHook;
static BOOL LoggedAtLeastVersionHook;
static BOOL LoggedMGCopyAnswerHook;
static BOOL LoggedMGGetStringAnswerHook;
static BOOL LoggedSystemVersionDictionaryHook;
static BOOL LoggedAboutUIHook;

static BOOL IsSettingsProcess(void) {
    return [[[NSBundle mainBundle] bundleIdentifier]
        isEqualToString:@"com.apple.Preferences"];
}

static NSString *SpoofedAboutLabelText(NSString *text) {
    if (!text || !RealSystemVersion || !IsSettingsProcess() ||
        !ShouldSpoofCurrentProcess() ||
        [text rangeOfString:RealSystemVersion].location == NSNotFound) {
        return text;
    }

    if (!LoggedAboutUIHook) {
        LoggedAboutUIHook = YES;
        AppendDiagnostic([NSString stringWithFormat:
            @"About label rewritten; original=%@ spoofed=%@",
            text, [text stringByReplacingOccurrencesOfString:RealSystemVersion
                                                  withString:kSpoofedVersion]]);
    }
    return [text stringByReplacingOccurrencesOfString:RealSystemVersion
                                           withString:kSpoofedVersion];
}

%hook UIDevice

- (NSString *)systemVersion {
    BOOL spoof = ShouldSpoofCurrentProcess();
    if (!LoggedUIDeviceHook) {
        LoggedUIDeviceHook = YES;
        AppendDiagnostic([NSString stringWithFormat:
            @"UIDevice.systemVersion called; spoof=%@",
            spoof ? @"yes" : @"no"]);
    }
    return spoof ? kSpoofedVersion : %orig;
}

%end

%hook NSProcessInfo

- (NSOperatingSystemVersion)operatingSystemVersion {
    BOOL spoof = ShouldSpoofCurrentProcess();
    if (!LoggedOperatingSystemVersionHook) {
        LoggedOperatingSystemVersionHook = YES;
        AppendDiagnostic([NSString stringWithFormat:
            @"NSProcessInfo.operatingSystemVersion called; spoof=%@",
            spoof ? @"yes" : @"no"]);
    }
    return spoof ? kSpoofedOperatingSystemVersion : %orig;
}

- (NSString *)operatingSystemVersionString {
    BOOL spoof = ShouldSpoofCurrentProcess();
    if (!LoggedOperatingSystemVersionStringHook) {
        LoggedOperatingSystemVersionStringHook = YES;
        AppendDiagnostic([NSString stringWithFormat:
            @"NSProcessInfo.operatingSystemVersionString called; spoof=%@",
            spoof ? @"yes" : @"no"]);
    }
    return spoof ? kSpoofedVersionString : %orig;
}

- (BOOL)isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion)requestedVersion {
    BOOL spoof = ShouldSpoofCurrentProcess();
    if (!LoggedAtLeastVersionHook) {
        LoggedAtLeastVersionHook = YES;
        AppendDiagnostic([NSString stringWithFormat:
            @"NSProcessInfo.isOperatingSystemAtLeastVersion called; spoof=%@",
            spoof ? @"yes" : @"no"]);
    }
    return spoof
        ? SpoofedVersionIsAtLeast(requestedVersion)
        : %orig;
}

%end

%hook UILabel

- (void)setText:(NSString *)text {
    %orig(SpoofedAboutLabelText(text));
}

- (void)setAttributedText:(NSAttributedString *)text {
    NSString *replacement = SpoofedAboutLabelText([text string]);
    if (text && ![replacement isEqualToString:[text string]]) {
        NSMutableAttributedString *rewritten = [text mutableCopy];
        NSRange range = [[rewritten string] rangeOfString:RealSystemVersion];
        while (range.location != NSNotFound) {
            [rewritten replaceCharactersInRange:range withString:kSpoofedVersion];
            range = [[rewritten string] rangeOfString:RealSystemVersion];
        }
        %orig(rewritten);
        return;
    }
    %orig(text);
}

%end

static CFTypeRef ReplacedMGCopyAnswer(CFStringRef key) {
    if (ShouldSpoofCurrentProcess() && key &&
        CFGetTypeID(key) == CFStringGetTypeID()) {
        if (IsVersionKey(key)) {
            if (!LoggedMGCopyAnswerHook) {
                LoggedMGCopyAnswerHook = YES;
                AppendDiagnostic(@"MGCopyAnswer version key called; spoof=yes");
            }
            // MGCopyAnswer follows the Copy rule, so return an owned object.
            return CFRetain((__bridge CFStringRef)kSpoofedVersion);
        }

        if (CFEqual(key, CFSTR("ProductVersionExtra"))) {
            return NULL;
        }
    }

    return OriginalMGCopyAnswer ? OriginalMGCopyAnswer(key) : NULL;
}

static CFStringRef ReplacedMGGetStringAnswer(CFStringRef key) {
    if (ShouldSpoofCurrentProcess() && key &&
        CFGetTypeID(key) == CFStringGetTypeID()) {
        if (IsVersionKey(key)) {
            if (!LoggedMGGetStringAnswerHook) {
                LoggedMGGetStringAnswerHook = YES;
                AppendDiagnostic(@"MGGetStringAnswer version key called; spoof=yes");
            }
            return (__bridge CFStringRef)kSpoofedVersion;
        }

        if (CFEqual(key, CFSTR("ProductVersionExtra"))) {
            return NULL;
        }
    }

    return OriginalMGGetStringAnswer ? OriginalMGGetStringAnswer(key) : NULL;
}

static CFDictionaryRef ReplacedCFCopySystemVersionDictionary(void) {
    CFDictionaryRef original = OriginalCFCopySystemVersionDictionary
        ? OriginalCFCopySystemVersionDictionary()
        : NULL;

    if (!ShouldSpoofCurrentProcess()) {
        return original;
    }

    if (!LoggedSystemVersionDictionaryHook) {
        LoggedSystemVersionDictionaryHook = YES;
        AppendDiagnostic(@"_CFCopySystemVersionDictionary called; spoof=yes");
    }

    CFMutableDictionaryRef spoofed = original
        ? CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, original)
        : CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                    &kCFTypeDictionaryKeyCallBacks,
                                    &kCFTypeDictionaryValueCallBacks);

    if (original) {
        CFRelease(original);
    }

    CFDictionarySetValue(spoofed, CFSTR("ProductVersion"), CFSTR("26.0"));
    CFDictionarySetValue(spoofed, CFSTR("ProductBuildVersion"), CFSTR("23A000"));
    CFDictionaryRemoveValue(spoofed, CFSTR("ProductVersionExtra"));
    return spoofed;
}

%ctor {
    RealSystemVersion = [[[UIDevice currentDevice] systemVersion] copy];
    ReloadPreferences();
    AppendDiagnostic([NSString stringWithFormat:
        @"tweak 1.2.1 loaded; bundle=%@ real=%@ enabled=%@ scope=%@",
        [[NSBundle mainBundle] bundleIdentifier] ?: @"?",
        RealSystemVersion ?: @"?",
        PreferencesEnabled ? @"yes" : @"no", ScopeName()]);

    // A custom constructor disables Logos' automatic default-group setup.
    // Initialize the UIDevice and NSProcessInfo hooks explicitly.
    %init;
    AppendDiagnostic(@"Logos UIDevice/NSProcessInfo hooks initialized");

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(), NULL, PreferencesChanged,
        kPreferencesChangedNotification, NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately);

    const char *paths[] = {
        "/usr/lib/libMobileGestalt.dylib",
        "/System/Library/PrivateFrameworks/MobileGestalt.framework/MobileGestalt",
    };

    for (size_t index = 0; index < sizeof(paths) / sizeof(paths[0]); index++) {
        MobileGestaltHandle = dlopen(paths[index], RTLD_LAZY);
        if (MobileGestaltHandle) {
            break;
        }
    }

    if (MobileGestaltHandle) {
        void *copyAnswer = dlsym(MobileGestaltHandle, "MGCopyAnswer");
        if (copyAnswer) {
            MSHookFunction(copyAnswer, (void *)&ReplacedMGCopyAnswer,
                           (void **)&OriginalMGCopyAnswer);
        }

        void *getStringAnswer = dlsym(MobileGestaltHandle, "MGGetStringAnswer");
        if (getStringAnswer) {
            MSHookFunction(getStringAnswer, (void *)&ReplacedMGGetStringAnswer,
                           (void **)&OriginalMGGetStringAnswer);
        }
    }

    AppendDiagnostic([NSString stringWithFormat:
        @"MobileGestalt loaded=%@ MGCopyAnswer=%@ MGGetStringAnswer=%@",
        MobileGestaltHandle ? @"yes" : @"no",
        OriginalMGCopyAnswer ? @"hooked" : @"missing",
        OriginalMGGetStringAnswer ? @"hooked" : @"missing"]);

    void *systemVersionDictionary =
        dlsym(RTLD_DEFAULT, "_CFCopySystemVersionDictionary");
    if (systemVersionDictionary) {
        MSHookFunction(systemVersionDictionary,
                       (void *)&ReplacedCFCopySystemVersionDictionary,
                       (void **)&OriginalCFCopySystemVersionDictionary);
    }
    AppendDiagnostic([NSString stringWithFormat:
        @"_CFCopySystemVersionDictionary=%@",
        OriginalCFCopySystemVersionDictionary ? @"hooked" : @"missing"]);
}
