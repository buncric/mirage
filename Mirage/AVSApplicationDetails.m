#import "AVSApplicationDetails.h"
#define SPOOF_APP_VERSION_KEY @"appVersionToSpoof"
#define SPOOF_APP_BUNDLE_KEY @"appBundle"
#define SPOOF_IOS_VERSION_KEY @"iosVersionToSpoof"
#define SPOOF_EXPERIMENTAL_KEY @"ExperimentalSpoof"
#define SPOOF_UPDATE_BLOCKER_KEY @"BlockForcedUpdate"

@interface NSWorkspace
-(id)sharedWorkspace;
-(NSString *)fullPathForApplication:(NSString *)appName;
@end

@interface AVSApplicationDetails ()
@property (nonatomic, strong) NSString *currentAppVersion;
@property (nonatomic, strong) NSString *currentiOSSpoofedVersion;
@property (nonatomic) BOOL experimentalSpoofing;
@property (nonatomic) BOOL updateBlockerEnabled;
@end

@implementation  AVSApplicationDetails
- (NSArray *)specifiers {
	if (!_specifiers) {
		_specifiers = [self loadSpecifiersFromPlistName:@"Apps" target:self];
		NSDictionary *spoofedPlistValues = [NSDictionary dictionaryWithContentsOfFile:SPOOF_VER_PLIST_WITH_PATH];
		_currentAppVersion = spoofedPlistValues[[self specifier].identifier];
		_currentiOSSpoofedVersion = nil;
		_experimentalSpoofing = NO;
		_updateBlockerEnabled = NO;
		
		for (NSDictionary *key in spoofedPlistValues) {
			if (([spoofedPlistValues[key] isKindOfClass:[NSString class]] && [(NSString *)key isEqualToString:[self specifier].identifier])) {
				// this means old settings was found.. only until i remove it
				_currentAppVersion = spoofedPlistValues[key];
			} else if ([spoofedPlistValues[key] isKindOfClass:[NSDictionary class]] && [spoofedPlistValues[key][SPOOF_APP_BUNDLE_KEY] isEqualToString:[self specifier].identifier]) {
				_currentAppVersion = spoofedPlistValues[key][SPOOF_APP_VERSION_KEY];
				_currentiOSSpoofedVersion = spoofedPlistValues[key][SPOOF_IOS_VERSION_KEY];
				_experimentalSpoofing = [spoofedPlistValues[key][SPOOF_EXPERIMENTAL_KEY] boolValue];
				_updateBlockerEnabled = [spoofedPlistValues[key][SPOOF_UPDATE_BLOCKER_KEY] boolValue];
			}
		}

		_currentAppVersion = [self checkIfDefaultVersion:_currentAppVersion];
		_currentiOSSpoofedVersion = [self checkIfDefaultVersion:_currentiOSSpoofedVersion];
		PSSpecifier *bundleID = [PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"Bundle ID: %@",[self specifier].identifier]
						  target:self
						  set:Nil
						  get:Nil
						  detail:Nil
						  cell:PSStaticTextCell
						  edit:Nil];

		PSSpecifier *currentVersion = [PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"Phiên bản đang giả lập: %@", _currentAppVersion]
						  target:self
						  set:Nil
						  get:Nil
						  detail:Nil
						  cell:PSStaticTextCell
						  edit:Nil];

		PSSpecifier *currentiOSVersion = [PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"Phiên bản iOS đang giả lập: %@", _currentiOSSpoofedVersion]
						  target:self
						  set:Nil
						  get:Nil
						  detail:Nil
						  cell:PSStaticTextCell
						  edit:Nil];

		PSSpecifier *defaultAppVersion = [PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"Phiên bản gốc của app: %@", [[NSBundle bundleWithIdentifier:[self specifier].identifier] infoDictionary][@"CFBundleShortVersionString"]]
						  target:self
						  set:Nil
						  get:Nil
						  detail:Nil
						  cell:PSStaticTextCell
						  edit:Nil];

		PSSpecifier *groupCell = [PSSpecifier preferenceSpecifierNamed:@"Giả lập phiên bản app"
						  target:self
						  set:Nil
						  get:Nil
						  detail:Nil
						  cell:PSGroupCell
						  edit:Nil];

		PSSpecifier *versionToSpoof = [PSSpecifier preferenceSpecifierNamed:@"Phiên bản app cần giả lập:"
						  target:self
						  set:@selector(setPreferenceValueLocal:specifier:)
						  get:@selector(readPreferenceValueLocal:)
						  detail:Nil
						  cell:PSEditTextCell
						  edit:Nil];

		PSSpecifier *iOSversionToSpoof = [PSSpecifier preferenceSpecifierNamed:@"Phiên bản iOS cần giả lập:"
						  target:self
						  set:@selector(setPreferenceValueLocal:specifier:)
						  get:@selector(readPreferenceValueLocal:)
						  detail:Nil
						  cell:PSEditTextCell
						  edit:Nil];

		// i had to add readpreferencevaluelocal because without that, no changes are made using the setter.. idk why
		PSSpecifier *spoofSwitchSpecifier = [PSSpecifier preferenceSpecifierNamed:@"Giả lập thử nghiệm"
                        target:self
                    	set:@selector(setPreferenceValueLocal:specifier:)
                        get:@selector(readPreferenceValueLocal:)
                        detail:Nil
                        cell:PSSwitchCell
                        edit:Nil];

		PSSpecifier *updateBlockerSpecifier = [PSSpecifier preferenceSpecifierNamed:@"Chặn cập nhật bắt buộc"
                        target:self
                    	set:@selector(setPreferenceValueLocal:specifier:)
                        get:@selector(readPreferenceValueLocal:)
                        detail:Nil
                        cell:PSSwitchCell
                        edit:Nil];
		
		PSSpecifier *defaultVersionButton = [PSSpecifier preferenceSpecifierNamed:@"Đặt lại về mặc định" target:self set:Nil get:Nil detail:Nil cell:PSButtonCell edit:Nil];
   		[defaultVersionButton setButtonAction:@selector(resetToDefaultVersion)];

		[versionToSpoof setProperty:@YES forKey:PSEnabledKey];		
		[versionToSpoof setProperty:SPOOF_VER_PLIST forKey:@"defaults"];
		[versionToSpoof setProperty:@YES forKey:PSNumberKeyboardKey];				  
		[versionToSpoof setProperty:[self specifier].identifier forKey:@"key"];
		[versionToSpoof setProperty:SPOOF_VER_SETTINGS_CHANGED_NOTIFICATION forKey:@"PostNotification"];
		[iOSversionToSpoof setProperty:SPOOF_VER_SETTINGS_CHANGED_NOTIFICATION forKey:@"PostNotification"];
		[spoofSwitchSpecifier setProperty:SPOOF_VER_SETTINGS_CHANGED_NOTIFICATION forKey:@"PostNotification"];
		[updateBlockerSpecifier setProperty:SPOOF_VER_SETTINGS_CHANGED_NOTIFICATION forKey:@"PostNotification"];
		[_specifiers addObject:bundleID];
		[_specifiers addObject:currentVersion];
		[_specifiers addObject:currentiOSVersion];
		[_specifiers addObject:defaultAppVersion];
		[_specifiers addObject:groupCell];
		[_specifiers addObject:versionToSpoof];
		[_specifiers addObject:iOSversionToSpoof];
		[_specifiers addObject:spoofSwitchSpecifier];
		[_specifiers addObject:updateBlockerSpecifier];
		[_specifiers addObject:defaultVersionButton];
	}
	return _specifiers;
}

