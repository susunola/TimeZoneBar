# TravelTime 测试计划

> 版本：2026-08-18 · 对应 HEAD `4e74a4b`
> 状态：**25 个单元测试全绿**，CI 已跑 build + test + bundle 组装。本计划补齐分层缺口。

## 1. 测试分层

| 层级 | 范围 | 现状 | 目标 |
|---|---|---|---|
| **L1 单元** | 纯逻辑函数（时间格式化/版本比较/SHA 解析/颜色解析/JSON 迁移/高度计算） | ✅ 25 个 | 30+ |
| **L2 集成** | 进程边界（osascript 提权/超时终止）、网络边界（定位 provider 错误分支）、UserDefaults 持久化 | ⚠️ 部分（GeoResult 解码有，进程/网络无） | 补 8 个 |
| **L3 UI 冒烟** | 真实 app 启动、主题切换、增删改时区、窗口自适应 | ❌ 无（依赖 macOS 26 scene fence，需人工） | 半自动脚本 + 发版人工清单 |
| **L4 发版回归** | 手动 checklist | ✅ 有流程（build.sh release） | 固化为文档清单 |

## 2. 当前覆盖矩阵（25 个测试）

| 模块 | 覆盖点 | 用例数 | 状态 |
|---|---|---|---|
| `TimeZoneStore` | `offsetString`（整点/半点/非法） | 3 | ✅ |
| `ZoneEntry` | 旧数据无 uuid 迁移、round-trip 持久化 | 2 | ✅ |
| `Updater` | `parseVersion`/`isVersionGreater`/`sha256FromBody` | 3 | ✅ |
| `Updater` | `appBundle(in:)` 旧名/现名/无 bundle 防御 | 3 | ✅ |
| `TimeZoneStore` | `dayDifference`（同区为 0） | 1 | ✅ |
| `TimeZoneStore` | `currentZoneUUID` 启动恢复、删当前行按 id 回填 | 2 | ✅ |
| `TimeZoneStore` | 调色板轮转不重复 | 1 | ✅ |
| `AppDelegate` | `panelContentHeight` 随行数缩放/editorial chrome/下限/屏幕 cap | 4 | ✅ |
| `TimeZoneStore` | `dayLabel` 三态 + 越界 | 1 | ✅ |
| `GeoResult` | ipwho.is 嵌套 / ipapi.co 扁平 / 限流 / 错误对象 | 4 | ✅ |
| `Color(hex:)` | 6 位/3 位/8 位 alpha/非法回退 | 1 | ✅ |

## 3. 缺口与新增测试清单

### P1 — 优先补（核心逻辑最薄弱处）

| # | 测试 | 前置改造 | 说明 |
|---|---|---|---|
| 1 | `SystemZoneSwitcher.switchTimeZone` 白名单：合法 id 通过、非法 id 抛 `adminRejected` | 无（已含校验） | 注入面安全回归 |
| 2 | `PrivilegedRunner` 超时：挂起脚本在 timeout 后被 terminate | 无（已有 `timeout:` 参数） | 用 `/usr/bin/sleep 30` 当脚本，timeout=1s，断言抛错且进程消失 |
| 3 | `PrivilegedRunner` 用户取消：exit 128 → `.userCanceled` 静默 | 无 | 用 `/usr/bin/false` 替代脚本验证 128 映射（或注入 exit code） |
| 4 | `switchTo` 状态机：`isSwitching` 期间二次调用被拒、失败后复位 | **抽 `protocol ZoneSwitching` 注入 store** | 目前 `SystemZoneSwitcher` 是硬编码 enum，无法 mock |
| 5 | `confirmDetectedZone`：非法 tz 拒绝且不触发提权 | 同 4 | 依赖注入后可直接测 |
| 6 | `isDaytime` 太阳算法：固定 UTC 时刻断言已知城市昼/夜 | `store.now` 直接赋值（已可） | 例：UTC 04:00 → 东京白天 / 纽约深夜 |

### P2 — 价值较高

| # | 测试 | 前置改造 | 说明 |
|---|---|---|---|
| 7 | `cachedFormatter` 命中/新建、12/24 小时切换后 key 变化 | 无 | 防缓存 key 碰撞 |
| 8 | `QuoteView` 按显示时区取小时 | 抽 `static func hourOfDay(in zone, at date)` | 防「名言跟系统时区」回归 |
| 9 | `dayDifference` 跨日（-1/+1） | `store.now` 赋值 + 固定 zone | 需选一个与 `TimeZone.current` 差一天的时刻，断言确定性（用固定 date 即可，`TimeZone.current` 只影响参照日） |
| 10 | `switchTo` 成功后持久化 `currentZoneUUID.v1` | 同 4 | 防「高亮不持久化」回归 |
| 11 | `LocationDetector.detect` 全失败抛错、provider 顺序 | **抽 `URLSession` 注入（或 `URLProtocol` mock）** | 网络层当前无法单测 |
| 12 | `Color(hex:)` 3 位展开等价 6 位（`#0f0` == `#00ff00`） | 无 | 已隐式覆盖，显式化 |

