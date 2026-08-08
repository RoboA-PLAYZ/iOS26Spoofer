#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <substrate.h>
#import <dlfcn.h>

typedef CFTypeRef (*MGCopyAnswerFunction)(CFStringRef key);

static MGCopyAnswerFunction OriginalMGCopyAnswer;
static void *MobileGestaltHandle;

static NSString *const kSpoofedVersion = @"26.0";
static NSString *const kSpoofedVersionString = @"Version 26.0 (Build 23A000)";

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
    return kSpoofedVersion;
}

%end

%hook NSProcessInfo

- (NSOperatingSystemVersion)operatingSystemVersion {
    return kSpoofedOperatingSystemVersion;
}

- (NSString *)operatingSystemVersionString {
    return kSpoofedVersionString;
}

- (BOOL)isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion)requestedVersion {
    return SpoofedVersionIsAtLeast(requestedVersion);
}

%end

static CFTypeRef ReplacedMGCopyAnswer(CFStringRef key) {
    if (key && CFGetTypeID(key) == CFStringGetTypeID()) {
        if (CFStringCompare(key, CFSTR("ProductVersion"), 0) == kCFCompareEqualTo) {
            // MGCopyAnswer follows the Copy rule, so return an owned object.
            return CFRetain((__bridge CFStringRef)kSpoofedVersion);
        }
    }

    return OriginalMGCopyAnswer ? OriginalMGCopyAnswer(key) : NULL;
}

%ctor {
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

    if (!MobileGestaltHandle) {
        return;
    }

    void *symbol = dlsym(MobileGestaltHandle, "MGCopyAnswer");
    if (symbol) {
        MSHookFunction(symbol, (void *)&ReplacedMGCopyAnswer,
                       (void **)&OriginalMGCopyAnswer);
    }
}
