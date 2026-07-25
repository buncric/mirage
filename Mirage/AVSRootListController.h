#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <rootless.h>
#if __has_include(<roothide.h>)
#include <roothide.h>
#else
#define jbroot(path) path
#endif

#define SPOOF_VER_PLIST @"com.buzizaa.mirage"
#define SPOOF_VER_PLIST_WITH_PATH jbroot(ROOT_PATH_NS(@"/var/mobile/Library/Preferences/com.buzizaa.mirage.plist"))
#define SPOOF_VER_OLD_PLIST_WITH_PATH jbroot(ROOT_PATH_NS(@"/var/mobile/Library/Preferences/com.0xkuj.3dappversionspoofer.plist"))
#define SPOOF_VER_SETTINGS_CHANGED_NOTIFICATION @"com.buzizaa.mirage.settingschanged"

@interface AVSRootListController : PSListController
@end
