# Mirage

iOS tweak that spoofs app version and iOS version per app, switchable straight from the 3D Touch menu or Settings. Includes an optional forced-update blocker. Supports iOS 14.5–16.5 on rootful, rootless and roothide jailbreaks.

- **Package:** `com.buzizaa.mirage`
- **Version:** 2.0.3
- **Author:** buzizaa
- **Depends on:** [AltList](https://github.com/opa334/AltList) (`com.opa334.altlist`)

## Features

- **App version spoofing** — overrides `CFBundleShortVersionString` and `CFBundleVersion` on a per-app basis.
- **iOS version spoofing** — overrides `UIDevice.systemVersion`, `NSProcessInfo.operatingSystemVersion` and `operatingSystemVersionString`.
- **Forced-update blocker** (optional) — detects and suppresses "you must update" screens by filtering alerts, view controllers, network responses and flags stored in `NSUserDefaults`.
- **Experimental spoofing** — widens hook coverage for apps that read `Info.plist` through indirect paths.
- **3D Touch menu** — adds a version-switching action when you long-press an app icon.

Hook coverage includes `NSBundle`, `NSDictionary`, `CFBundleGetValueForInfoDictionaryKey`, `UIDevice`, `NSProcessInfo`, `NSURLSession`, `NSURLConnection`, `NSData`, `NSUserDefaults`, `NSJSONSerialization`, `SBIconView`, `UIViewController`, `UIView` and `UIApplication`.

App version spoofing only applies when the bundle executable matches the current process, so SpringBoard and Settings never read a spoofed value by accident.

## Compatibility

- iOS 14.5 – 16.5, `arm64` and `arm64e`
- Rootful, rootless and roothide (uses `ROOT_PATH_NS` / `jbroot`)

## Building

Requires [Theos](https://theos.dev) and a valid iOS SDK.

```bash
make clean package
```

The resulting `.deb` lands in `packages/`. Install it on device, then respring.

## Layout

| Path | Contents |
| --- | --- |
| `Tweak.x` / `Tweak.h` | All hook logic |
| `Mirage/` | Preferences bundle (AltList, PreferenceLoader) |
| `layout/` | Resources installed to `/Library/Application Support/Mirage.bundle` |
| `Mirage.plist` | Filter — loads into SpringBoard, UIKit, UIKitCore |
| `control` | dpkg package metadata |
| `UPGRADE_PLAN_AND_TEST_MATRIX.md` | Upgrade plan and manual test matrix |

## Known limitations

An app can still discover its real version by reading files through lower-level APIs, parsing its own cached copy, running anti-hook checks, or validating the version server-side. The `operatingSystemVersionString` value is a synthesized string, so apps that parse Apple's exact build-string format may need per-app tuning.

## License

GNU General Public License v3.0
