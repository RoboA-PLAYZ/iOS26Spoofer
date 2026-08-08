#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <spawn.h>

extern char **environ;

static CFStringRef const kPreferencesDomain = CFSTR("com.roboa.ios26spoofer");
static CFStringRef const kPreferencesChangedNotification =
    CFSTR("com.roboa.ios26spoofer/preferences.changed");

static void Respring(void) {
    const char *sbreloadPaths[] = {
        "/var/jb/usr/bin/sbreload",
        "/usr/bin/sbreload",
    };

    for (NSUInteger index = 0;
         index < sizeof(sbreloadPaths) / sizeof(sbreloadPaths[0]); index++) {
        const char *path = sbreloadPaths[index];
        char *const arguments[] = {(char *)path, NULL};
        pid_t processIdentifier = 0;
        if (posix_spawn(&processIdentifier, path, NULL, NULL, arguments,
                        environ) == 0) {
            return;
        }
    }

    const char *killallPath = "/var/jb/usr/bin/killall";
    char *const killallArguments[] = {
        (char *)killallPath, (char *)"-9", (char *)"SpringBoard", NULL
    };
    pid_t processIdentifier = 0;
    posix_spawn(&processIdentifier, killallPath, NULL, NULL,
                killallArguments, environ);
}

@interface I26RootListController : PSListController
@end

@implementation I26RootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];
    CFPreferencesAppSynchronize(kPreferencesDomain);
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        kPreferencesChangedNotification, NULL, NULL, YES);

    NSString *key = [specifier propertyForKey:@"key"];
    if ([key isEqualToString:@"enabled"] && [value boolValue]) {
        [self performSelector:@selector(respringNow)
                   withObject:nil afterDelay:0.7];
    }
}

- (void)respringNow {
    Respring();
}

@end

@interface I26LogListController : PSListController
@end

@implementation I26LogListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Log" target:self];
        if ([_specifiers count] > 0) {
            [[_specifiers objectAtIndex:0]
                setProperty:[self currentLogText] forKey:@"footerText"];
        }
    }
    return _specifiers;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateLogText];
}

- (NSString *)currentLogText {
    CFPreferencesAppSynchronize(kPreferencesDomain);
    CFTypeRef value = CFPreferencesCopyAppValue(CFSTR("diagnosticLog"),
                                                 kPreferencesDomain);
    NSString *text = value && CFGetTypeID(value) == CFStringGetTypeID()
        ? [(__bridge NSString *)value copy]
        : @"No runtime events have been recorded yet.";

    if (value) {
        CFRelease(value);
    }
    return text;
}

- (void)updateLogText {
    if ([_specifiers count] > 0) {
        PSSpecifier *logGroup = [_specifiers objectAtIndex:0];
        [logGroup setProperty:[self currentLogText] forKey:@"footerText"];
        [self reloadSpecifier:logGroup];
    }
}

- (void)clearLog {
    CFPreferencesSetAppValue(CFSTR("diagnosticLog"), NULL,
                             kPreferencesDomain);
    CFPreferencesAppSynchronize(kPreferencesDomain);
    [self updateLogText];
}

@end
