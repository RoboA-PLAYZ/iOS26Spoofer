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
static CFStringRef const kPreferencesDomain = CFSTR("com.roboa.ios26spoofer");
static CFStringRef const kPreferencesChangedNotification =
    CFSTR("com.roboa.ios26spoofer/preferences.changed");

typedef NS_ENUM(NSInteger, SpoofScope) {
    SpoofScopeAboutOnly,
    SpoofScopeAppsOnly,
    SpoofScopeBoth,
};

static BOOL PreferencesEnabled = YES;
static SpoofScope PreferencesScope = SpoofScopeBoth;

static void ReloadPreferences(void) {
    CFPreferencesAppSynchronize(kPreferencesDomain);

    CFTypeRef enabled = CFPreferencesCopyAppValue(CFSTR("enabled"),
                                                   kPreferencesDomain);
    PreferencesEnabled = !enabled ||
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

%hook UIDevice

- (NSString *)systemVersion {
    return ShouldSpoofCurrentProcess() ? kSpoofedVersion : %orig;
}

%end

%hook NSProcessInfo

- (NSOperatingSystemVersion)operatingSystemVersion {
    return ShouldSpoofCurrentProcess() ? kSpoofedOperatingSystemVersion : %orig;
}

- (NSString *)operatingSystemVersionString {
    return ShouldSpoofCurrentProcess() ? kSpoofedVersionString : %orig;
}

- (BOOL)isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion)requestedVersion {
    return ShouldSpoofCurrentProcess()
        ? SpoofedVersionIsAtLeast(requestedVersion)
        : %orig;
}

%end

static CFTypeRef ReplacedMGCopyAnswer(CFStringRef key) {
    if (ShouldSpoofCurrentProcess() && key &&
        CFGetTypeID(key) == CFStringGetTypeID()) {
        if (IsVersionKey(key)) {
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
    // A custom constructor disables Logos' automatic default-group setup.
    // Initialize the UIDevice and NSProcessInfo hooks explicitly.
    %init;

    ReloadPreferences();
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

    void *systemVersionDictionary =
        dlsym(RTLD_DEFAULT, "_CFCopySystemVersionDictionary");
    if (systemVersionDictionary) {
        MSHookFunction(systemVersionDictionary,
                       (void *)&ReplacedCFCopySystemVersionDictionary,
                       (void **)&OriginalCFCopySystemVersionDictionary);
    }
}
