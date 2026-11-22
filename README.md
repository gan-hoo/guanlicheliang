# 行车记录（DriveLog）

一个自用的 iPhone App：**连上 CarPlay 自动开始记录行程，断开自动停止并保存**，同时管理多辆车的加油、用车费用、保养提醒和统计。

- iOS 17+，SwiftUI + SwiftData + Swift Charts + MapKit，**不用任何第三方库**
- 只有一个 App target，没有 widget / extension，不需要付费开发者账号
- 用 GitHub Actions（macOS）编译出**未签名 IPA**，在 Windows 上用 **Sideloadly + 免费 Apple ID** 安装

---

## 目录

1. [功能一览](#功能一览)
2. [编译：上传代码 → 运行 Actions → 下载 IPA](#一编译上传代码--运行-actions--下载-ipa)
3. [在 Windows 上用 Sideloadly 安装](#二在-windows-上用-sideloadly-安装)
4. [iPhone 上：开发者模式、信任证书](#三iphone-上开启开发者模式信任证书)
5. [每 7 天续签一次（不要删 App！）](#四每-7-天续签一次)
6. [定位权限：「始终」+「精确位置」](#五定位权限始终--精确位置)
7. [快捷指令：两个 CarPlay 自动化](#六快捷指令两个-carplay-自动化)
8. [数据、导出与备份](#七数据导出与备份)
9. [常见问题](#八常见问题)
10. [技术方案、数据模型、文件结构](#九技术方案数据模型文件结构)

---

## 功能一览

| 模块 | 内容 |
| --- | --- |
| 自动行程记录 | 两个 App Intents：「开始记录行程」（后台运行，锁屏也行）、「停止记录并保存」；重复触发安全；记录 GPS 路线、距离、实时/最高/行驶均速、总时长和行驶时长、海拔 |
| 防丢数据 | GPS 点边记边写入磁盘（约 4 秒 flush 一次）；同时开启 significant location change，被系统杀掉后能被唤醒接着记；启动时发现没收尾的行程：最后一个点在 30 分钟内就接着记，否则直接收尾保存 |
| GPS 过滤 | 丢弃精度 > 50 m 和过期缓存点；停车漂移（速度 < 0.8 m/s 且位移 < 15 m）不计距离；隐含速度 > 250 km/h 的跳点不计；最高速度只用 speedAccuracy 可靠的点；短于 100 m 的行程自动丢弃 |
| 通知 | 开始记录、保存行程（「行程已保存：12.3 km · 18分 · 最高 98 km/h」）、到期提醒 |
| 行程 | 列表（按月分组，左滑删除，顶部累计里程）；详情页地图按速度分段上色（<30 / 30–60 / 60–90 / 90–110 / >110 km/h）、起终点、速度/海拔曲线（降采样）；可改归属车辆 |
| 车辆 | 多辆车、当前车辆、照片；估算当前里程 = 最近一次填写的里程表读数 + 之后的行程距离，可手动校正 |
| 加油 | 三选二自动算（加油量 / 单价 / 总价）、默认估算里程和上次油价、当前定位 + 附近加油站；「满箱到满箱」油耗、漏记处理、每公里油费、油价/油耗走势图 |
| 费用 | 13 个默认分类（可增删改名换图标）、收据照片、常用商家自动补全；周期性费用（保险、rego…）到期前通知、一键续费；保养提醒（按日期或里程） |
| 统计 | 按月/按年/按车辆：总花费、分类占比饼图、每公里总成本、总里程、油耗趋势；首页概览卡片 |
| 导出/备份 | 每段行程自动生成 GPX + 原始 CSV；加油/费用/行程概要导出 CSV；一键备份全部数据为一个文件，可完整恢复 |

---

## 一、编译：上传代码 → 运行 Actions → 下载 IPA

> 不需要 Mac。编译在 GitHub 提供的 macOS 机器上完成。

### 1. 把代码放到 GitHub

如果代码已经在你的仓库里（例如本仓库），跳到第 2 步。

否则：

1. 登录 GitHub，右上角「+」→「New repository」，起个名字（例如 `drivelog`），选 **Public**（公开仓库的 Actions 免费；私有仓库也可以，但 macOS 机器按 10 倍消耗免费额度，每次编译大约 2–3 分钟）。
2. 上传代码（任选一种）：
   - **网页上传**：仓库页面点「uploading an existing file」，把整个项目文件夹里的内容（包括 `.github` 文件夹、`DriveLog` 文件夹、`project.yml` 等）拖进去，点「Commit changes」。
     Windows 资源管理器默认隐藏以 `.` 开头的文件夹，请在「查看 → 显示 → 隐藏的项目」里打开显示，确认 `.github/workflows/build-ipa.yml` 也上传了。
   - **GitHub Desktop**：File → Add local repository → 选项目文件夹 → Publish repository。

### 2. 运行 Actions

1. 打开仓库页面，点上方的 **Actions**。第一次可能要点「I understand my workflows, go ahead and enable them」。
2. 左边选 **Build unsigned IPA**。
3. 右边点 **Run workflow** → 选择分支 → 绿色的 **Run workflow**。
   （每次往 `main` 或 `claude/...` 分支推送代码也会自动编译。）
4. 等 2–5 分钟，出现绿色 ✅ 就是成功。

### 3. 下载 IPA

1. 点进这次运行，页面最下面 **Artifacts** 里有 `DriveLog-ipa-数字`，点击下载。
2. 下载得到的是一个 zip，**解压后**才是 `DriveLog.ipa`。

> 编译失败时，Artifacts 里的 `xcodebuild-log-数字` 是完整编译日志，日志末尾的 `ERRORS` 部分列出了所有报错。

---

## 二、在 Windows 上用 Sideloadly 安装

### 1. 先装 iTunes 和 iCloud（必须是 Apple 官网版）

Sideloadly 需要 Apple 的驱动和服务。**不要用 Microsoft Store 里的版本**，Store 版没有 Sideloadly 需要的组件。

- iTunes：从 Apple 官网下载 Windows 64 位安装包（`https://www.apple.com/itunes/download/win64`）。
- iCloud：下载 Apple 官网的「iCloud for Windows」**非 Microsoft Store 版本**。Sideloadly 官网的下载页也给出了这两个官方安装包的链接。
- 如果之前装过 Store 版，先在「设置 → 应用」里卸载，再装官网版。

### 2. 安装 Sideloadly

从官网 `https://sideloadly.io` 下载 Windows 版并安装。

### 3. 安装 App

1. 用数据线把 iPhone 连到电脑，iPhone 上弹出「要信任此电脑吗？」→ 信任，输入锁屏密码。
2. 打开 Sideloadly：
   - **iDevice**：选你的 iPhone
   - **Apple account**：填你的 Apple ID（建议用一个专门的免费 Apple ID 也可以）
   - 把 `DriveLog.ipa` 拖到左上角的 IPA 图标上
3. 点 **Start**，按提示输入 Apple ID 密码，可能还要输入双重认证验证码。
4. 显示 `Done` 就装好了。

> **以后每次都用同一个 Apple ID，不要勾选修改 Bundle ID 之类的选项**，这样续签时才会覆盖原来的 App，数据才不会丢。

---

## 三、iPhone 上：开启开发者模式、信任证书

1. **开发者模式**（iOS 16 起需要）：
   设置 → 隐私与安全性 → 拉到最下面「开发者模式」→ 打开 → 按提示重启 → 重启后解锁时选「打开」，输入密码。
   （这个选项要在第一次用 Sideloadly 装过 App 之后才会出现。）
2. **信任证书**：
   设置 → 通用 → VPN 与设备管理 →「开发者 App」下面点你的 Apple ID → 信任。
3. 现在可以打开「行车记录」了。

---

## 四、每 7 天续签一次

免费 Apple ID 签名的 App **7 天后就打不开**（数据还在，只是无法启动）。

续签方法：**再用 Sideloadly 装一次 IPA，直接覆盖安装**（可以是同一个 IPA，也可以是新编译的版本）。

> ⚠️ **千万不要先删除 App 再装！** 删除 App 会把里面的所有数据（行程、加油、费用、照片、备份文件夹）一起删掉。
>
> 建议定期在 App 里「车辆/设置 → 备份与恢复」导出备份，并存到 iCloud 云盘或电脑上。

小提示：

- Sideloadly 有「自动刷新」功能，电脑开着、手机和电脑在同一 Wi-Fi 下时可以自动续签（需要先在 Sideloadly 里开启 Wi-Fi 同步）。
- 免费 Apple ID 同时最多 3 个侧载 App，每 7 天最多注册 10 个 App ID。
- 每次覆盖安装后，快捷指令自动化和权限设置都会保留，一般不用重新设置。

---

## 五、定位权限：「始终」+「精确位置」

快捷指令在后台（锁屏、App 没打开）启动记录，**必须**是「始终」允许定位：

1. 第一次打开 App 会请求定位，先选「使用 App 时允许」。
2. 首页的黄色提示卡片点「改为始终」，在弹窗里选「更改为始终允许」；
   或者：设置 → 行车记录 → 位置 → 选 **始终**。
3. 同一页面打开 **精确位置**（关掉的话误差可达几公里）。
4. 设置 → 行车记录 → 通知 → 允许通知（用于确认自动化是否真的运行了）。

首页会实时检测：定位服务关闭、权限不是「始终」、精确位置关闭、通知关闭时都会显示醒目提示，并有一键跳转设置的按钮。「车辆/设置 → 定位与通知权限」可以查看完整状态。

---

## 六、快捷指令：两个 CarPlay 自动化

> 先手动打开一次 App，「快捷指令」里才能找到它的动作。

### 自动化一：连接 CarPlay → 开始记录

1. 打开「**快捷指令**」App → 底部「**自动化**」。
2. 点右上角「**+**」（第一次是「新建自动化」）。
3. 在列表里找到并选择「**CarPlay**」。
4. 勾选「**连接**」，选择「**立即运行**」（可以关闭「运行时通知」），点「**下一步**」。
5. 点「**新建空白自动化**」→「**添加操作**」→ 搜索「**行车记录**」→ 选择「**开始记录行程**」。
6. 点右上角「**完成**」。

### 自动化二：断开 CarPlay → 停止并保存

1. 「自动化」→「**+**」→「**CarPlay**」。
2. 勾选「**断开连接**」，选「**立即运行**」，点「**下一步**」。
3. 「新建空白自动化」→「添加操作」→ 搜索「行车记录」→ 选择「**停止记录并保存**」。
4. 点「**完成**」。

### 确认生效

- 连上 CarPlay → 收到通知「开始记录行程」。
- 断开 → 收到通知「行程已保存：12.3 km · 18分 · 最高 98 km/h」。
- 短于 100 m（比如停着插了一下线）→ 通知「行程过短，未保存」。
- 重复触发是安全的：已经在记录时再触发「开始」会被忽略；没在记录时触发「停止」也会被忽略。
- 也可以在「快捷指令」App 的「App 快捷指令」里直接运行这两个动作测试，或在 App 首页手动开始/停止。

---

## 七、数据、导出与备份

### 文件位置

「文件」App → 我的 iPhone → **行车记录**：

| 文件夹 | 内容 |
| --- | --- |
| `行程轨迹/` | 每段行程自动生成的 `.gpx` 和原始 `.csv`（时间、经纬度、海拔、精度、速度、航向） |
| `数据导出/` | 在「车辆/设置 → 导出 CSV」里导出的加油、费用、行程概要（UTF-8 带 BOM，Excel 直接打开不乱码） |
| `备份/` | 「备份与恢复」生成的 `.drivelog` 备份文件 |

数据库和内部轨迹文件在 App 的私有目录里，「文件」App 看不到。

### 备份与恢复

- 「车辆/设置 → 备份与恢复 → 立即备份全部数据」：把车辆、加油、费用、行程、GPS 轨迹、照片打包成**一个文件**，备份完会直接弹出「存储到文件」，建议存到 **iCloud 云盘**。
- 恢复：「从『文件』选择备份恢复…」→ 选择 `.drivelog` 文件 → 确认。恢复会**完整替换**当前数据。
- `备份/` 文件夹在 App 里面，**删 App 会一起删掉**，所以一定要另存一份到别处。

---

## 八、常见问题

**连上 CarPlay 没有自动开始记录？**
1. 首页有没有黄色/红色权限提示？定位必须是「始终」+「精确位置」。
2. 快捷指令的自动化是不是选了「立即运行」？
3. App 是否已经过期（超过 7 天没续签）？过期的 App 无法被快捷指令启动。
4. 在快捷指令 App 里手动运行「开始记录行程」，看能否收到「开始记录行程」通知。

**中途 App 被系统杀掉怎么办？**
记录时开启了 significant location change：App 被杀后，手机移动一段距离（通常几百米到一公里）系统会把它唤醒，自动接着记（会收到「已恢复行程记录」通知）。被杀期间的路线会以直线连接，距离按直线计算。如果超过 30 分钟都没有新的点，下次启动时会直接收尾保存。

**估算里程不准？**
到车辆页面点「校正里程表读数」，填仪表盘上的实际读数即可。加油记录和费用记录里填的里程表读数也会作为新的基准。

**油耗为什么是「—」？**
「满箱到满箱」至少需要两次标记为「加满」的加油记录。中间如果有一次标记了「上次加油漏记了」，这一段不计算。

**Actions 编译失败？**
打开失败的那次运行 → Build 步骤日志末尾的 `ERRORS` 部分就是报错；也可以下载 `xcodebuild-log` artifact 看完整日志。

---

## 九、技术方案、数据模型、文件结构

### 整体方案

```
快捷指令（CarPlay 连接/断开）
        │  App Intents（openAppWhenRun = false，后台拉起 App 进程）
        ▼
TripRecorder（@MainActor 单例，不依赖任何视图）
  ├─ CLLocationManager：automotiveNavigation / BestForNavigation / distanceFilter 5 m
  │   pausesLocationUpdatesAutomatically = false，allowsBackgroundLocationUpdates = true
  │   + startMonitoringSignificantLocationChanges（被杀后唤醒）
  ├─ 过滤 → TripAccumulator（距离/行驶时长/最高速度/海拔，实时与恢复共用一套逻辑）
  ├─ TrackWriter：逐行追加 CSV 到 Application Support/Tracks/<id>.csv，约 4 秒 fsync
  ├─ active_trip.json：进行中行程的状态（用于被杀后恢复）
  └─ 停止 → 生成 Trip（SwiftData）+ GPX/CSV（Documents/行程轨迹）+ 本地通知
App 启动（AppDelegate.didFinishLaunching）→ TripRecorder.bootstrap()
  └─ 有未收尾行程：最后一个点 ≤ 30 分钟 → 接着记；否则 → 收尾保存
```

### 数据模型（SwiftData，`DriveLog/Models`）

用 UUID 做外键（而不是 SwiftData 关系），备份/恢复和筛选都更简单可靠。

| 模型 | 主要字段 |
| --- | --- |
| `Vehicle` | id, nickname, brand, modelName, year, plate, fuelTypeRaw（91/95/98/E10/柴油）, tankCapacity, purchaseDate, purchasePrice, initialOdometer + initialOdometerDate, odometerCalibration + odometerCalibrationDate, notes, photoData（外部存储）, createdAt |
| `Trip` | id, vehicleID, startDate, endDate, distance(m), duration(s), movingDuration(s), maxSpeed(m/s), averageMovingSpeed(m/s), minAltitude, maxAltitude, elevationGain, 起终点坐标与地名, pointCount, notes |
| `FuelEntry` | id, vehicleID, date, odometer, liters, pricePerLiter, totalCost, fuelTypeRaw, stationName, latitude, longitude, isFullTank, missedPrevious, notes |
| `Expense` | id, vehicleID, categoryID, date, amount, odometer?, merchant, notes, receiptData（外部存储）, recurrenceMonths, dueDate, remindDaysBefore, reminderEnabled, renewed |
| `ExpenseCategory` | id, name, iconName（SF Symbol）, sortOrder |
| `MaintenanceReminder` | id, vehicleID, title, intervalKm?, intervalMonths?, lastDoneDate, lastDoneOdometer?, isEnabled, notes, notifiedDueOdometer |

GPS 轨迹点不进数据库，单独存为文件，每行：
`epoch秒,纬度,经度,海拔,水平精度,垂直精度,速度m/s,速度精度,航向`

设置（当前车辆、货币）存在 UserDefaults。

### 文件结构

```
.
├── project.yml                     # XcodeGen 工程定义（Info.plist 也由它生成）
├── .github/workflows/build-ipa.yml # Actions：xcodegen → xcodebuild → 打包 IPA → 上传
├── Config/                         # 生成的 Info.plist 放这里（已 gitignore）
└── DriveLog/
    ├── App/            DriveLogApp（入口）、AppDelegate（启动恢复）、RootView（5 个 Tab）
    ├── Models/         Vehicle、Trip、FuelEntry、Expense、ExpenseCategory、MaintenanceReminder、FuelType
    ├── Persistence/    DataStore（ModelContainer）、AppPaths、AppSettings、SeedData
    ├── Recording/      TripRecorder、TripAccumulator、TrackPoint、TrackStore/TrackWriter、
    │                   TripExporter（GPX/CSV）、TrackAnalysis（速度分段、图表采样）
    ├── Intents/        TripIntents（开始/停止）、DriveLogShortcuts（AppShortcutsProvider）
    ├── Services/       NotificationManager、ReminderEngine、OdometerService、FuelEconomy、
    │                   BackupService、CSVExporter、TripService、VehicleService、OneShotLocation、ImageUtil
    ├── Utilities/      Formatters（中文格式化）、Downsampler（LTTB 降采样）
    ├── Views/
    │   ├── Home/       首页、记录面板、权限提示
    │   ├── Trips/      行程列表、详情、地图、曲线
    │   ├── Fuel/       加油列表 + 图表、加油表单
    │   ├── Expenses/   费用列表 + 图表、费用表单、分类管理、保养提醒
    │   ├── Stats/      统计
    │   ├── Garage/     车辆与设置、车辆详情/编辑
    │   ├── Settings/   快捷指令说明、权限、备份与恢复、导出
    │   └── Components/ 通用组件、照片选择
    └── Resources/Assets.xcassets       # App 图标（1024×1024 单一尺寸）
```

### 编译设置

- `SWIFT_VERSION = 5.0`，`SWIFT_STRICT_CONCURRENCY = minimal`（避免 Swift 6 严格并发报错）
- 部署目标 iOS 17.0，仅 iPhone，竖屏
- Info.plist：`UIBackgroundModes = location`、中文的定位/相册/相机权限说明、`UIFileSharingEnabled`、`LSSupportsOpeningDocumentsInPlace`
- 本地编译（有 Mac 时）：`brew install xcodegen && xcodegen generate && open DriveLog.xcodeproj`
