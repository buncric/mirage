#include "Tweak.h"
#import <mach-o/nlist.h>

@interface UITraitCollection ()
+(id)currentTraitCollection;
@end

BOOL isTweakEnabled, is3DMenu;

static NSDictionary *TDAVSPreferences();
static NSDictionary *TDAVSConfigForBundle(NSString *bundleID, NSString *executableName);
static NSString *TDAVSAppVersionForCurrentProcess();

static void TDAVSLog(NSString *message) {
	if (message.length == 0) {
		return;
	}

	NSString *logPath = jbroot(ROOT_PATH_NS(@"/var/mobile/Library/Preferences/com.buzizaa.mirage.log"));
	NSString *timestamp = [[NSDate date] description];
	NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown";
	NSString *line = [NSString stringWithFormat:@"%@ [%@] %@\n", timestamp, bundleID, message];
	NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:logPath];
	if (!fileHandle) {
		[line writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
		return;
	}
	[fileHandle seekToEndOfFile];
	[fileHandle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
	[fileHandle closeFile];
}

static void TDAVSMigrateLegacyPreferences() {
	NSFileManager *fileManager = [NSFileManager defaultManager];
	if (![fileManager fileExistsAtPath:SPOOF_VER_PLIST] && [fileManager fileExistsAtPath:SPOOF_VER_OLD_PLIST]) {
		[fileManager copyItemAtPath:SPOOF_VER_OLD_PLIST toPath:SPOOF_VER_PLIST error:nil];
	}
}

static void loadPrefs() { 
	TDAVSMigrateLegacyPreferences();
	NSMutableDictionary* mainPreferenceDict = [[NSMutableDictionary alloc] initWithContentsOfFile:SPOOF_VER_PLIST];
	// if we have one key that is string, we should migrate all setting once.
	// this will be called before any applaunch after respring.
	isTweakEnabled = [mainPreferenceDict objectForKey:@"isTweakEnabled"] ? [[mainPreferenceDict objectForKey:@"isTweakEnabled"] boolValue] : YES;
	is3DMenu = [mainPreferenceDict objectForKey:@"is3DMenu"] ? [[mainPreferenceDict objectForKey:@"is3DMenu"] boolValue] : YES;
}

static BOOL TDAVSCanRunUpdateBlocker() {
	static BOOL isChecking = NO;
	if (isChecking) {
		return NO;
	}
	isChecking = YES;

	NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
	NSString *processName = [[NSProcessInfo processInfo] processName] ?: @"";
	if ([bundleID isEqualToString:@"com.apple.Preferences"] || [processName isEqualToString:@"Preferences"]) {
		isChecking = NO;
		return NO;
	}
	if ([bundleID isEqualToString:@"com.apple.springboard"] || [processName isEqualToString:@"SpringBoard"]) {
		isChecking = NO;
		return NO;
	}
	NSDictionary *config = TDAVSConfigForBundle(bundleID, processName);
	BOOL canRun = isTweakEnabled && [config[SPOOF_UPDATE_BLOCKER_KEY] boolValue];
	isChecking = NO;
	return canRun;
}

static BOOL TDAVSContainsAny(NSString *text, NSArray<NSString *> *needles) {
	if (![text isKindOfClass:[NSString class]] || text.length == 0) {
		return NO;
	}
	for (NSString *needle in needles) {
		if ([text rangeOfString:needle options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound) {
			return YES;
		}
	}
	return NO;
}

static NSString *TDAVSAlertText(UIAlertController *alertController) {
	NSMutableArray<NSString *> *parts = [NSMutableArray array];
	if (alertController.title.length > 0) {
		[parts addObject:alertController.title];
	}
	if (alertController.message.length > 0) {
		[parts addObject:alertController.message];
	}
	for (UIAlertAction *action in alertController.actions) {
		if (action.title.length > 0) {
			[parts addObject:action.title];
		}
	}
	return [parts componentsJoinedByString:@"\n"];
}

static BOOL TDAVSAlertHasDismissAction(UIAlertController *alertController) {
	for (UIAlertAction *action in alertController.actions) {
		NSString *title = action.title ?: @"";
		if (action.style == UIAlertActionStyleCancel || TDAVSContainsAny(title, @[@"huỷ", @"hủy", @"không", @"bỏ qua", @"để sau", @"lúc khác", @"cancel", @"no", @"later", @"not now", @"skip", @"ignore"])) {
			return YES;
		}
	}
	return NO;
}

static BOOL TDAVSAlertHasUpdateAction(UIAlertController *alertController) {
	for (UIAlertAction *action in alertController.actions) {
		NSString *title = action.title ?: @"";
		if (TDAVSContainsAny(title, @[@"cập nhật", @"nâng cấp", @"update", @"upgrade", @"app store", @"store"])) {
			return YES;
		}
	}
	return NO;
}

static void TDAVSCollectViewText(UIView *view, NSMutableArray<NSString *> *parts) {
	if (![view isKindOfClass:[UIView class]]) {
		return;
	}

	NSMutableArray<NSString *> *viewParts = [NSMutableArray array];
	if ([view isKindOfClass:[UILabel class]]) {
		NSString *text = ((UILabel *)view).text;
		if (text.length > 0) [viewParts addObject:text];
		NSAttributedString *attributedText = ((UILabel *)view).attributedText;
		if (attributedText.string.length > 0) [viewParts addObject:attributedText.string];
	} else if ([view isKindOfClass:[UITextView class]]) {
		NSString *text = ((UITextView *)view).text;
		if (text.length > 0) [viewParts addObject:text];
	} else if ([view isKindOfClass:[UITextField class]]) {
		NSString *text = ((UITextField *)view).text ?: ((UITextField *)view).placeholder;
		if (text.length > 0) [viewParts addObject:text];
	} else if ([view isKindOfClass:[UIButton class]]) {
		UIButton *button = (UIButton *)view;
		NSString *text = [button titleForState:UIControlStateNormal] ?: button.currentTitle;
		if (text.length > 0) [viewParts addObject:text];
		NSAttributedString *attributedTitle = [button attributedTitleForState:UIControlStateNormal] ?: button.currentAttributedTitle;
		if (attributedTitle.string.length > 0) [viewParts addObject:attributedTitle.string];
	}

	NSString *accessibilityLabel = view.accessibilityLabel;
	NSString *accessibilityValue = [view.accessibilityValue isKindOfClass:[NSString class]] ? (NSString *)view.accessibilityValue : nil;
	NSString *accessibilityHint = view.accessibilityHint;
	NSString *accessibilityIdentifier = view.accessibilityIdentifier;
	if (accessibilityLabel.length > 0) [viewParts addObject:accessibilityLabel];
	if (accessibilityValue.length > 0) [viewParts addObject:accessibilityValue];
	if (accessibilityHint.length > 0) [viewParts addObject:accessibilityHint];
	if (accessibilityIdentifier.length > 0) [viewParts addObject:accessibilityIdentifier];

	for (NSString *text in viewParts) {
		if (text.length > 0) {
			[parts addObject:text];
		}
	}

	for (UIView *subview in view.subviews) {
		TDAVSCollectViewText(subview, parts);
	}
}

static NSString *TDAVSViewText(UIView *view) {
	NSMutableArray<NSString *> *parts = [NSMutableArray array];
	TDAVSCollectViewText(view, parts);
	return [parts componentsJoinedByString:@"\n"];
}

static NSInteger TDAVSVisibleTextElementCount(UIView *view) {
	if (![view isKindOfClass:[UIView class]] || view.hidden || view.alpha < 0.01) {
		return 0;
	}

	NSInteger count = 0;
	if ([view isKindOfClass:[UILabel class]]) {
		UILabel *label = (UILabel *)view;
		if (label.text.length > 0 || label.attributedText.string.length > 0) count++;
	} else if ([view isKindOfClass:[UITextView class]]) {
		if (((UITextView *)view).text.length > 0) count++;
	} else if ([view isKindOfClass:[UIButton class]]) {
		UIButton *button = (UIButton *)view;
		if (([button titleForState:UIControlStateNormal] ?: button.currentTitle).length > 0) count++;
	}

	for (UIView *subview in view.subviews) {
		count += TDAVSVisibleTextElementCount(subview);
	}
	return count;
}

static BOOL TDAVSIsLargeBlockingView(UIView *view) {
	if (![view isKindOfClass:[UIView class]] || !view.window) {
		return NO;
	}

	CGRect viewFrame = [view convertRect:view.bounds toView:view.window];
	CGFloat viewArea = CGRectGetWidth(viewFrame) * CGRectGetHeight(viewFrame);
	CGFloat windowArea = CGRectGetWidth(view.window.bounds) * CGRectGetHeight(view.window.bounds);
	return windowArea > 0 && viewArea >= windowArea * 0.35 && TDAVSVisibleTextElementCount(view) >= 2;
}

static BOOL TDAVSShouldBlockUpdateScreen(UIView *view) {
	if (!TDAVSCanRunUpdateBlocker() || ![view isKindOfClass:[UIView class]]) {
		return NO;
	}

	NSString *text = TDAVSViewText(view);
	BOOL updateSignal = TDAVSContainsAny(text, @[@"cập nhật", @"nâng cấp", @"phiên bản mới", @"phiên bản hiện tại", @"phiên bản của bạn đã cũ", @"bạn cần nâng cấp", @"update", @"upgrade", @"new version", @"latest version", @"out of date", @"unsupported version"]);
	BOOL actionSignal = TDAVSContainsAny(text, @[@"cập nhật ngay", @"nâng cấp ngay", @"update now", @"upgrade now", @"app store"]);
	BOOL oldVersionSignal = TDAVSContainsAny(text, @[@"đã cũ", @"ứng dụng đã cũ", @"version is old", @"out of date", @"unsupported"]);
	return updateSignal && (actionSignal || oldVersionSignal);
}

static BOOL TDAVSHideUpdateSubviews(UIView *view) {
	if (!TDAVSCanRunUpdateBlocker() || ![view isKindOfClass:[UIView class]]) {
		return NO;
	}

	BOOL changed = NO;
	for (UIView *subview in [view.subviews reverseObjectEnumerator]) {
		if (TDAVSShouldBlockUpdateScreen(subview) && TDAVSIsLargeBlockingView(subview)) {
			subview.hidden = YES;
			subview.userInteractionEnabled = NO;
			changed = YES;
			continue;
		}
		changed = TDAVSHideUpdateSubviews(subview) || changed;
	}
	return changed;
}

static void TDAVSBlockUpdateScreenForController(UIViewController *controller) {
	if (!TDAVSShouldBlockUpdateScreen(controller.view)) {
		TDAVSHideUpdateSubviews(controller.view);
		return;
	}

	if (controller.presentingViewController) {
		[controller dismissViewControllerAnimated:NO completion:nil];
		return;
	}

	if (controller.navigationController.viewControllers.count > 1) {
		[controller.navigationController popViewControllerAnimated:NO];
		return;
	}

	TDAVSHideUpdateSubviews(controller.view);
}

static BOOL TDAVSShouldBlockUpdateAlert(UIViewController *viewControllerToPresent) {
	if (!TDAVSCanRunUpdateBlocker() || ![viewControllerToPresent isKindOfClass:[UIAlertController class]]) {
		return NO;
	}

	UIAlertController *alertController = (UIAlertController *)viewControllerToPresent;
	NSString *text = TDAVSAlertText(alertController);
	BOOL updateSignal = TDAVSContainsAny(text, @[@"cập nhật", @"nâng cấp", @"phiên bản mới", @"phiên bản hiện tại", @"ứng dụng đã cũ", @"update", @"upgrade", @"new version", @"latest version", @"out of date", @"unsupported version"]);
	BOOL forceSignal = TDAVSContainsAny(text, @[@"bắt buộc", @"yêu cầu", @"phải cập nhật", @"không thể tiếp tục", @"vui lòng cập nhật", @"cần cập nhật", @"required", @"mandatory", @"must update", @"cannot continue", @"can't continue", @"please update", @"force update"]);
	BOOL storeSignal = TDAVSContainsAny(text, @[@"app store", @"itunes.apple.com", @"apps.apple.com", @"itms-apps"]);
	BOOL hasUpdateAction = TDAVSAlertHasUpdateAction(alertController);
	BOOL hasDismissAction = TDAVSAlertHasDismissAction(alertController);

	return updateSignal && (forceSignal || storeSignal || (hasUpdateAction && !hasDismissAction));
}

static BOOL TDAVSShouldBlockAppStoreURL(NSURL *url) {
	if (!TDAVSCanRunUpdateBlocker() || ![url isKindOfClass:[NSURL class]]) {
		return NO;
	}

	NSString *scheme = url.scheme ?: @"";
	NSString *host = url.host ?: @"";
	NSString *absoluteString = url.absoluteString ?: @"";
	return TDAVSContainsAny(scheme, @[@"itms-apps", @"itms-appss", @"itms-services"]) ||
		TDAVSContainsAny(host, @[@"apps.apple.com", @"itunes.apple.com", @"phobos.apple.com"]) ||
		(TDAVSContainsAny(absoluteString, @[@"apps.apple.com", @"itunes.apple.com"]) && TDAVSContainsAny(absoluteString, @[@"/app/", @"id"]));
}

static BOOL TDAVSIsUpdateFlagKey(NSString *key) {
	return TDAVSContainsAny(key, @[@"force_update", @"forceupdate", @"forced_update", @"must_update", @"mustupdate", @"need_update", @"needupdate", @"needs_update", @"need_upgrade", @"needupgrade", @"needs_upgrade", @"update_required", @"updaterequired", @"upgrade_required", @"upgraderequired", @"required_update", @"require_update", @"required_upgrade", @"require_upgrade", @"mandatory_update", @"mandatory_upgrade", @"is_update", @"isupdate", @"is_force", @"isforce", @"is_mandatory", @"ismandatory", @"forceUpgrade", @"force_upgrade", @"minimum_version_required"]);
}

static BOOL TDAVSIsMinimumVersionKey(NSString *key) {
	return TDAVSContainsAny(key, @[@"min_version", @"minimum_version", @"minimumVersion", @"minVersion", @"min_app_version", @"minimum_app_version", @"minimumAppVersion", @"required_version", @"requiredVersion", @"required_app_version", @"requiredAppVersion", @"latest_version", @"latestVersion", @"latest_app_version", @"latestAppVersion", @"newest_version", @"newestVersion"]);
}

static BOOL TDAVSIsVersionAllowedKey(NSString *key) {
	return TDAVSContainsAny(key, @[@"version_valid", @"versionValid", @"is_version_valid", @"isVersionValid", @"valid_version", @"validVersion", @"version_supported", @"versionSupported", @"is_version_supported", @"isVersionSupported", @"can_continue", @"canContinue"]);
}

static BOOL TDAVSIsUpdateMessageKey(NSString *key) {
	return TDAVSContainsAny(key, @[@"message", @"msg", @"title", @"content", @"description", @"desc", @"reason", @"error", @"warning", @"notice", @"alert", @"dialog"]);
}

static BOOL TDAVSIsUpdateStatusKey(NSString *key) {
	return TDAVSContainsAny(key, @[@"status", @"code", @"error_code", @"errorCode", @"type", @"action", @"screen", @"page", @"route"]);
}

static BOOL TDAVSIsUpdateText(NSString *text) {
	BOOL updateSignal = TDAVSContainsAny(text, @[@"cập nhật", @"nâng cấp", @"phiên bản mới", @"phiên bản hiện tại", @"phiên bản của bạn đã cũ", @"ứng dụng đã cũ", @"bạn cần nâng cấp", @"update", @"upgrade", @"new version", @"latest version", @"out of date", @"unsupported version"]);
	BOOL forceSignal = TDAVSContainsAny(text, @[@"bắt buộc", @"yêu cầu", @"phải cập nhật", @"không thể tiếp tục", @"vui lòng cập nhật", @"cần cập nhật", @"required", @"mandatory", @"must update", @"cannot continue", @"can't continue", @"please update", @"force update"]);
	return updateSignal && forceSignal;
}

static id TDAVSSanitizeUpdatePayload(id object) {
	if (!TDAVSCanRunUpdateBlocker()) {
		return object;
	}

	if ([object isKindOfClass:[NSDictionary class]]) {
		NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:[(NSDictionary *)object count]];
		[(NSDictionary *)object enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
			NSString *keyString = [key isKindOfClass:[NSString class]] ? (NSString *)key : [NSString stringWithFormat:@"%@", key];
			if (TDAVSIsVersionAllowedKey(keyString)) {
				result[key] = @YES;
			} else if (TDAVSIsUpdateFlagKey(keyString)) {
				result[key] = @NO;
			} else if (TDAVSIsMinimumVersionKey(keyString)) {
				result[key] = @"0.0.0";
			} else if (TDAVSContainsAny(keyString, @[@"update_url", @"updateUrl", @"appstore_url", @"appStoreUrl", @"store_url", @"storeUrl"])) {
				result[key] = @"";
			} else if ([value isKindOfClass:[NSString class]] && TDAVSIsUpdateText(value) && (TDAVSIsUpdateMessageKey(keyString) || TDAVSIsUpdateStatusKey(keyString))) {
				result[key] = @"";
			} else {
				result[key] = TDAVSSanitizeUpdatePayload(value) ?: [NSNull null];
			}
		}];
		return result;
	}

	if ([object isKindOfClass:[NSArray class]]) {
		NSMutableArray *result = [NSMutableArray arrayWithCapacity:[(NSArray *)object count]];
		for (id value in (NSArray *)object) {
			[result addObject:TDAVSSanitizeUpdatePayload(value) ?: [NSNull null]];
		}
		return result;
	}

	return object;
}