- (id)readPreferenceValueLocal:(PSSpecifier*)specifier {
	if ([specifier.name isEqualToString:@"Giả lập thử nghiệm"]) {
		NSNumber *result = @(self.experimentalSpoofing);
		return result;
	}
	if ([specifier.name isEqualToString:@"Chặn cập nhật bắt buộc"]) {
		NSNumber *result = @(self.updateBlockerEnabled);
		return result;
	}
	if ([specifier.name isEqualToString:@"Phiên bản app cần giả lập:"]) {
		return [self.currentAppVersion isEqualToString:@"Mặc định"] ? nil : self.currentAppVersion;
	}
	if ([specifier.name isEqualToString:@"Phiên bản iOS cần giả lập:"]) {
		return [self.currentiOSSpoofedVersion isEqualToString:@"Mặc định"] ? nil : self.currentiOSSpoofedVersion;
	}
	return nil;
}

/* set the value immediately when needed */
- (void)setPreferenceValueLocal:(id)value specifier:(PSSpecifier*)specifier {
	NSMutableDictionary *settings = [NSMutableDictionary dictionaryWithContentsOfFile:SPOOF_VER_PLIST_WITH_PATH];
	if (!settings) {
		settings = [NSMutableDictionary dictionary];
	}

	NSString *bundleID = [self specifier].identifier;
	NSString *appExecName = [NSBundle bundleWithIdentifier:bundleID].infoDictionary[@"CFBundleExecutable"] ?: bundleID;
	if (![settings[appExecName] isKindOfClass:[NSMutableDictionary class]]) {
		NSDictionary *existingEntry = [settings[appExecName] isKindOfClass:[NSDictionary class]] ? settings[appExecName] : nil;
		settings[appExecName] = existingEntry ? [existingEntry mutableCopy] : [NSMutableDictionary dictionary];
	}
	if (![settings[appExecName][SPOOF_APP_BUNDLE_KEY] isEqualToString:bundleID]) {
		[settings[appExecName] setObject:bundleID forKey:SPOOF_APP_BUNDLE_KEY];
	}
	if (!settings[appExecName][SPOOF_APP_VERSION_KEY]) {
		[settings[appExecName] setObject:[self.currentAppVersion isEqualToString:@"Mặc định"] ? @"0" : self.currentAppVersion forKey:SPOOF_APP_VERSION_KEY];
	}
	if (!settings[appExecName][SPOOF_IOS_VERSION_KEY]) {
		[settings[appExecName] setObject:@"0" forKey:SPOOF_IOS_VERSION_KEY];
	}
	if (!settings[appExecName][SPOOF_EXPERIMENTAL_KEY]) {
		[settings[appExecName] setObject:@(NO) forKey:SPOOF_EXPERIMENTAL_KEY];
	}
	if (!settings[appExecName][SPOOF_UPDATE_BLOCKER_KEY]) {
		[settings[appExecName] setObject:@(NO) forKey:SPOOF_UPDATE_BLOCKER_KEY];
	}

	if ([specifier.name isEqualToString:@"Giả lập thử nghiệm"]) {
		[settings[appExecName] setObject:value forKey:SPOOF_EXPERIMENTAL_KEY];
	} else if ([specifier.name isEqualToString:@"Chặn cập nhật bắt buộc"]) {
		[settings[appExecName] setObject:value forKey:SPOOF_UPDATE_BLOCKER_KEY];
	} else if ([specifier.name isEqualToString:@"Phiên bản iOS cần giả lập:"]) {
		NSString *normalizedValue = [[NSString stringWithFormat:@"%@", value ?: @"0"] stringByReplacingOccurrencesOfString:@"," withString:@"."];
		[settings[appExecName] setObject:normalizedValue.length > 0 ? normalizedValue : @"0" forKey:SPOOF_IOS_VERSION_KEY];
	} else if ([specifier.name isEqualToString:@"Phiên bản app cần giả lập:"]) {
		NSString *normalizedValue = [[NSString stringWithFormat:@"%@", value ?: @"0"] stringByReplacingOccurrencesOfString:@"," withString:@"."];
		[settings[appExecName] setObject:normalizedValue.length > 0 ? normalizedValue : @"0" forKey:SPOOF_APP_VERSION_KEY];
	}

	// Remove legacy bundle-id entry after migrating to executable-name schema.
	[settings removeObjectForKey:bundleID];

	[settings writeToFile:SPOOF_VER_PLIST_WITH_PATH atomically:YES];
	CFStringRef notificationName = (__bridge CFStringRef)specifier.properties[@"PostNotification"];
	if (notificationName) {
		CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), notificationName, NULL, NULL, YES);
	}
}

