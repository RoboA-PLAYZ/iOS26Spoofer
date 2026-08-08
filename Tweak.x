#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

// MobileGestalt is private and its declaration is not shipped in every SDK.
// Logos still needs a prototype in scope in order to hook the function.
CFTypeRef MGCopyAnswer(CFStringRef key) CF_RETURNS_RETAINED;

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

%hookf(CFTypeRef, MGCopyAnswer, CFStringRef key) {
    if (key && CFGetTypeID(key) == CFStringGetTypeID()) {
        if (CFStringCompare(key, CFSTR("ProductVersion"), 0) == kCFCompareEqualTo) {
            // MGCopyAnswer follows the Copy rule, so return an owned object.
            return CFRetain((__bridge CFStringRef)kSpoofedVersion);
        }
    }

    return %orig;
}