### P3 — 可选

| # | 测试 | 说明 |
|---|---|---|
| 13 | `ZoneEntry` 非法输入防御（空 label / 坏 color 解码不崩） | 边界健壮性 |
| 14 | `menuBarText` 12/24 小时 + 日期开关组合 | 4 种组合断言 |

## 4. 可测性改造（配合新增测试，改动小、无行为变化）

1. **`protocol ZoneSwitching`**：`SystemZoneSwitcher` 改为遵循协议，`TimeZoneStore(defaults:switcher:)` 注入 —— 解锁 #4/#5/#10
2. **`URLSession` 注入** 到 `LocationDetector.detect(session:)` —— 解锁 #11（用 `URLProtocol` 桩返回 429/超时/畸形 JSON）
3. **抽纯函数**：`QuoteView` 的小时计算、`readAutoTimezoneFlagAsync` 的 plutil 输出解析（`parseAutoTimezoneFlag(output:) -> Bool`）—— 前者解锁 #8，后者补 P2

## 5. CI 增强（当前：macos-15 + build + test + icon + bundle + artifact）

| 改进 | 价值 |
|---|---|
| 矩阵：`macos-14` + `macos-15` | 项目 `platforms: [.macOS(.v14)]`，两个最低/最高支持版本都要过 |
| `pull_request` 已开 ✓；补 `workflow_dispatch` 已开 ✓ | — |
| 覆盖率：`swift test --enable-code-coverage` + `xcrun llvm-cov report` 打印 | 让缺口可见，卡 PR 阈值（如 ≥60%） |
| release 标签推送时跑 `build.sh release` 并校验 SHA256 与 release notes 一致性 | 防「自动更新死锁」类回归（Updater 拒绝无 checksum 的版本） |
| 增加 `swiftlint`/格式检查（可选） | 风格一致性，非必须 |

## 6. 发版回归清单（L4，手动冒烟，每次发版前过一遍）

| # | 场景 | 通过标准 |
|---|---|---|
| 1 | 冷启动 → Dock 点图标 | 面板出现，6 默认时区，默认北京高亮 |
| 2 | 4 主题逐个切换 | 面板即时变化，窗口高度随主题/行数自适应，不超屏幕 |
| 3 | 添加 Frankfurt + Berlin 并存 | 两行都在，删除 Frankfurt 不影响 Berlin，无空白行 |
| 4 | 替换当前行 / Restore Defaults | 高亮不消失，删除按钮状态正确 |
| 5 | 重启 app | 时区列表、主题、高亮行、头像全部保留 |
| 6 | 点头像换图 | 选图后立即生效，重启保留 |
| 7 | Detect location | ≤3s 返回（ipwho.is 首选），显示城市 + Switch 按钮 |
| 8 | 点时区行 → 授权弹窗 → **取消** | 无红字、无变化（静默） |
| 9 | 点时区行 → 授权成功 | 系统时区切换，该行高亮，`currentZone.v1` 更新 |
| 10 | 自动更新 | 有 SHA256 的 release 可更新；无 SHA256 明确报错而非静默失败 |
| 11 | 卸载 | 数据全清、登录项移除、app 删除并退出 |
| 12 | 菜单栏/状态项（best-effort） | 若显示则点击可开关面板（macOS 26 自签可能不显示，不算失败） |

## 7. 执行顺序建议

1. **本轮立即可做（无前置改造）**：#1 #2 #3 #6 #7 #9 #12 → 25 → ~32 个
2. **下一轮（先做 `protocol ZoneSwitching` 注入）**：#4 #5 #10 → ~35 个
3. **再下一轮（URLSession 注入 + 纯函数抽取）**：#8 #11 → ~37 个
4. CI 矩阵 + 覆盖率卡口随 #2 一起上

## 8. 运行方式

```bash
swift build --disable-sandbox && swift test --disable-sandbox   # 本地
./build.sh                                                       # 构建 + 部署 /Applications
./build.sh release                                               # 打包 zip + 打印 SHA256
```
（`--disable-sandbox`：SwiftPM manifest 沙箱在 macOS 26 上会 `sandbox_apply: Operation not permitted`。）
