# Android 正式签名与 CI Secrets

## 本机

- `android/key.properties`（gitignore）
- `android/keystore/upload-keystore.jks`（gitignore）
- 参考：`android/key.properties.example`
- 首次生成后本地会有 `dev/android_signing_secrets.env`（gitignore），把其中变量写入 GitHub Secrets

## GitHub Secrets

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEY_ALIAS`（一般为 `upload`）
- `ANDROID_STORE_PASSWORD`
- `ANDROID_KEY_PASSWORD`

`Release Packages` 工作流构建 APK 前会写出 keystore。未配置 Secrets 时回退 debug 签名。

## 注意

换签后，已安装的 debug 签旧包需先卸载再装正式签 APK。