static NSData *TDAVSSanitizeUpdateData(NSData *data) {
	if (!TDAVSCanRunUpdateBlocker() || ![data isKindOfClass:[NSData class]] || data.length == 0) {
		return data;
	}

	NSError *jsonError = nil;
	id object = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&jsonError];
	if (jsonError || !object) {
		return data;
	}

	id sanitizedObject = TDAVSSanitizeUpdatePayload(object);
	if (!sanitizedObject || ![NSJSONSerialization isValidJSONObject:sanitizedObject]) {
		return data;
	}

	NSData *sanitizedData = [NSJSONSerialization dataWithJSONObject:sanitizedObject options:0 error:nil];
	if (sanitizedData && sanitizedData.length != data.length) {
		TDAVSLog(@"sanitized update response payload");
	}
	return sanitizedData ?: data;
}

static BOOL TDAVSIsVersionRequestKey(NSString *key) {
	return TDAVSContainsAny(key, @[@"app_version", @"appVersion", @"app-ver", @"appver", @"current_version", @"currentVersion", @"client_version", @"clientVersion", @"version_name", @"versionName", @"bundle_version", @"bundleVersion", @"CFBundleShortVersionString", @"CFBundleVersion"]);
}

static BOOL TDAVSIsBuildRequestKey(NSString *key) {
	return TDAVSContainsAny(key, @[@"build_number", @"buildNumber", @"build_no", @"buildNo", @"version_code", @"versionCode", @"app_build", @"appBuild"]);
}

