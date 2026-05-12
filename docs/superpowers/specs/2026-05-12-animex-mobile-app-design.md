# AnimeX 手机 APP 设计稿

- **日期**：2026-05-12
- **状态**：设计稿（待用户最终确认后转 implementation plan）
- **作者**：基于 AnimeX 仓库现状与用户决策协同输出
- **目标读者**：AnimeX 维护者；以及后续负责实施的 AI 编码会话

---

## 1. 背景

AnimeX 当前形态：

- 后端 Go 1.25，REST API 在 `internal/web/` 下
- Web 前端 Vue 3 + Vite + xgplayer，覆盖 8 个视图（Home / Discover / Schedule / Library / History / Detail / Search / Player）
- 管理员后台覆盖：数据概览 / 用户管理 / 邀请码 / 番剧 / 下载申请 / 储存桶配置 / 日志 / 系统监控 / 系统设置
- 用户角色：管理员 + 普通用户（可申请下载）
- 多储存桶：PikPak / 115 / Aria2 本地 / NAS
- 视频流统一入口：`GET /api/stream`，支持 HTTP Range
- 认证：基于随机 token 的 session（cookie `animex_session`），存内存 + Redis，TTL 7 天

需求是为这个系统补一个**双端手机 APP**，让普通用户能在手机上完整使用追番/搜刮/播放体验，管理员能随时随地审批和查看状态。

## 2. 目标与非目标

### 目标

1. 双端覆盖（iOS + Android），单代码库
2. 全量平移 Web 端功能（含管理员面板），手机端体验为主
3. 提供 4 项原生能力：
   - 后台离线下载番剧到手机本地
   - 推送通知（番剧更新提醒、审批提醒）
   - 原生视频播放（画中画 / 锁屏控制 / 后台音频 / 外连耳机路由）
   - 投屏（AirPlay / Chromecast / DLNA）
4. 代码可由 AI 全量产出，开发者只需负责调试与签名打包
5. 不上架 App Store，iOS 输出 IPA 通过侧载/自签分发

### 非目标

1. 不支持 iPad/Android 平板专门布局（保持单栏拉伸即可）
2. 不重写后端业务逻辑，仅做最小 API 扩展
3. 不替换 Web 前端
4. 不做 Apple TV / Android TV / 桌面端
5. 手机端不实现复杂表单（如新增/编辑储存桶），跳转 Web 完成

## 3. 关键决策（已与用户确认）

| 决策 | 选择 | 替代项 | 理由 |
|---|---|---|---|
| 跨端框架 | Flutter | RN / 双端真原生 | 单代码库，UI 一致，AI 在 Dart 上产出稳定，所需插件齐全 |
| 平台覆盖 | iOS + Android | 单端 | 用户要求双端 |
| 代码产出方式 | 由 AI 全量编写 | 用户手写 | 用户偏好 |
| 发布渠道 | 不上架商店，自分发 APK + IPA | App Store / Google Play | 绕开商店审核，免除 $99/年开发者费（可选） |
| 视频播放引擎 | `media_kit`（libmpv）| `video_player`、`better_player` | 库内含 mkv/HEVC/10bit，`video_player` 不支持；libmpv 硬解兼容性最佳 |
| 推送 | Firebase FCM（iOS 通过 APNs 中转）| 自建 WebSocket / MQTT | 免费、稳定、跨端；APP 后台被杀也能收到 |
| 投屏-AirPlay | 系统 AVRoutePickerView | — | iOS 免费送 |
| 投屏-Cast | `flutter_cast_framework` | — | Android 主场景 |
| 投屏-DLNA | 自实现 SSDP + SOAP（约 300 行 Dart）| 第三方插件 | 现有插件维护差 |
| 后台下载 | `background_downloader` 包 | 自写 isolate | iOS URLSession + Android WorkManager 都封装好 |
| 状态管理 | Riverpod | Bloc / Provider | 强类型、轻量、与异步代码生成器集成好 |
| 路由 | go_router | Navigator 2.0 自写 | 官方推荐、声明式 |
| 认证 | 复用现有 session token，APP 用 Bearer header | JWT / OAuth | 后端改动最小 |
| 管理员复杂表单 | 手机端只读，编辑跳 Web | 全量实现 | 手机 UX 差、出错率高 |
| iOS 默认产物 | unsigned IPA + 三种签名指南 | 直接签名 | 用户根据自己条件选签名路线 |

## 4. 总体架构

### 4.1 仓库布局

