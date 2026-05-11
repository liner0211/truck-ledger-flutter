# truck_ledger_flutter（卡车记账 · Flutter）

与 **Theos iOS（Swift）**、`TruckLedgerAndroid`（Kotlin）并列的 **Flutter** 工程，双端包名均为 **`com.liner0211.truckledger`**，桌面显示名 **卡车记账**。

## 环境

- 安装 **Flutter stable**（本仓库在 WSL 下可使用 `/home/liner0211/Code/.flutter_toolchain/flutter`，或改用你本机 Flutter）。
- **Android**：Android SDK + 接受许可（`flutter doctor --android-licenses`）。
- **iOS**：必须在 **macOS + Xcode** 上执行 `flutter build ios` / 归档；无法在纯 Linux/WSL 完成官方 iOS 签名构建。

## 常用命令

```bash
export PATH="/home/liner0211/Code/.flutter_toolchain/flutter/bin:$PATH"
cd /path/to/truck_ledger_flutter

flutter pub get
flutter analyze
flutter test

# Android：调试 APK
flutter build apk --debug
# 输出：build/app/outputs/flutter-apk/app-debug.apk

# Android：发布 APK（需配置 release 签名后再改 android/app/build.gradle.kts）
flutter build apk --release

# iOS（仅 Mac）
flutter build ios
```

也可执行：`./scripts/build_apk.sh`（默认使用上述 WSL 内 Flutter 路径，可通过环境变量 `FLUTTER_BIN_PATH` 覆盖）。

## 安装到设备

- **Android**：`adb install -r build/app/outputs/flutter-apk/app-debug.apk`，或在 Android Studio / VS Code 里 Run。
- **iOS**：用 Xcode 打开 `ios/Runner.xcodeproj`（或 `flutter open ios`）连接真机运行；与当前 **Theos + deb** 流程不同，Flutter iOS 走 **Xcode / TestFlight / IPA**，不会自动生成 Theos 的 deb。

## 注意

- **applicationId / Bundle ID** 与现有原生安卓工程相同，**同一台设备上不能同时安装两个包名一致的应用**；调试 Flutter 版前请先卸载 Kotlin 版或临时改掉一方包名。
- Theos 越狱直装的 **TruckLedger** 与商店/Xcode 签名的 Flutter iOS **包名若相同会冲突**，上架或侧载时请按需区分 Bundle ID。