static id TDAVSRewriteVersionPayload(id object, NSString *version) {
	if (!TDAVSCanRunUpdateBlocker() || version.length == 0) {
		return object;
	}

	if ([object isKindOfClass:[NSDictionary class]]) {
		NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:[(NSDictionary *)object count]];
		[(NSDictionary *)object enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
			NSString *keyString = [key isKindOfClass:[NSString class]] ? (NSString *)key : [NSString stringWithFormat:@"%@", key];
			if (TDAVSIsVersionRequestKey(keyString) || TDAVSIsMinimumVersionKey(keyString)) {
				result[key] = version;
			} else if (TDAVSIsBuildRequestKey(keyString)) {
				result[key] = version;
			} else {
				result[key] = TDAVSRewriteVersionPayload(value, version) ?: [NSNull null];
			}
		}];
		return result;
	}

	if ([object isKindOfClass:[NSArray class]]) {
		NSMutableArray *result = [NSMutableArray arrayWithCapacity:[(NSArray *)object count]];
		for (id value in (NSArray *)object) {
			[result addObject:TDAVSRewriteVersionPayload(value, version) ?: [NSNull null]];
		}
		return result;
	}

	return object;
}

static NSData *TDAVSRewriteVersionData(NSData *data, NSString *version) {
	if (!TDAVSCanRunUpdateBlocker() || version.length == 0 || ![data isKindOfClass:[NSData class]] || data.length == 0) {
		return data;
	}

	NSError *jsonError = nil;
	id object = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&jsonError];
	if (!jsonError && object) {
		id rewrittenObject = TDAVSRewriteVersionPayload(object, version);
		if (rewrittenObject && [NSJSONSerialization isValidJSONObject:rewrittenObject]) {
			NSData *rewrittenData = [NSJSONSerialization dataWithJSONObject:rewrittenObject options:0 error:nil];
			if (rewrittenData) {
				return rewrittenData;
			}
		}
	}

	NSString *bodyString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	if (bodyString.length == 0) {
		return data;
	}

	NSMutableArray<NSString *> *parts = [NSMutableArray array];
	BOOL changed = NO;
	for (NSString *pair in [bodyString componentsSeparatedByString:@"&"]) {
		NSArray *keyValue = [pair componentsSeparatedByString:@"="];
		NSString *key = keyValue.count > 0 ? keyValue[0] : @"";
		if (TDAVSIsVersionRequestKey(key) || TDAVSIsBuildRequestKey(key)) {
			NSString *encodedVersion = [version stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]] ?: version;
			[parts addObject:[NSString stringWithFormat:@"%@=%@", key, encodedVersion]];
			changed = YES;
		} else {
			[parts addObject:pair];
		}
	}

	return changed ? [[parts componentsJoinedByString:@"&"] dataUsingEncoding:NSUTF8StringEncoding] : data;
}

