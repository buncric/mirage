# Mirage

iOS tweak that spoofs app version and iOS version per app, switchable straight from the 3D Touch menu or Settings. Includes an optional forced-update blocker. Supports iOS 14.5–16.5 on rootful, rootless and roothide jailbreaks.

Tweak iOS (jailbreak) giả lập phiên bản ứng dụng và phiên bản iOS cho từng app riêng lẻ, điều khiển từ Cài đặt hoặc menu 3D Touch trên icon app.

- **Package:** `com.buzizaa.mirage`
- **Version:** 2.0.3
- **Author:** buzizaa
- **Phụ thuộc:** [AltList](https://github.com/opa334/AltList) (`com.opa334.altlist`)

## Tính năng

- **Giả lập phiên bản app** — ghi đè `CFBundleShortVersionString` và `CFBundleVersion` cho từng app.
- **Giả lập phiên bản iOS** — ghi đè `UIDevice.systemVersion`, `NSProcessInfo.operatingSystemVersion` và `operatingSystemVersionString`.
- **Chặn cập nhật bắt buộc** (tuỳ chọn) — nhận diện và vô hiệu hoá các màn hình "bắt buộc cập nhật" bằng cách lọc alert, view controller, phản hồi mạng và cờ trong `NSUserDefaults`.
- **Giả lập thử nghiệm** — mở rộng phạm vi hook cho các app đọc `Info.plist` qua đường vòng.
- **Menu 3D Touch** — thêm tác vụ đổi phiên bản trực tiếp khi giữ icon app.

Phạm vi hook bao gồm `NSBundle`, `NSDictionary`, `CFBundleGetValueForInfoDictionaryKey`, `UIDevice`, `NSProcessInfo`, `NSURLSession`, `NSURLConnection`, `NSData`, `NSUserDefaults`, `NSJSONSerialization`, `SBIconView`, `UIViewController`, `UIView` và `UIApplication`.

Việc giả lập phiên bản app chỉ áp dụng khi executable của bundle trùng với tiến trình hiện tại, để SpringBoard và Settings không vô tình đọc phải giá trị giả.

## Hỗ trợ

- iOS 14.5 – 16.5, kiến trúc `arm64` và `arm64e`
- Rootful, rootless và roothide (dùng `ROOT_PATH_NS` / `jbroot`)

## Build

Cần [Theos](https://theos.dev) và một iOS SDK hợp lệ.

```bash
make clean package
```

File `.deb` sẽ nằm trong thư mục `packages/`. Cài lên máy rồi respring.

## Cấu trúc

| Đường dẫn | Nội dung |
| --- | --- |
| `Tweak.x` / `Tweak.h` | Toàn bộ logic hook |
| `Mirage/` | Bundle Preferences (AltList, PreferenceLoader) |
| `layout/` | Tài nguyên cài vào `/Library/Application Support/Mirage.bundle` |
| `Mirage.plist` | Filter — nạp vào SpringBoard, UIKit, UIKitCore |
| `control` | Metadata gói dpkg |
| `UPGRADE_PLAN_AND_TEST_MATRIX.md` | Kế hoạch nâng cấp và ma trận test thủ công |

## Giới hạn đã biết

App vẫn có thể phát hiện phiên bản thật bằng cách đọc file ở tầng thấp hơn, dùng bản cache riêng, chống hook, hoặc xác thực phiên bản phía server. Chuỗi `operatingSystemVersionString` là chuỗi tổng hợp, nên app nào phân tích đúng định dạng build string của Apple có thể cần tinh chỉnh riêng.

## Giấy phép

GNU General Public License v3.0
