# AnimeX Mobile — M2 实施计划

**范围**：发现 / 搜索 / 详情 / 订阅浏览闭环（不含播放）

承接 M1（commit `cb54a5d`）。M2 完成后用户可以：
- 进入 App 后看到 4 个底 Tab：首页 / 发现 / 媒体库 / 我的
- 发现 Tab 内 3 段：新番时间表（Mikan）/ Bangumi 排行 / Mikan 搜索
- 任意 item 点开 → 详情页 → 看剧集网格 → 点订阅
- 媒体库 Tab 看后端扫到的全部番剧
- 我的 Tab 看用户信息 + 修改密码占位 + 退出登录 + 更换服务器

## 后端复用
全部使用现有 endpoint，不改后端：
- `GET /api/library` — 媒体库（管理员；普通用户读快照）
- `GET /api/search?q=...` — Mikan 搜索
- `GET /api/bangumi/discover?offset=&limit=` — Bangumi 排行（分页）
- `GET /api/mikan/schedule` — Mikan 新番时间表
- `POST /api/mikan/subscribe` — 订阅一项 Mikan 番剧

## 文件结构变更
```
mobile/lib/
  data/
    dtos/
      bangumi_subject.dart        # discover 用
      mikan_schedule.dart         # schedule 用
      search_result.dart          # search 用
      library_bangumi.dart        # library + episode + playable_file
    repositories/
      discover_repository.dart    # discover/schedule/search
      library_repository.dart     # library
      subscription_repository.dart # subscribe
  features/
    shell/app_shell.dart          # IndexedStack + BottomNavigationBar
    discover/
      discover_tab.dart           # DefaultTabController 框架
      schedule_view.dart
      ranking_view.dart
      search_view.dart
    detail/
      detail_page.dart            # 共用详情
    library/
      library_tab.dart
    profile/
      profile_tab.dart
    home/home_tab.dart            # M1 home_page 改名简化
```

## 任务清单（TDD，每个任务一次 commit）

| # | Task | 类型 | 验收 |
|---|---|---|---|
| 1 | 新增 DTO + 单元测试 | TDD | parse 真实样本 JSON |
| 2 | DiscoverRepository + 测试 | TDD | 3 个 endpoint mock 通过 |
| 3 | LibraryRepository + 测试 | TDD | mock /api/library |
| 4 | SubscriptionRepository + 测试 | TDD | mock POST /api/mikan/subscribe |
| 5 | AppShell（4 Tab + IndexedStack） | TDD | widget 测试 tab 切换不丢 state |
| 6 | DiscoverTab 框架 + 3 sub-tab 路由 | TDD | widget 测试 TabBar 切换 |
| 7 | ScheduleView：按 weekday 分组 grid | TDD | 渲染 fake schedule |
| 8 | RankingView：分页 grid + 滚到底加载下一页 | TDD | 渲染 + 模拟翻页 |
| 9 | SearchView：搜索框 + 结果列表 | TDD | debounce + 空 query |
| 10 | DetailPage：传 hero data + 加载剧集 | TDD | 渲染 + 空剧集态 |
| 11 | LibraryTab：网格 + 跳详情 | TDD | 渲染 + onTap |
| 12 | ProfileTab：信息 + 退出 + 更换服务器 | TDD | 退出后跳 /login，更换跳 /setup |
| 13 | HomeTab：保留欢迎，移除退出按钮 | TDD | 不再有 "退出登录" 文字 |
| 14 | router：根路径渲染 AppShell | manual | 现有 M1 router 测试不破 |
| 15 | u2_smoke：扩展脚本采集 4 个 Tab 截图 | manual | 截图存档 |

## 风险
- `/api/library` 对非管理员可能返回快照不可用 → ProfileTab/媒体库要处理 403 + 友好提示
- `/api/mikan/subscribe` 入参 schema 未验证 → 任务 4 前用 curl 探一次
- Bangumi discover 在初次启动后端缓存可能慢 → 网络层加 30s receive timeout（M1 已有）

## 退出条件
- 全部 15 个 task 完成，flutter test 全绿
- 在 docker compose 后端上跑通 4 个 Tab 切换 + 1 次 search + 1 次详情跳转，截图入档
- 提交到 `feat/mobile-m1` 分支