static NSURL *TDAVSRewriteVersionURL(NSURL *url, NSString *version) {
	if (!TDAVSCanRunUpdateBlocker() || version.length == 0 || ![url isKindOfClass:[NSURL class]]) {
		return url;
	}

	NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
	if (!components.queryItems.count) {
		return url;
	}

	BOOL changed = NO;
	NSMutableArray<NSURLQueryItem *> *queryItems = [NSMutableArray arrayWithCapacity:components.queryItems.count];
	for (NSURLQueryItem *item in components.queryItems) {
		if (TDAVSIsVersionRequestKey(item.name) || TDAVSIsBuildRequestKey(item.name)) {
			[queryItems addObject:[NSURLQueryItem queryItemWithName:item.name value:version]];
			changed = YES;
		} else {
			[queryItems addObject:item];
		}
	}
	components.queryItems = queryItems;
	return changed ? components.URL : url;
}

static NSURLRequest *TDAVSRewriteVersionRequest(NSURLRequest *request) {
	if (!TDAVSCanRunUpdateBlocker() || ![request isKindOfClass:[NSURLRequest class]]) {
		return request;
	}

	NSString *version = TDAVSAppVersionForCurrentProcess();
	if (version.length == 0) {
		return request;
	}

	NSMutableURLRequest *mutableRequest = [request mutableCopy];
	BOOL changed = NO;
	NSURL *rewrittenURL = TDAVSRewriteVersionURL(mutableRequest.URL, version);
	if (rewrittenURL && ![rewrittenURL isEqual:mutableRequest.URL]) {
		mutableRequest.URL = rewrittenURL;
		changed = YES;
	}

	NSMutableDictionary *headers = [[mutableRequest allHTTPHeaderFields] mutableCopy] ?: [NSMutableDictionary dictionary];
	NSArray *versionHeaderKeys = @[@"X-App-Version", @"X-AppVersion", @"App-Version", @"AppVersion", @"X-Client-Version", @"Client-Version", @"X-Version", @"Version", @"CFBundleShortVersionString", @"CFBundleVersion", @"app-version", @"client-version", @"x-app-version", @"x-client-version"];
	for (NSString *headerKey in versionHeaderKeys) {
		if (headers[headerKey]) {
			[mutableRequest setValue:version forHTTPHeaderField:headerKey];
			changed = YES;
		}
	}
	[mutableRequest setValue:version forHTTPHeaderField:@"X-App-Version"];
	[mutableRequest setValue:version forHTTPHeaderField:@"X-Client-Version"];
	[mutableRequest setValue:version forHTTPHeaderField:@"App-Version"];
	changed = YES;

	NSString *userAgent = headers[@"User-Agent"];
	NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
	BOOL userAgentHasVersionSignal = TDAVSContainsAny(userAgent, @[@"version", @"Version", @"CFBundle"]);
	BOOL userAgentHasBundleSignal = bundleID.length > 0 && TDAVSContainsAny(userAgent, @[bundleID]);
	if (userAgent.length > 0 && (userAgentHasVersionSignal || userAgentHasBundleSignal)) {
		NSMutableString *rewrittenUserAgent = [userAgent mutableCopy];
		NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"([Vv]ersion/|[Vv]/|app_version=|version=)[0-9]+(\\.[0-9]+)*" options:0 error:nil];
		[regex replaceMatchesInString:rewrittenUserAgent options:0 range:NSMakeRange(0, rewrittenUserAgent.length) withTemplate:[NSString stringWithFormat:@"$1%@", version]];
		[mutableRequest setValue:rewrittenUserAgent forHTTPHeaderField:@"User-Agent"];
		changed = YES;
	}

	NSData *body = mutableRequest.HTTPBody;
	NSData *rewrittenBody = TDAVSRewriteVersionData(body, version);
	if (rewrittenBody && ![rewrittenBody isEqualToData:body]) {
		mutableRequest.HTTPBody = rewrittenBody;
		changed = YES;
	}

	if (changed) {
		NSURL *url = mutableRequest.URL;
		NSString *safePath = [NSString stringWithFormat:@"%@%@", url.host ?: @"", url.path ?: @""];
		TDAVSLog([NSString stringWithFormat:@"rewrote request version=%@ method=%@ target=%@", version, mutableRequest.HTTPMethod ?: @"GET", safePath.length > 0 ? safePath : @"unknown"]);
	}

	return mutableRequest;
}

static NSDictionary *TDAVSPreferences() {
	NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:SPOOF_VER_PLIST];
	return [prefs isKindOfClass:[NSDictionary class]] ? prefs : @{};
}

