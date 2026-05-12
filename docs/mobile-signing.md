# AnimeX 手机端打包与签名

本文档说明如何为 AnimeX 双端 App 生成可分发的安装包。CI 已配置 tag
触发的自动构建（见 `.github/workflows/mobile-android-release.yml`、
`mobile-ios-unsigned.yml`），下面是从零开始的本地步骤。

## Android：生成 keystore + 发布 APK

1. 生成 keystore（一次性，长期保留好私钥文件）：

   ```bash
   cd mobile/android
   keytool -genkey -v -keystore animex.jks \
     -alias animex -keyalg RSA -keysize 2048 -validity 36500
   ```

   按提示填写密码 / Common Name / Organization，记下两个密码（store 和
   key 通常相同即可）。`animex.jks` 已加入 `.gitignore`，**绝对不要
   提交进仓库**。

2. 复制示例配置：

   ```bash
   cp mobile/android/key.properties.example mobile/android/key.properties
   ```

   编辑 `key.properties`，把 `storePassword`、`keyPassword` 填好，
   `storeFile` 默认指向 `../animex.jks`（即 `mobile/android/animex.jks`）。

3. 构建 release APK（三个 ABI 分发包，体积更小）：

   ```bash
   cd mobile
   flutter build apk --release --split-per-abi
   ```

   产物路径：

   ```
   mobile/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
   mobile/build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
   mobile/build/app/outputs/flutter-apk/app-x86_64-release.apk
   ```

   `arm64-v8a` 是当前几乎所有 Android 设备的主流。直接分发给用户安装即可，
   首次安装需要在系统设置里允许"未知来源"。

### CI Secrets（可选）

启用 GitHub Actions 自动构建时，把 keystore 注入到仓库 Secrets：

```bash
# 把 keystore 编码成 base64 字符串
base64 -i mobile/android/animex.jks | pbcopy
```

仓库 Settings → Secrets and variables → Actions 配置：

- `ANDROID_KEYSTORE_BASE64` — 上面拷贝的 base64
- `ANDROID_KEYSTORE_PASSWORD` — keystore 密码
- `ANDROID_KEY_ALIAS` — 默认 `animex`
- `ANDROID_KEY_PASSWORD` — key 密码

之后 `git tag v0.1.0 && git push --tags` 即可触发自动构建并把 APK 上传到
GitHub Release。Secrets 缺失时 workflow 自动回退到 debug 签名（仅做
artifact，不上传 release）。

## iOS：未签名 IPA + 三种自签路线

由于 iOS 必须有 Apple 颁发的证书才能安装到真机，仓库内部无法预签名。
CI 产物是**未签名 IPA**（`.xcarchive` 导出），需在本地或工具中再签。

### 本地导出未签名 IPA

```bash
cd mobile
flutter build ipa --no-codesign

# .xcarchive 路径：build/ios/archive/Runner.xcarchive
xcodebuild -exportArchive \
  -archivePath build/ios/archive/Runner.xcarchive \
  -exportPath build/ios/ipa-unsigned \
  -exportOptionsPlist ios/export_unsigned.plist
```

产物：`mobile/build/ios/ipa-unsigned/Runner.ipa`

### 路线 1：Sideloadly + 个人 Apple ID（推荐自用）

- 下载 [Sideloadly](https://sideloadly.io/) (macOS / Windows / Linux)
- 用 USB 连手机，把 `Runner.ipa` 拖进 Sideloadly
- 用个人 Apple ID 登录（无需付费）
- 点击 Start，工具会自动签名 + 安装到设备

**限制**：自签证书 7 天到期，过期后需要重新打开 Sideloadly 重签。
长期使用建议把 IPA + Sideloadly 一起备份。

### 路线 2：Apple Developer Program（$99/年）

- 在 [developer.apple.com](https://developer.apple.com) 加入开发者计划
- 在 Xcode 中打开 `mobile/ios/Runner.xcworkspace`
- Product → Archive 后选择 Distribute App → Ad Hoc
- 选择已加入计划的 Team，Xcode 自动生成证书 + Provisioning Profile
- 导出的 IPA 90 天有效，最多支持 100 台设备（UDID 注册）

### 路线 3：TrollStore（仅限 iOS 14.0–17.0 特定子版本）

- 设备需是越狱社区维护的 TrollStore 支持列表中的 iOS 版本（≤ 17.0
  且未打补丁）
- 用 TrollHelper 永久安装 TrollStore，之后把 `Runner.ipa` 拖入即可
- **优点**：永久签名，无 7 天 / 90 天限制
- **限制**：适用面窄，仅作为附录方案

详细 TrollStore 兼容性表见 [trollstore.app](https://ios.cfw.guide/installing-trollstore/)。

## 版本号管理

在 `mobile/pubspec.yaml` 顶部修改 `version: <name>+<code>`：

```yaml
version: 0.1.0+1
```

`<name>` 是用户看到的版本（例如 `0.1.0`），`<code>` 是 Android 内部
整数递增的版本号（每次 release 必须比上一次大）。

打完 tag 之前先把 pubspec.yaml 的 version 改好并提交，CI 用 tag 名
作为 release 标题。
