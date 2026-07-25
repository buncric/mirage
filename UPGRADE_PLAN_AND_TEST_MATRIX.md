# Mirage Upgrade Plan And Test Matrix

## Goal

Make app/iOS version spoofing more complete and safer while keeping the tweak small, local-only, and compatible with rootless/roothide paths already used by the project.

## Phase 1 - Runtime Spoof Coverage

Implemented:

- Keep `NSBundle -infoDictionary` spoofing.
- Add `NSBundle -localizedInfoDictionary`.
- Add `NSBundle -objectForInfoDictionaryKey:`.
- Add `NSDictionary +dictionaryWithContentsOfFile:` for app `Info.plist` direct reads.
- Add `NSDictionary -initWithContentsOfFile:` for app `Info.plist` direct reads.
- Add `CFBundleGetValueForInfoDictionaryKey` hook for CoreFoundation readers.
- Continue spoofing both `CFBundleShortVersionString` and `CFBundleVersion`.
- Add `NSProcessInfo -operatingSystemVersion`.
- Add `NSProcessInfo -operatingSystemVersionString`.
- Keep `UIDevice -systemVersion`.

Safety rule:

- App version spoofing is only applied when the bundle executable matches the current process name. This prevents SpringBoard or Settings from accidentally seeing a spoofed version while inspecting another app.

## Phase 2 - Preferences Reliability

Implemented:

- Normalize comma decimal separators to dot.
- Handle missing preference plist without nil dictionary crashes.
- Migrate legacy bundle-id string entries to executable-name dictionary entries.
- Fix reset-to-default so it resets the modern schema, not only the old bundle-id schema.
- Send Darwin preference-change notifications from app-detail fields.
- Ensure disabling the tweak also disables iOS version spoofing.

## Phase 3 - Manual Device Test Matrix

Run on a jailbroken/rootless or roothide device after building/installing the package.

### Install

```bash
make clean package
```

Install the matching package on device, then respring.

### Basic Function Tests

- Settings opens `Mirage`.
- `Tweak Enabled` toggle persists.
- `Add 3D Menu Action` toggle persists.
- App list opens and searchable apps display bundle identifiers.
- Selecting an app shows default app version.
- Setting spoofed app version persists after leaving and re-entering the screen.
- Setting spoofed iOS version persists after leaving and re-entering the screen.
- Reset to default sets app/iOS version values to `0` and disables experimental spoofing.

### Runtime App Version Tests

Inside a target test app, validate all of these return the spoofed version:

```objc
[[NSBundle mainBundle] infoDictionary][@"CFBundleShortVersionString"]
[[NSBundle mainBundle] infoDictionary][@"CFBundleVersion"]
[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]
[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"]
[[NSBundle mainBundle] localizedInfoDictionary][@"CFBundleShortVersionString"]
CFBundleGetValueForInfoDictionaryKey(CFBundleGetMainBundle(), CFSTR("CFBundleShortVersionString"))
CFBundleGetValueForInfoDictionaryKey(CFBundleGetMainBundle(), CFSTR("CFBundleVersion"))
[NSDictionary dictionaryWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"Info" ofType:@"plist"]][@"CFBundleShortVersionString"]
```

### Runtime iOS Version Tests

Inside the same target app, validate these return the spoofed iOS version:

```objc
[[UIDevice currentDevice] systemVersion]
[[NSProcessInfo processInfo] operatingSystemVersion]
[[NSProcessInfo processInfo] operatingSystemVersionString]
```

### Safety Tests

- SpringBoard icon labels and 3D Touch menus still work.
- Settings app does not crash.
- App Store or other unrelated apps still launch normally.
- A non-target app still sees its real version.
- Turning `Tweak Enabled` off restores real app/iOS version values.
- Removing the app-specific entry or setting `0` restores real values.

## Known Limits

- Apps can still bypass this by reading raw filesystem data using lower-level APIs, parsing a cached copy, using anti-hook checks, or validating version server-side.
- Spoofing `operatingSystemVersionString` uses a synthetic string; apps that parse Apple's exact build string may need app-specific tuning.
- The project still requires a real Theos/iOS SDK build environment for full compile-time validation.