static BOOL TDAVSIsDefaultValue(id value) {
	if (![value isKindOfClass:[NSString class]]) {
		return YES;
	}
	NSString *stringValue = [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	return stringValue.length == 0 || [stringValue isEqualToString:@"0"] || [stringValue isEqualToString:@"0.0"];
}

static NSString *TDAVSNormalizedVersion(id value) {
	if (![value isKindOfClass:[NSString class]]) {
		return nil;
	}
	NSString *stringValue = [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	stringValue = [stringValue stringByReplacingOccurrencesOfString:@"," withString:@"."];
	return TDAVSIsDefaultValue(stringValue) ? nil : stringValue;
}

static NSString *TDAVSAppVersionForCurrentProcess() {
	if (!isTweakEnabled) {
		return nil;
	}

	NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
	NSString *processName = [[NSProcessInfo processInfo] processName];
	NSDictionary *config = TDAVSConfigForBundle(bundleID, processName);
	return TDAVSNormalizedVersion(config[SPOOF_APP_VERSION_KEY]);
}

static NSDictionary *TDAVSConfigForBundle(NSString *bundleID, NSString *executableName) {
	NSDictionary *prefs = TDAVSPreferences();
	if (executableName.length > 0 && [prefs[executableName] isKindOfClass:[NSDictionary class]]) {
		NSDictionary *candidate = prefs[executableName];
		NSString *candidateBundle = candidate[SPOOF_APP_BUNDLE_KEY];
		if (bundleID.length == 0 || candidateBundle.length == 0 || [candidateBundle isEqualToString:bundleID]) {
			return candidate;
		}
	}

	for (NSString *key in prefs) {
		id candidate = prefs[key];
		if ([candidate isKindOfClass:[NSDictionary class]] && [candidate[SPOOF_APP_BUNDLE_KEY] isEqualToString:bundleID]) {
			return candidate;
		}
	}

	// Legacy preferences stored bundle identifier -> spoofed version string.
	if (bundleID.length > 0 && [prefs[bundleID] isKindOfClass:[NSString class]]) {
		return @{ SPOOF_APP_BUNDLE_KEY: bundleID, SPOOF_APP_VERSION_KEY: prefs[bundleID] };
	}

	return nil;
}

static BOOL TDAVSIsApplicationURL(NSURL *bundleURL) {
	NSString *absoluteString = bundleURL.absoluteString;
	return [absoluteString containsString:@"/Application/"] || [absoluteString containsString:@"/Applications/"];
}

static NSString *TDAVSAppVersionForInfo(NSDictionary *infoDictionary, NSURL *bundleURL) {
	if (!isTweakEnabled || ![infoDictionary isKindOfClass:[NSDictionary class]] || !TDAVSIsApplicationURL(bundleURL)) {
		return nil;
	}

	NSString *bundleID = infoDictionary[@"CFBundleIdentifier"];
	NSString *executableName = infoDictionary[@"CFBundleExecutable"] ?: [[NSProcessInfo processInfo] processName];
	if (executableName.length > 0 && ![executableName isEqualToString:[[NSProcessInfo processInfo] processName]]) {
		return nil;
	}

	NSDictionary *config = TDAVSConfigForBundle(bundleID, executableName);
	return TDAVSNormalizedVersion(config[SPOOF_APP_VERSION_KEY]);
}

static NSDictionary *TDAVSModifiedInfoDictionary(NSDictionary *dictionary, NSURL *bundleURL) {
	NSString *versionToSpoof = TDAVSAppVersionForInfo(dictionary, bundleURL);
	if (!versionToSpoof) {
		return nil;
	}

	NSMutableDictionary *moddedDictionary = [NSMutableDictionary dictionaryWithDictionary:dictionary];
	[moddedDictionary setValue:versionToSpoof forKey:@"CFBundleShortVersionString"];
	[moddedDictionary setValue:versionToSpoof forKey:@"CFBundleVersion"];
	return moddedDictionary;
}

static NSString *TDAVSiOSVersionForCurrentProcess() {
	if (!isTweakEnabled) {
		return nil;
	}

	NSString *processName = [[NSProcessInfo processInfo] processName];
	NSDictionary *config = TDAVSConfigForBundle(nil, processName);
	return TDAVSNormalizedVersion(config[SPOOF_IOS_VERSION_KEY]);
}

static NSOperatingSystemVersion TDAVSOperatingSystemVersionFromString(NSString *versionString, NSOperatingSystemVersion fallback) {
	NSArray *components = [versionString componentsSeparatedByString:@"."];
	if (components.count < 1) {
		return fallback;
	}

	NSOperatingSystemVersion version = fallback;
	version.majorVersion = components.count > 0 ? [components[0] integerValue] : fallback.majorVersion;
	version.minorVersion = components.count > 1 ? [components[1] integerValue] : 0;
	version.patchVersion = components.count > 2 ? [components[2] integerValue] : 0;
	return version;
}

%hook SBIconView
- (void)setApplicationShortcutItems:(NSArray *)shortcutItems {
	#define TDAVS_ASSET_DARK jbroot(ROOT_PATH_NS(@"/Library/Application Support/Mirage.bundle/fakeverblack@2x.png"))
	#define TDAVS_ASSET_WHITE jbroot(ROOT_PATH_NS(@"/Library/Application Support/Mirage.bundle/fakeverwhite@2x.png"))
	if (!is3DMenu) {
		return %orig;
	}

	NSMutableArray *editedItems = [NSMutableArray arrayWithArray:shortcutItems ? : @[]];
	if (![self.icon isKindOfClass:%c(SBFolderIcon)] && ![self.icon isKindOfClass:%c(SBWidgetIcon)]) { 
		SBSApplicationShortcutItem *shortcutItems = [[%c(SBSApplicationShortcutItem) alloc] init];
		shortcutItems.localizedTitle = @"Giả lập phiên bản app";
		shortcutItems.type = SPOOF_VER_TWEAK_BUNDLE;
		NSData *imgData = UIImagePNGRepresentation([UIImage imageNamed:TDAVS_ASSET_DARK]);
		//dark mode check
		NSOperatingSystemVersion versionToCheck;
        versionToCheck.majorVersion = 13;
        versionToCheck.minorVersion = 5;
        versionToCheck.patchVersion = 0;
		BOOL iosContainsDarkmode = [[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:versionToCheck];
		if (iosContainsDarkmode) {
			if ([[UITraitCollection currentTraitCollection] userInterfaceStyle] == UIUserInterfaceStyleDark) {
				imgData = UIImagePNGRepresentation([UIImage imageNamed:TDAVS_ASSET_WHITE]);
			}
		}
		if (imgData) {
			SBSApplicationShortcutCustomImageIcon *iconImage = [[%c(SBSApplicationShortcutCustomImageIcon) alloc] initWithImagePNGData:imgData];
			shortcutItems.icon = iconImage;
		}
		if (shortcutItems) {
			[editedItems addObject:shortcutItems];
		}
	}
 	%orig(editedItems);
}

+ (void)activateShortcut:(SBSApplicationShortcutItem *)item withBundleIdentifier:(NSString *)bundleID forIconView:(SBIconView *)iconView {
    if ([item.type isEqualToString:SPOOF_VER_TWEAK_BUNDLE]) {
		//i have no idea why sometimes the apdefaultversion is null, the bundle is correct and works the same as in settings..
		NSURL *appFolderURL = [iconView applicationBundleURLForShortcuts];
		NSURL *infoPlistURL = [appFolderURL URLByAppendingPathComponent:@"Info.plist"];
		NSDictionary *infoDictionary = [NSDictionary dictionaryWithContentsOfFile:infoPlistURL.path];
		NSString *appDefaultVersion = infoDictionary[@"CFBundleShortVersionString"];
		NSString *appExecName = infoDictionary[@"CFBundleExecutable"];
		NSMutableDictionary *prefPlist = [NSMutableDictionary dictionaryWithContentsOfFile:SPOOF_VER_PLIST];
		if (!prefPlist) {
			prefPlist = [NSMutableDictionary dictionary];
		}
		//support old prefs
		NSString *currentVer = prefPlist[appExecName] ? prefPlist[appExecName][SPOOF_APP_VERSION_KEY] : prefPlist[bundleID] ? prefPlist[bundleID] : nil;
		NSString *currentiOSSpoofedVersion = prefPlist[appExecName] ? prefPlist[appExecName][SPOOF_IOS_VERSION_KEY] : nil;
		UISwitch *experimentalSpoofSwitch = [[UISwitch alloc] init];

		if (currentVer == nil || [currentVer isEqualToString:@"0"]) {
			currentVer = @"Mặc định";
		}

		if (currentiOSSpoofedVersion == nil || [currentiOSSpoofedVersion isEqualToString:@"0"]) {
			currentiOSSpoofedVersion = @"Mặc định";
		}

	    UIAlertController* alertController = [UIAlertController alertControllerWithTitle:@"Mirage"
																	message:[NSString stringWithFormat:@"CẢNH BÁO: Tính năng này có thể làm app hoạt động không ổn định.\nBundle ID: %@\nPhiên bản đang giả lập: %@\nPhiên bản iOS đang giả lập: %@\nPhiên bản gốc của app: %@\n\nBạn muốn giả lập phiên bản nào?\n\n\n",bundleID,currentVer,currentiOSSpoofedVersion,appDefaultVersion]
																	preferredStyle:UIAlertControllerStyleAlert];

		[alertController addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
			if ([currentVer isEqualToString:@"Mặc định"]) {
				textField.placeholder = @"Nhập phiên bản app"; 
			} else {
				textField.text = currentVer;
			}
			
			textField.keyboardType = UIKeyboardTypeDecimalPad;
		}];

		[alertController addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
			if ([currentiOSSpoofedVersion isEqualToString:@"Mặc định"]) {
				textField.placeholder = @"Nhập phiên bản iOS (tuỳ chọn)"; 
			} else {
				textField.text = currentiOSSpoofedVersion;
			}
			
			textField.keyboardType = UIKeyboardTypeDecimalPad;
		}];

		UIAlertAction *setNewValue = [UIAlertAction actionWithTitle:@"Áp dụng phiên bản giả lập" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
			NSString *spoofedAppVersion = ([[alertController textFields][0] text].length > 0) ? [[alertController textFields][0] text] : prefPlist[bundleID] ? prefPlist[bundleID] : @"0";
			NSString *spoofediOSVersion = ([[alertController textFields][1] text].length > 0) ? [[alertController textFields][1] text] : @"0";
			//support regions that have comma instead of dot 0-0
			if (prefPlist[appExecName] == nil) {
				prefPlist[appExecName] = [NSMutableDictionary dictionary];
			}
			[prefPlist[appExecName] setObject:bundleID forKey:SPOOF_APP_BUNDLE_KEY];
			[prefPlist[appExecName] setObject:[spoofedAppVersion stringByReplacingOccurrencesOfString:@"," withString:@"."] forKey:SPOOF_APP_VERSION_KEY];
			[prefPlist[appExecName] setObject:spoofediOSVersion forKey:SPOOF_IOS_VERSION_KEY];
			[prefPlist[appExecName] setObject:@(experimentalSpoofSwitch.isOn) forKey:SPOOF_EXPERIMENTAL_KEY];
			if (!prefPlist[appExecName][SPOOF_UPDATE_BLOCKER_KEY]) {
				[prefPlist[appExecName] setObject:@(NO) forKey:SPOOF_UPDATE_BLOCKER_KEY];
			}
			if (prefPlist[bundleID] != nil) {
				[prefPlist removeObjectForKey:bundleID];
			}
			[prefPlist writeToFile:SPOOF_VER_PLIST atomically:YES]; 
		}];

		[alertController addAction:setNewValue];		

		BOOL isSwitchOn = [prefPlist[appExecName] objectForKey:SPOOF_EXPERIMENTAL_KEY] ? [[prefPlist[appExecName] objectForKey:SPOOF_EXPERIMENTAL_KEY] boolValue] : NO;
		if (isSwitchOn) {
			[experimentalSpoofSwitch setOn:YES animated:YES];
		} else {
			[experimentalSpoofSwitch setOn:NO animated:YES];
		}
		
		[alertController.view addSubview:experimentalSpoofSwitch];

		UILabel *switchLabel = [[UILabel alloc] init];
		switchLabel.text = @"GIẢ LẬP THỬ NGHIỆM";
		switchLabel.numberOfLines = 0;
		switchLabel.textAlignment = NSTextAlignmentLeft;
		switchLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
		switchLabel.font = [UIFont systemFontOfSize:12.0];

		[alertController.view addSubview:switchLabel];
		[experimentalSpoofSwitch setTranslatesAutoresizingMaskIntoConstraints:NO];
		[switchLabel setTranslatesAutoresizingMaskIntoConstraints:NO];
		NSLayoutConstraint *leadingConstraint = [NSLayoutConstraint constraintWithItem:experimentalSpoofSwitch attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual toItem:alertController.view attribute:NSLayoutAttributeLeadingMargin multiplier:1.0 constant:0];
		NSLayoutConstraint *topConstraint = [NSLayoutConstraint constraintWithItem:experimentalSpoofSwitch attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:alertController.view attribute:NSLayoutAttributeTopMargin multiplier:1.0 constant:195];
		NSLayoutConstraint *labelLeadingConstraint = [NSLayoutConstraint constraintWithItem:switchLabel attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual toItem:experimentalSpoofSwitch attribute:NSLayoutAttributeTrailing multiplier:1.0 constant:8];
		NSLayoutConstraint *labelCenterYConstraint = [NSLayoutConstraint constraintWithItem:switchLabel attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem:experimentalSpoofSwitch attribute:NSLayoutAttributeCenterY multiplier:1.0 constant:0];
		[alertController.view addConstraints:@[leadingConstraint, topConstraint, labelLeadingConstraint, labelCenterYConstraint]];

		UIAlertAction *setDefaultValue = [UIAlertAction actionWithTitle:@"Đặt lại về mặc định" style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
			//0 means use original version!
			CGFloat defaultValue = 0.0f;
			NSNumber *numberFromFloat = [NSNumber numberWithFloat:defaultValue];
			if (prefPlist[appExecName] == nil) {
				prefPlist[appExecName] = [NSMutableDictionary dictionary];
			}
			[prefPlist[appExecName] setObject:@(NO) forKey:SPOOF_EXPERIMENTAL_KEY];
			[prefPlist[appExecName] setObject:[numberFromFloat stringValue] forKey:SPOOF_APP_VERSION_KEY];
			[prefPlist[appExecName] setObject:[numberFromFloat stringValue] forKey:SPOOF_IOS_VERSION_KEY];
			[prefPlist[appExecName] setObject:@(NO) forKey:SPOOF_UPDATE_BLOCKER_KEY];
			//getting rid of old prefs
			if (prefPlist[bundleID] != nil) {
				[prefPlist removeObjectForKey:bundleID];
			}
			[prefPlist writeToFile:SPOOF_VER_PLIST atomically:YES];
		}];
		[alertController addAction:setDefaultValue];

		UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Huỷ" style: UIAlertActionStyleCancel handler:^(UIAlertAction * action) {}];

		[alertController addAction:cancelAction];

		//seriously shit hacks
		UIWindow *originalKeyWindow = [[UIApplication sharedApplication] keyWindow];
		UIResponder *responder = originalKeyWindow.rootViewController.view;
		while ([responder isKindOfClass:[UIView class]]) responder = [responder nextResponder];
		[(UIViewController *)responder presentViewController:alertController animated:YES completion:^{}];
	} else {
		%orig;
	}

}
%end

