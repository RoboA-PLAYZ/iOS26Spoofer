#import <Preferences/PSListController.h>

@interface I26RootListController : PSListController
@end

@implementation I26RootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

@end