- (BOOL)checkIfValueExists {
	NSMutableDictionary *settings = [NSMutableDictionary dictionaryWithContentsOfFile:SPOOF_VER_PLIST_WITH_PATH];
	if (!settings) {
		return NO;
	}
	for (NSDictionary *key in settings) {
		if ([settings[key] isKindOfClass:[NSDictionary class]] && [settings[key][SPOOF_APP_BUNDLE_KEY] isEqualToString:[self specifier].identifier]) {
			return YES;
		}
	}
	return NO;
}
- (NSString *)checkIfDefaultVersion:(NSString *)str {
	if (str == nil || !([str length] > 0) || [str isEqualToString:@"0"]) {
		return @"Mặc định";
	}
	return str;
}

- (void)_returnKeyPressed:(id)arg1 {
    [self.view endEditing:YES];
	[self reloadSpecifiers];
}

-(void)resetToDefaultVersion {
	//0 means use original version!
	NSMutableDictionary *prefPlist = [NSMutableDictionary dictionaryWithContentsOfFile:SPOOF_VER_PLIST_WITH_PATH];
	if (!prefPlist) {
		prefPlist = [NSMutableDictionary dictionary];
	}
	CGFloat defaultValue = 0.0f;
	NSNumber *numberFromFloat = [NSNumber numberWithFloat:defaultValue];
	NSString *bundleID = [self specifier].identifier;
	NSString *appExecName = [NSBundle bundleWithIdentifier:bundleID].infoDictionary[@"CFBundleExecutable"] ?: bundleID;
	if (![prefPlist[appExecName] isKindOfClass:[NSMutableDictionary class]]) {
		NSDictionary *existingEntry = [prefPlist[appExecName] isKindOfClass:[NSDictionary class]] ? prefPlist[appExecName] : nil;
		prefPlist[appExecName] = existingEntry ? [existingEntry mutableCopy] : [NSMutableDictionary dictionary];
	}
	[prefPlist[appExecName] setObject:bundleID forKey:SPOOF_APP_BUNDLE_KEY];
	[prefPlist[appExecName] setObject:[numberFromFloat stringValue] forKey:SPOOF_APP_VERSION_KEY];
	[prefPlist[appExecName] setObject:[numberFromFloat stringValue] forKey:SPOOF_IOS_VERSION_KEY];
	[prefPlist[appExecName] setObject:@(NO) forKey:SPOOF_EXPERIMENTAL_KEY];
	[prefPlist[appExecName] setObject:@(NO) forKey:SPOOF_UPDATE_BLOCKER_KEY];
	[prefPlist removeObjectForKey:bundleID];
	[prefPlist writeToFile:SPOOF_VER_PLIST_WITH_PATH atomically:YES];
	[self reloadSpecifiers];
}
@end