%hook UIViewController
- (void)presentViewController:(UIViewController *)viewControllerToPresent animated:(BOOL)flag completion:(void (^)(void))completion {
	if (TDAVSShouldBlockUpdateAlert(viewControllerToPresent) || TDAVSShouldBlockUpdateScreen(viewControllerToPresent.view)) {
		if (completion) {
			completion();
		}
		return;
	}
	%orig;
}

- (void)viewDidAppear:(BOOL)animated {
	%orig;
	TDAVSBlockUpdateScreenForController(self);
}
%end

%hook UIView
- (void)didMoveToWindow {
	%orig;
	if (!TDAVSCanRunUpdateBlocker() || !self.window) {
		return;
	}
	if (![self.nextResponder isKindOfClass:[UIViewController class]] && TDAVSShouldBlockUpdateScreen(self) && TDAVSIsLargeBlockingView(self)) {
		self.hidden = YES;
		self.userInteractionEnabled = NO;
		return;
	}
	TDAVSHideUpdateSubviews(self);
}
%end

%hook UIApplication
- (BOOL)openURL:(NSURL *)url {
	if (TDAVSShouldBlockAppStoreURL(url)) {
		return NO;
	}
	return %orig;
}

- (void)openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenExternalURLOptionsKey, id> *)options completionHandler:(void (^)(BOOL success))completion {
	if (TDAVSShouldBlockAppStoreURL(url)) {
		if (completion) {
			completion(NO);
		}
		return;
	}
	%orig;
}
%end