```
AnimeX/
├── main.go, internal/, frontend/    现有后端 + Web 前端，不动
└── mobile/                          新增 Flutter 工程
    ├── lib/
    │   ├── main.dart
    │   ├── app/            根 widget、go_router、ThemeData
    │   ├── core/           Dio 客户端、auth、错误处理、日志
    │   ├── data/           DTO（freezed）、Repository、API 接口定义
    │   ├── features/
    │   │   ├── auth/  home/  discover/  schedule/  search/
    │   │   ├── detail/  player/  library/  history/
    │   │   ├── downloads/  profile/
    │   │   └── admin/        users/ invites/ bangumis/ requests/
    │   │                     storages/ logs/ monitor/ settings/
    │   ├── native/         投屏、PiP 等 platform channel 桥接
    │   └── widgets/        通用组件
    ├── ios/                Xcode 工程（Info.plist、entitlements、APNs）
    ├── android/            Gradle 工程（Foreground Service、FCM、PiP）
    ├── docs/               IPA 签名指南、APK 打包指南
    └── pubspec.yaml
```

后端代码与 Flutter 工程**通过 HTTP/JSON 解耦**，不共享类型定义。Dart DTO 手写并保持与 Go 结构体字段一致，由 freezed + json_serializable 生成序列化代码。

### 4.2 进程与线程

- Flutter UI 在主 isolate
- 后台下载、推送处理在 platform 原生层（iOS URLSession / Android WorkManager），不开 Dart isolate
- 播放器 libmpv 自行管理解码线程
- 网络请求经 Dio 一层，统一拦截器处理 token 注入和 401 重登录

### 4.3 数据流（典型：浏览到播放）

```
用户 -> 首页(Riverpod provider 调用 Repository)
     -> Dio GET /api/library?... (带 Bearer token)
     -> 后端 Go handler -> DB -> JSON
     -> DTO 解析 -> Riverpod state -> UI 重建
     -> 用户点剧集 -> PlayerView 路由
     -> media_kit 加载 /api/stream/<id> (带 Range)
     -> 后端把云盘/本地视频以 Range 流式回传
     -> 播放 / 后台播放 / PiP / 历史进度回传 /api/history
```

## 5. 页面与导航

### 5.1 主框架（底 Tab）

普通用户：

```
[ 首页  发现  媒体库  我的 ]
```

管理员：

```
[ 首页  发现  媒体库  管理  我的 ]
```

Tab 切换不销毁页面状态（IndexedStack）。

### 5.2 页面映射

| 手机端页面 | 对应 Web 视图 | 备注 |
|---|---|---|
| 首页 | HomeView | 最近更新 / 继续观看 / 我的订阅 横滑卡片 |
| 发现 Tab | DiscoverView + ScheduleView + SearchView | 顶部 TabBar 分段：新番时间表 / Bangumi 排行 / 分类浏览 / Mikan 搜索 |
| 详情页 | DetailView | 番剧封面 + 简介 + 剧集网格 + 订阅/申请下载/立即播放 |
| 播放器 | PlayerView | 全屏，详见 §6 |
| 媒体库 Tab | LibraryView | 显示后端扫描到的全部番剧（云盘 + 本地存储 + NAS），其中已下载到本机手机的剧集额外标"已下载到手机"角标 |
| 下载（媒体库右上角入口） | —（新增）| 本地离线下载队列、进度、暂停/续传/删除 |
| 历史（"我的"内） | HistoryView | 观看历史 + 进度 |
| 我的 Tab | —（新增）| 用户信息、修改密码、设置、关于、退出 |

管理 Tab 内部（垂直列表入口页）：

- 数据概览（dashboard 图表）
- 用户管理（列表 + 详情 + 启停/改角色）
- 邀请码管理（生成 / 列表 / 删除）
- 番剧管理（列表 + 强制刷新 / 删除）
- 下载申请审批（待审 / 已审，下拉刷新 + 批量通过）
- 储存桶配置（**只读 + 切换当前 + 测试连接**，编辑跳 Web）
- 日志查看（虚拟滚动 + 关键字过滤）
- 系统监控（CPU / 内存 / 同步状态卡片 + 自动刷新）
- 系统设置（开关项为主，复杂项跳 Web）

### 5.3 UI 主题

- 双端统一深色番剧主题，不走 iOS Cupertino
- 主色取 README 截图紫/蓝调，背景 `#0F1014`，卡片 `#1A1B22`，强调色饱和橙红
- 字体：iOS PingFang SC，Android 思源/系统中文
- Material 3 组件 + 自定义 ThemeExtension
- 横屏：仅播放器允许，其他强制竖屏
- 平板：保持单栏布局拉伸

