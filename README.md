# WESU1 Watch app (Flutter, Android)

Talks to the firmware in `smartwatch-project-trunk` (advertises as `WESU1-Lab`).

## Features
- **Scan** for BLE devices (filter "WESU1 only" on by default)
- **Remember devices**: any watch you connect to is saved; the last one
  reconnects automatically at launch; dropped links auto-retry with backoff
- **Inspect data**: live accel/gyro values (converted + raw), charts, rate,
  last raw packet in hex, scrollable/copyable packet log, pause/clear
- **Notifications** from the app: connected / disconnected, optional motion
  alert above an acceleration threshold, test button

## What the app expects from the watch (taken from main.rs)
| Item | Value |
|---|---|
| Name | `WESU1-Lab` |
| Service | `00FFEEDD-CCBB-AA99-8877-665544332211` |
| IMU characteristic (Read+Notify) | `01FFEEDD-CCBB-AA99-8877-665544332211` |
| Payload | 12 bytes, six little-endian int16: ax ay az gx gy gz |
| Scales | accel 0.061 mg/LSB (±2 g), gyro 8.75 mdps/LSB (250 dps) |

The firmware writes UUIDs to the BlueNRG little-endian, so the UUID above is
the byte array reversed. If that turns out wrong the app automatically retries
with the un-reversed form.

## Setup (EndeavourOS)
1. `flutter doctor --android-licenses` and accept everything.
2. Use a **real Android phone**: enable Developer options + USB debugging,
   plug it in, check `adb devices` (install `android-tools` and `android-udev`
   from the repos if it is not listed). The emulator has no Bluetooth.
3. `./setup.sh` then `cd wesu1_app && flutter run`

unzip wesu1_app_src.zip
cd wesu1_app_src
bash setup.sh

flutter run

## If setup.sh couldn't patch Android
Add to `android/app/src/main/AndroidManifest.xml` above `<application`:
```xml
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-feature android:name="android.hardware.bluetooth_le" android:required="true" />
```
In `android/app/build.gradle.kts` (needed by flutter_local_notifications):
```kotlin
android { compileOptions { isCoreLibraryDesugaringEnabled = true } }
dependencies { coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4") }
```

## Limitations
- The connection lives only while the app is running (Android may drop it in the
  background). A foreground service would be needed for always-on logging.
- The firmware has no writable characteristic, so the phone cannot send
  anything *to* the watch yet.