%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
	NSURLRequest *rewrittenRequest = TDAVSRewriteVersionRequest(request);
	if (completionHandler && TDAVSCanRunUpdateBlocker()) {
		void (^wrappedCompletion)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
			completionHandler(TDAVSSanitizeUpdateData(data), response, error);
		};
		return %orig(rewrittenRequest, wrappedCompletion);
	}
	return %orig(rewrittenRequest, completionHandler);
}

- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
	NSString *version = TDAVSAppVersionForCurrentProcess();
	NSURL *rewrittenURL = TDAVSRewriteVersionURL(url, version);
	if (completionHandler && TDAVSCanRunUpdateBlocker()) {
		void (^wrappedCompletion)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
			completionHandler(TDAVSSanitizeUpdateData(data), response, error);
		};
		return %orig(rewrittenURL, wrappedCompletion);
	}
	return %orig(rewrittenURL, completionHandler);
}

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request fromData:(NSData *)bodyData completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
	NSURLRequest *rewrittenRequest = TDAVSRewriteVersionRequest(request);
	NSData *rewrittenBodyData = TDAVSRewriteVersionData(bodyData, TDAVSAppVersionForCurrentProcess());
	if (completionHandler && TDAVSCanRunUpdateBlocker()) {
		void (^wrappedCompletion)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
			completionHandler(TDAVSSanitizeUpdateData(data), response, error);
		};
		return %orig(rewrittenRequest, rewrittenBodyData, wrappedCompletion);
	}
	return %orig(rewrittenRequest, rewrittenBodyData, completionHandler);
}

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request fromFile:(NSURL *)fileURL completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
	NSURLRequest *rewrittenRequest = TDAVSRewriteVersionRequest(request);
	if (completionHandler && TDAVSCanRunUpdateBlocker()) {
		void (^wrappedCompletion)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
			completionHandler(TDAVSSanitizeUpdateData(data), response, error);
		};
		return %orig(rewrittenRequest, fileURL, wrappedCompletion);
	}
	return %orig(rewrittenRequest, fileURL, completionHandler);
}
%end

%hook NSURLConnection
+ (void)sendAsynchronousRequest:(NSURLRequest *)request queue:(NSOperationQueue *)queue completionHandler:(void (^)(NSURLResponse *response, NSData *data, NSError *connectionError))handler {
	NSURLRequest *rewrittenRequest = TDAVSRewriteVersionRequest(request);
	if (handler && TDAVSCanRunUpdateBlocker()) {
		void (^wrappedHandler)(NSURLResponse *, NSData *, NSError *) = ^(NSURLResponse *response, NSData *data, NSError *connectionError) {
			handler(response, TDAVSSanitizeUpdateData(data), connectionError);
		};
		return %orig(rewrittenRequest, queue, wrappedHandler);
	}
	return %orig(rewrittenRequest, queue, handler);
}

+ (NSData *)sendSynchronousRequest:(NSURLRequest *)request returningResponse:(NSURLResponse **)response error:(NSError **)error {
	NSData *data = %orig(TDAVSRewriteVersionRequest(request), response, error);
	return TDAVSSanitizeUpdateData(data);
}

- (id)initWithRequest:(NSURLRequest *)request delegate:(id)delegate {
	return %orig(TDAVSRewriteVersionRequest(request), delegate);
}

- (id)initWithRequest:(NSURLRequest *)request delegate:(id)delegate startImmediately:(BOOL)startImmediately {
	return %orig(TDAVSRewriteVersionRequest(request), delegate, startImmediately);
}
%end

%hook NSData
+ (id)dataWithContentsOfURL:(NSURL *)url {
	NSString *version = TDAVSAppVersionForCurrentProcess();
	NSData *data = %orig(TDAVSRewriteVersionURL(url, version));
	return TDAVSSanitizeUpdateData(data);
}

+ (id)dataWithContentsOfURL:(NSURL *)url options:(NSDataReadingOptions)readOptionsMask error:(NSError **)errorPtr {
	NSString *version = TDAVSAppVersionForCurrentProcess();
	NSData *data = %orig(TDAVSRewriteVersionURL(url, version), readOptionsMask, errorPtr);
	return TDAVSSanitizeUpdateData(data);
}
%end

%hook NSUserDefaults
- (id)objectForKey:(NSString *)defaultName {
	if (TDAVSCanRunUpdateBlocker()) {
		if (TDAVSIsVersionAllowedKey(defaultName)) {
			return @YES;
		}
		if (TDAVSIsUpdateFlagKey(defaultName)) {
			return @NO;
		}
		if (TDAVSIsMinimumVersionKey(defaultName)) {
			return @"0.0.0";
		}
		if (TDAVSContainsAny(defaultName, @[@"update_url", @"updateUrl", @"appstore_url", @"appStoreUrl", @"store_url", @"storeUrl"])) {
			return @"";
		}
	}

	id value = %orig;
	if (TDAVSCanRunUpdateBlocker() && [value isKindOfClass:[NSString class]] && TDAVSIsUpdateText(value) && (TDAVSIsUpdateMessageKey(defaultName) || TDAVSIsUpdateStatusKey(defaultName))) {
		return @"";
	}
	return value;
}

- (NSString *)stringForKey:(NSString *)defaultName {
	if (TDAVSCanRunUpdateBlocker()) {
		if (TDAVSIsMinimumVersionKey(defaultName)) {
			return @"0.0.0";
		}
		if (TDAVSContainsAny(defaultName, @[@"update_url", @"updateUrl", @"appstore_url", @"appStoreUrl", @"store_url", @"storeUrl"])) {
			return @"";
		}
	}

	NSString *value = %orig;
	if (TDAVSCanRunUpdateBlocker() && TDAVSIsUpdateText(value) && (TDAVSIsUpdateMessageKey(defaultName) || TDAVSIsUpdateStatusKey(defaultName))) {
		return @"";
	}
	return value;
}

- (BOOL)boolForKey:(NSString *)defaultName {
	if (TDAVSCanRunUpdateBlocker()) {
		if (TDAVSIsVersionAllowedKey(defaultName)) {
			return YES;
		}
		if (TDAVSIsUpdateFlagKey(defaultName)) {
			return NO;
		}
	}
	return %orig;
}
%end

%hook NSJSONSerialization
+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)opt error:(NSError **)error {
	id object = %orig;
	return TDAVSSanitizeUpdatePayload(object);
}
%end

