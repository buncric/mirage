#include "AVSRootListController.h"
#import <spawn.h>

@implementation AVSRootListController

- (void)migrateLegacyPreferencesIfNeeded {
	NSFileManager *fileManager = [NSFileManager defaultManager];
	if (![fileManager fileExistsAtPath:SPOOF_VER_PLIST_WITH_PATH] && [fileManager fileExistsAtPath:SPOOF_VER_OLD_PLIST_WITH_PATH]) {
		[fileManager copyItemAtPath:SPOOF_VER_OLD_PLIST_WITH_PATH toPath:SPOOF_VER_PLIST_WITH_PATH error:nil];
	}
}

- (NSArray *)specifiers {
	[self migrateLegacyPreferencesIfNeeded];
	if (!_specifiers) {
		_specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
	}

	return _specifiers;
}

- (void)loadView {
    [super loadView];
}

/* read values from preferences */
- (id)readPreferenceValue:(PSSpecifier*)specifier {
	[self migrateLegacyPreferencesIfNeeded];
	NSDictionary* dict = [NSDictionary dictionaryWithContentsOfFile:SPOOF_VER_PLIST_WITH_PATH];
	id obj = [dict objectForKey:[[specifier properties] objectForKey:@"key"]];
	if(!obj)
	{
		obj = [[specifier properties] objectForKey:@"default"];
	}

	return obj;
}

/* set the value immediately when needed */
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier*)specifier {
	[self migrateLegacyPreferencesIfNeeded];
	NSMutableDictionary *settings = [NSMutableDictionary dictionaryWithContentsOfFile:SPOOF_VER_PLIST_WITH_PATH];
	if (!settings) {
		settings = [NSMutableDictionary dictionary];
	}
	[settings setObject:value forKey:specifier.properties[@"key"]];
	[settings writeToFile:SPOOF_VER_PLIST_WITH_PATH atomically:YES];
	CFStringRef notificationName = (__bridge CFStringRef)specifier.properties[@"PostNotification"];
	if (notificationName) {
		CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), notificationName, NULL, NULL, YES);
	}
}

/* default settings and repsring right after. files to be deleted are specified in this function */
-(void)defaultsettings:(PSSpecifier*)specifier {
	UIAlertController* alertController = [UIAlertController alertControllerWithTitle:@"Xác nhận"
    									                    message:@"Thao tác này sẽ khôi phục cài đặt Mirage về mặc định.\nBạn có chắc chắn không?" 
    														preferredStyle:UIAlertControllerStyleAlert];
	/* prepare function for "yes" button */
	UIAlertAction* OKAction = [UIAlertAction actionWithTitle:@"Có" style:UIAlertActionStyleDefault
    		handler:^(UIAlertAction * action) {
				[[NSFileManager defaultManager] removeItemAtURL:[NSURL fileURLWithPath:SPOOF_VER_PLIST_WITH_PATH] error: nil];
				[[NSFileManager defaultManager] removeItemAtURL:[NSURL fileURLWithPath:SPOOF_VER_OLD_PLIST_WITH_PATH] error: nil];
    			[self reload];
				UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Thông báo"
				message:@"Đã khôi phục cài đặt mặc định.\nVui lòng respring thiết bị" 
				preferredStyle:UIAlertControllerStyleAlert];
				UIAlertAction* DoneAction =  [UIAlertAction actionWithTitle:@"Respring ngay" style:UIAlertActionStyleDefault
    			handler:^(UIAlertAction * action) {
					[self respring];
				}];
				[alert addAction:DoneAction];
				[self presentViewController:alert animated:YES completion:nil];
	}];
	/* prepare function for "no" button" */
	UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Không" style: UIAlertActionStyleCancel handler:^(UIAlertAction * action) { return; }];
	/* actually assign those actions to the buttons */
	[alertController addAction:OKAction];
    [alertController addAction:cancelAction];
	/* present the dialog and wait for an answer */
	[self presentViewController:alertController animated:YES completion:nil];
	return;
}

- (void)respring {
	pid_t pid;
	const char* args[] = {"killall", "backboardd", NULL};
	posix_spawn(&pid, jbroot("/usr/bin/killall"), NULL, NULL, (char* const*)args, NULL);
}

-(void)openTwitter {
	UIApplication *application = [UIApplication sharedApplication];
	NSURL *URL = [NSURL URLWithString:@"https://www.twitter.com/buzizaa"];
	[application openURL:URL options:@{} completionHandler:^(BOOL success) {return;}];
}

-(void)donationLink {
	UIApplication *application = [UIApplication sharedApplication];
	NSURL *URL = [NSURL URLWithString:@"https://www.paypal.me/buzizaa"];
	[application openURL:URL options:@{} completionHandler:^(BOOL success) {return;}];
}

-(void)openTelegram {
	UIApplication *application = [UIApplication sharedApplication];
	NSURL *URL = [NSURL URLWithString:@"https://t.me/buzizaa"];
	[application openURL:URL options:@{} completionHandler:^(BOOL success) {return;}];
}

@end