## 6. 核心能力实现

### 6.1 视频播放（`media_kit`）

- 基于 libmpv，支持 mkv / HEVC / 10bit / 字幕轨切换
- 硬解优先，软解兜底（媒体库内 README 已注明部分浏览器无法播 mkv/HEVC/10bit，APP 端必须解决）
- 自定义播放控件（音量/亮度/进度手势、双击快进、长按倍速）
- 历史进度本地持久 + 周期上报后端 `/api/history`
- 字幕：从同目录拉 `.ass / .srt`（如果后端能返回），优先内嵌

### 6.2 画中画 + 后台 + 锁屏

- iOS：Info.plist 加 `UIBackgroundModes: audio`，AVPictureInPictureController 由 media_kit iOS 端封装暴露
- Android：Activity 加 `android:supportsPictureInPicture="true"`，PiP 配置宽高比；后台音频用 Foreground Service + MediaSession
- 锁屏：iOS NowPlayingInfoCenter + Android MediaSession 显示番剧名、剧集、封面、上一集/下一集
- 耳机路由：由系统自动处理，PlayerController 监听 audio session 中断恢复

### 6.3 后台下载

- 包：`background_downloader`
- iOS：URLSessionDownloadTask 后台任务，APP 被杀后系统继续下载，完成后唤醒 APP 通知
- Android：WorkManager + Foreground Service，常驻通知栏
- 文件落点：`<APP Documents>/AnimeX/<番剧名>/<剧集>.<ext>`
- 来源 URL：`/api/stream/<id>`，APP 把 Range 请求做成分片下载
- 任务持久化：本地 sqlite（drift），断点续传由 background_downloader 自带支持
- 离线播放：媒体库展示"已下载"标记，点开优先用本地文件，缺失则回退在线流

### 6.4 推送

- 服务：Firebase Cloud Messaging（iOS 经 APNs 中转，Android 直推）
- 客户端：`firebase_messaging`，首次启动请求权限，拿到 token 上报后端
- 后端事件触发点：
  - 番剧入库新剧集（已有 hook 点）→ 给所有订阅该番剧的用户推
  - 下载申请被审批 → 给提交人推
- 离线漏推补救：APP 启动调用 `/api/notifications?since=<ts>` 拉取未读

### 6.5 投屏

- **AirPlay**：iOS 系统自带，播放器右上角放 AVRoutePickerView（media_kit 已暴露 API）
- **Chromecast**：`flutter_cast_framework`，发现设备 → 取媒体 URL → cast `/api/stream/<id>`（接收端需要能直连后端，注意 LAN/公网环境）
- **DLNA**：自实现
  1. SSDP `M-SEARCH` 发现 `urn:schemas-upnp-org:service:AVTransport:1`
  2. 解析 device description XML 拿到 control URL
  3. POST SOAP `SetAVTransportURI` 推视频，`Play` 播放
  4. 轮询 `GetPositionInfo` 显示进度
  约 300 行 Dart，封装为 `lib/native/dlna.dart`

## 7. 后端 API 改造清单

仅新增和扩展，不破坏现有接口。

| 接口 | 方法 | 用途 |
|---|---|---|
| `/api/auth/mobile-login` | POST | 入参 `{username, password}`，返回 `{token, expires_at, role, username}` |
| 现有受保护接口 | — | auth middleware 增加 `Authorization: Bearer <token>` 解析路径（与 cookie 二选一） |
| `/api/devices/register` | POST | 入参 `{fcm_token, platform: ios\|android}`，与当前用户绑定 |
| `/api/devices/unregister` | POST | 入参 `{fcm_token}`，登出或换设备时调用 |
| `/api/notifications` | GET | 查询参数 `since=<unix_ts>`，返回该时间点之后产生的通知列表 |

新增数据库表 `mobile_devices(id, user_id, fcm_token, platform, created_at, last_seen_at)`。

新增 Go 代码量预估 ~400 行：

- `internal/web/mobile.go`：mobile-login、devices、notifications
- `internal/web/auth.go`：扩展 middleware 支持 Bearer
- `internal/notify/fcm.go`：FCM 推送客户端（用 google.golang.org/api 或直 HTTP）
- 在番剧入库 / 审批通过的位置插入推送调用

## 8. 打包与签名

### 8.1 Android