%hook NSBundle
-(NSDictionary *)infoDictionary {
	NSDictionary *dictionary = %orig;
	NSDictionary *moddedDictionary = TDAVSModifiedInfoDictionary(dictionary, [self bundleURL]);
	return moddedDictionary ?: dictionary;
}

-(NSDictionary *)localizedInfoDictionary {
	NSDictionary *dictionary = %orig;
	NSDictionary *moddedDictionary = TDAVSModifiedInfoDictionary(dictionary, [self bundleURL]);
	return moddedDictionary ?: dictionary;
}

-(id)objectForInfoDictionaryKey:(NSString *)key {
	if ([key isEqualToString:@"CFBundleShortVersionString"] || [key isEqualToString:@"CFBundleVersion"]) {
		NSString *spoofedVersion = TDAVSAppVersionForInfo([self infoDictionary], [self bundleURL]);
		if (spoofedVersion) {
			return spoofedVersion;
		}
	}
	return %orig;
}
%end

%hook NSDictionary
- (id)objectForKey:(id)aKey {
	if (TDAVSCanRunUpdateBlocker() && [aKey isKindOfClass:[NSString class]]) {
		NSString *keyString = (NSString *)aKey;
		if (TDAVSIsVersionAllowedKey(keyString)) {
			return @YES;
		}
		if (TDAVSIsUpdateFlagKey(keyString)) {
			return @NO;
		}
		if (TDAVSIsMinimumVersionKey(keyString) || TDAVSIsVersionRequestKey(keyString) || TDAVSIsBuildRequestKey(keyString)) {
			return TDAVSAppVersionForCurrentProcess() ?: @"0.0.0";
		}
		if (TDAVSContainsAny(keyString, @[@"update_url", @"updateUrl", @"appstore_url", @"appStoreUrl", @"store_url", @"storeUrl"])) {
			return @"";
		}
	}

	id value = %orig;
	if (TDAVSCanRunUpdateBlocker() && [aKey isKindOfClass:[NSString class]] && [value isKindOfClass:[NSString class]] && TDAVSIsUpdateText(value) && (TDAVSIsUpdateMessageKey(aKey) || TDAVSIsUpdateStatusKey(aKey))) {
		return @"";
	}
	return value;
}

- (id)objectForKeyedSubscript:(id)key {
	if (TDAVSCanRunUpdateBlocker() && [key isKindOfClass:[NSString class]]) {
		NSString *keyString = (NSString *)key;
		if (TDAVSIsVersionAllowedKey(keyString)) {
			return @YES;
		}
		if (TDAVSIsUpdateFlagKey(keyString)) {
			return @NO;
		}
		if (TDAVSIsMinimumVersionKey(keyString) || TDAVSIsVersionRequestKey(keyString) || TDAVSIsBuildRequestKey(keyString)) {
			return TDAVSAppVersionForCurrentProcess() ?: @"0.0.0";
		}
		if (TDAVSContainsAny(keyString, @[@"update_url", @"updateUrl", @"appstore_url", @"appStoreUrl", @"store_url", @"storeUrl"])) {
			return @"";
		}
	}

	id value = %orig;
	if (TDAVSCanRunUpdateBlocker() && [key isKindOfClass:[NSString class]] && [value isKindOfClass:[NSString class]] && TDAVSIsUpdateText(value) && (TDAVSIsUpdateMessageKey(key) || TDAVSIsUpdateStatusKey(key))) {
		return @"";
	}
	return value;
}

+ (id)dictionaryWithContentsOfFile:(NSString *)path {
	NSDictionary *dictionary = %orig;
	if (![path hasSuffix:@"/Info.plist"] || ![path containsString:@"/Application"]) {
		return dictionary;
	}

	NSDictionary *moddedDictionary = TDAVSModifiedInfoDictionary(dictionary, [NSURL fileURLWithPath:[path stringByDeletingLastPathComponent]]);
	return moddedDictionary ?: dictionary;
}

- (id)initWithContentsOfFile:(NSString *)path {
	NSDictionary *dictionary = %orig;
	if (![path hasSuffix:@"/Info.plist"] || ![path containsString:@"/Application"]) {
		return dictionary;
	}

	NSDictionary *moddedDictionary = TDAVSModifiedInfoDictionary(dictionary, [NSURL fileURLWithPath:[path stringByDeletingLastPathComponent]]);
	return moddedDictionary ? [moddedDictionary copy] : dictionary;
}
%end

%hookf(CFTypeRef, CFBundleGetValueForInfoDictionaryKey, CFBundleRef bundle, CFStringRef key) {
	CFTypeRef originalValue = %orig;
	if (!bundle || !key) {
		return originalValue;
	}

	NSString *keyString = (__bridge NSString *)key;
	if (![keyString isEqualToString:@"CFBundleShortVersionString"] && ![keyString isEqualToString:@"CFBundleVersion"]) {
		return originalValue;
	}

	CFURLRef bundleURLRef = CFBundleCopyBundleURL(bundle);
	if (!bundleURLRef) {
		return originalValue;
	}

	NSURL *bundleURL = CFBridgingRelease(bundleURLRef);
	CFURLRef executableURLRef = CFBundleCopyExecutableURL(bundle);
	if (executableURLRef) {
		NSURL *executableURL = CFBridgingRelease(executableURLRef);
		if (![executableURL.lastPathComponent isEqualToString:[[NSProcessInfo processInfo] processName]]) {
			return originalValue;
		}
	}

	CFStringRef bundleIDRef = CFBundleGetIdentifier(bundle);
	NSString *bundleID = bundleIDRef ? (__bridge NSString *)bundleIDRef : nil;
	NSDictionary *config = TDAVSConfigForBundle(bundleID, [[NSProcessInfo processInfo] processName]);
	if (![config[SPOOF_APP_BUNDLE_KEY] isEqualToString:bundleID]) {
		return originalValue;
	}
	NSString *spoofedVersion = TDAVSIsApplicationURL(bundleURL) ? TDAVSNormalizedVersion(config[SPOOF_APP_VERSION_KEY]) : nil;
	return spoofedVersion ? (__bridge CFTypeRef)spoofedVersion : originalValue;
}

%hook UIDevice
- (id)systemVersion {
	NSString *spoofediOSVersion = TDAVSiOSVersionForCurrentProcess();
	return spoofediOSVersion ?: %orig;
}
%end

%hook NSProcessInfo
- (NSOperatingSystemVersion)operatingSystemVersion {
	NSOperatingSystemVersion originalVersion = %orig;
	NSString *spoofediOSVersion = TDAVSiOSVersionForCurrentProcess();
	return spoofediOSVersion ? TDAVSOperatingSystemVersionFromString(spoofediOSVersion, originalVersion) : originalVersion;
}

- (NSString *)operatingSystemVersionString {
	NSString *spoofediOSVersion = TDAVSiOSVersionForCurrentProcess();
	return spoofediOSVersion ? [NSString stringWithFormat:@"Version %@ (Build Mirage)", spoofediOSVersion] : %orig;
}
%end

%ctor{
	loadPrefs();
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)loadPrefs, SPOOF_VER_SETTINGS_CHANGED_NOTIFICATION, NULL, CFNotificationSuspensionBehaviorCoalesce);
}