- 仓库放 `mobile/android/key.properties.example`
- 开发者按文档 `keytool -genkey -v -keystore animex.jks ...` 生成 keystore
- `flutter build apk --release --split-per-abi` 输出 3 个 ABI 的 APK
- 直接分发 APK 给用户安装

### 8.2 iOS IPA

默认输出 unsigned IPA：

```
flutter build ipa --no-codesign
# 产物在 mobile/build/ios/archive/Runner.xcarchive
# 导出未签名 ipa: xcodebuild -exportArchive -archivePath ... \
#                  -exportOptionsPlist export_unsigned.plist
```

随仓库提供《三种 iOS 签名路线指南》：

1. **Sideloadly + 个人 Apple ID**（推荐自用）
   - 工具：Sideloadly（macOS / Windows / Linux）
   - 7 天有效，每周重签
   - 零成本
2. **Apple Developer Program**（$99/年）
   - Xcode 直接 Archive + Distribute Ad-Hoc
   - 90 天有效，100 台设备上限
3. **TrollStore**（仅 iOS ≤ 17.0 特定版本）
   - 永久签名，无需重签
   - 适用面窄，作为附录说明

### 8.3 CI（可选，里程碑 M8）

GitHub Actions：

- `mobile-android-release.yml`：tag 触发，构建 APK 上传 release
- `mobile-ios-unsigned.yml`：tag 触发，构建 unsigned IPA 上传 release

## 9. 测试策略

- **单元测试**：Repository 层（Mock Dio）、DTO 序列化
- **Widget 测试**：关键 UI 状态（登录、详情、播放器控件）
- **集成测试**：登录闭环、首页加载、播放启动（用 mock 后端 fixture）
- **手动验收 checklist**：每个里程碑结束做一次双端真机跑

不做端到端 e2e（成本高、维护差），靠手动验收 + 单元 + Widget 覆盖。

## 10. 里程碑

| M | 内容 | 估算编码会话 |
|---|---|---|
| M1 | Flutter 脚手架 + Dio + 主题 + 登录 + 首页空壳 | 1 |
| M2 | 发现 / 搜索 / 详情 / 订阅 浏览闭环（不含播放）| 1–2 |
| M3 | 原生播放器 + 画中画 + 后台音频 + 观看进度 | 1–2 |
| M4 | 媒体库 + 后台离线下载 + 离线播放 | 1–2 |
| M5 | AirPlay / Cast / DLNA 投屏 | 1 |
| M6 | 后端推送改造 + FCM 接入 + 通知中心 | 1 |
| M7 | 管理员 Tab（审批 / 日志 / 监控；复杂表单跳 Web）| 1–2 |
| M8 | 签名打包文档 + CI（可选）+ 收尾 | 0.5 |

合计 8–12 个编码会话。每个 M 独立可交付，做到一半中断也不影响前面 M 已经能用的部分。

## 11. 已知风险

1. **iOS Sideload 7 天过期**：用户体验差。缓解：在《签名指南》里推荐 Sideloadly 自动续签 + 给出付费/TrollStore 替代方案。
2. **PikPak / 115 直链可能带防盗链 token，APP 内播 vs Chromecast 接收端拿不到同一个会话**：Cast 场景下若直链失败，回落到强制后端代理 `/api/stream`（已有，作为兜底）。
3. **media_kit iOS 包体增加 ~20MB**：可接受；如严重，后续可考虑切 `fvp` 但功能略弱。
4. **FCM 在国内 Android 设备 Google 服务可能不可用**：缓解：保留 APP 启动时拉 `/api/notifications` 的轮询路径，FCM 不可用也能看到通知。
5. **后端原 cookie session 与 Bearer header 并行**：middleware 改造需测试现有 Web 端不退化（必须有回归测试）。

## 12. 开放问题（实施前可与用户确认；当前默认决策已写明）

- **Q1**：是否需要 APP 内"扫码登录 Web 端"功能（Web 显示二维码，APP 扫了帮 Web 登录）？默认**不做**，需要再加。
- **Q2**：是否要做"局域网内 P2P 直传"以避免下载经过云盘？默认**不做**，所有流量经后端。
- **Q3**：Firebase 项目由谁创建？默认**由用户在自己 Google 账号下创建一个免费项目**，把 google-services.json / GoogleService-Info.plist 放进仓库（仓库可公开但建议私有）。

---

*本设计稿一旦获得用户确认，将转交 writing-plans 技能生成实施计划。M1–M8 每个里程碑会生成单独的可执行 plan，按会话顺序推进。*
