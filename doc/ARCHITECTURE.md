# ARCHITECTURE.md — 系统设计说明

> 本文回答：这些需求**是怎么被实现的**。
> 业务规则见 `REQUIREMENTS.md`；构建、测试与打包见 `DEVELOPMENT.md`。

## 1. 总体架构

本项目是**单机桌面应用**，没有服务端、没有网络请求、没有账号体系。

```text
┌──────────────────────────────────────────────────────┐
│              Flutter Windows 桌面应用                  │
│                                                       │
│  ┌────────────── 表现层（pages/） ──────────────┐      │
│  │ 名单 · 小红花 · 抽签 · 听写 · 设置            │      │
│  └───────────────────┬─────────────────────────┘      │
│                      │                                │
│  ┌───────────────────▼─────────────────────────┐      │
│  │  数据访问层  data/repo.dart（唯一 SQL 出口）   │      │
│  └───────────────────┬─────────────────────────┘      │
│                      │                                │
│  ┌───────────────────▼─────────────────────────┐      │
│  │  SQLite（sqflite_common_ffi + sqlite3.dll）  │      │
│  │  %APPDATA%\classroom_manager\data\           │      │
│  └─────────────────────────────────────────────┘      │
│                                                       │
│  ┌──────────── 平台服务（services/） ───────────┐      │
│  │ 音频播放 ← MethodChannel classroom/audio      │      │
│  │            → runner 内置 MFPlay（C++）         │      │
│  │ 语音合成 ← PowerShell + .NET System.Speech    │      │
│  │ 备份/恢复 ← archive（zip，纯 Dart）            │      │
│  │ 报表导出 ← excel（纯 Dart）                    │      │
│  └─────────────────────────────────────────────┘      │
└──────────────────────────────────────────────────────┘
```

### 关键架构约束

1. **无网络**：不存在 HTTP 客户端、不存在 API 地址、不存在重试与鉴权逻辑。
2. **无原生插件**：唯一原生代码是 runner 内置的 MFPlay 播放器，通过 MethodChannel 暴露。这规避了 Windows 插件机制对「开发人员模式」的依赖。
3. **唯一 SQL 出口**：所有数据库访问集中在 `data/repo.dart`，页面不写 SQL。
4. **纯 Dart 依赖**：`archive` / `excel` / `path` / `sqflite_common_ffi` / `uuid` 全部为纯 Dart 包。

## 2. 前端架构

### 应用入口与主题

| 文件 | 职责 |
|---|---|
| `lib/main.dart` | 初始化数据库（`AppDb.init()`）后启动 `ClassManagerApp` |
| `lib/app.dart` | 定义卡通高对比主题：`ink`（深墨色文字）、`cream`（奶油底）、六个糖果色 `candyColors`（按序轮换用于卡片）、2.5px 粗描边 + 18px 圆角的贴纸卡片样式 |

主题面向投影设计：深墨色文字配亮色块，保证后排可读。

### 页面组织

| 页面 | 文件 | 职责 |
|---|---|---|
| 主框架 | `pages/home_shell.dart` | 左侧导航 + 右侧内容；五个目的地：名单 / 小红花 / 抽签 / 听写 / 设置 |
| 名单 | `pages/roster_page.dart` | 班级切换、学生卡片网格、增删改、批量导入 |
| 小红花 | `pages/flower_page.dart` | 授奖加减、原因确认、榜单、今日统计与流水 |
| 抽签 | `pages/draw_page.dart` | 人数/范围选择、滚动动画、结果展示、历史 |
| 听写 | `pages/dictation_page.dart` | 听写单元列表、输入词语、导入教材词表入口 |
| 听写播放 | `pages/dictation_player_page.dart` | 播放状态机、对答案页 |
| 词语输入 | `pages/tts_input_page.dart` | 粘贴词语 / 一键导入教材词表 |
| 设置 | `pages/settings_page.dart` | 报表导出与备份恢复 |

### 状态管理

不使用全局状态库（无 Provider / Riverpod / Bloc）。状态分三处：

1. **页面 `State`**：各页自身状态（当前班级、选中项、播放进度等）。
2. **数据库**：唯一持久化来源；页面通过 `Repo` 读写，读后持有内存副本。
3. **`settings` 表**：跨会话的轻量偏好（如上次选中的班级）。

### 数据访问层

`data/repo.dart` 是唯一的数据库出口，提供静态方法：

| 分类 | 方法 |
|---|---|
| 班级 | `listClasses`、`addClass` |
| 学生 | `listStudents`、`addStudent`、`addStudentsByName`、`updateStudent`、`deleteStudent` |
| 红花 | `flowerTotals`、`awardFlower`、`flowerLeaderboard`、`classLogsSince`、`studentLogs`、`deleteFlowerLog` |
| 抽签 | `addDrawLog`、`listDrawLogs` |
| 设置 | `getSetting`、`setSetting` |
| 听写 | `listWordLists`、`createWordList`、`deleteWordList`、`listWords`、`importWords`、`deleteWord` |

### 公共模块

| 文件 | 职责 |
|---|---|
| `data/models.dart` | 领域模型：`Klass`、`Student`、`FlowerLog`、`LeaderRow`、`FlowerEntry`、`DrawRecord`、`WordList`、`Word`、`WordImportItem` |
| `data/db.dart` | 建库、建表与迁移（`_migrate`），开启 `PRAGMA foreign_keys = ON` |
| `data/audio_import.dart` | 音频格式探测（魔数校验）与时长解析 |
| `data/textbook_words.dart` | 教材词表常量 |

### 错误处理方式

- 数据库操作返回 `Future`，页面用 `await` 并在异常时提示。
- 音频合成/导入失败时不写入半成品记录。
- 无可移动磁盘时降级为手动输入路径。

## 3. 模块划分

| 模块 | 依赖 |
|---|---|
| 名单 | `repo`、`db`、`models` |
| 小红花 | `repo`（流水与榜单）、`app`（糖果色轮换） |
| 抽签 | `repo`（学生列表与抽签日志）、`dart:math`（`Random.secure`） |
| 听写 | `repo`（词表与词语）、`tts_service`、`audio_engine`、`textbook_seed_service` |
| 设置 | `report_service`、`backup_service` |
| 数据层 | `db`、`models`、`audio_import`、`textbook_words` |
| 平台服务 | `services/` 下的五个服务 |

依赖方向单向：`pages` → `services` / `data/repo` → `data/db`。数据层不依赖页面。

## 4. 数据模型

SQLite，位于 `%APPDATA%\classroom_manager\data\classroom.db`。

### classes

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | TEXT PK | UUID |
| `name` | TEXT NOT NULL | 班级名 |
| `created_at` | INTEGER NOT NULL | 时间戳 |
| `archived` | INTEGER NOT NULL DEFAULT 0 | 归档标记（软删除） |

### students

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | TEXT PK | UUID |
| `class_id` | TEXT NOT NULL FK→classes | 所属班级 |
| `name` | TEXT NOT NULL | 姓名 |
| `seat_no` | INTEGER | 座号 |
| `gender` | TEXT | 性别 |
| `group_name` | TEXT | 可选小组名称 |
| `member_no` | INTEGER | 可选组员号，正整数 |
| `archived` | INTEGER NOT NULL DEFAULT 0 | 归档标记 |
| `created_at` / `updated_at` | INTEGER NOT NULL | 时间戳 |

索引：`idx_students_class(class_id)`

v4.0 启动时在事务中检查 `PRAGMA table_info(students)`，仅对缺失字段执行 `ALTER TABLE ADD COLUMN`，保持原建表语句，兼容旧数据库及旧备份。原学生的新字段为 NULL，重启可重复执行而不重复添加列。抽签页面在内存中组合性别、小组、组员号过滤，再应用本轮已抽学生排除。

### flower_logs（小红花流水）

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | TEXT PK | UUID |
| `student_id` | TEXT NOT NULL FK→students | 学生 |
| `delta` | INTEGER NOT NULL | 增减值（可为负） |
| `reason` | TEXT | 原因 |
| `ref_log_id` | TEXT | 指向被纠错的原始记录 |
| `created_at` | INTEGER NOT NULL | 时间戳 |

索引：`idx_flower_student(student_id)`、`idx_flower_time(created_at)`

**设计要点**：表结构天然支持「只增不改」——扣减与纠错都是插入一条 `delta` 为负或带 `ref_log_id` 的新记录，原始记录永不被修改。这样多端合并时无冲突处理需求。

### draw_logs（抽签历史）

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | TEXT PK | UUID |
| `class_id` | TEXT NOT NULL FK→classes | 班级 |
| `student_ids` | TEXT NOT NULL | 抽中学生 ID（序列化） |
| `names` | TEXT NOT NULL | **姓名冗余存储** |
| `count` | INTEGER NOT NULL | 抽取人数 |
| `created_at` | INTEGER NOT NULL | 时间戳 |

**设计要点**：`names` 冗余存储，使历史在学生改名或删除后仍可读。

### settings

| 字段 | 类型 | 说明 |
|---|---|---|
| `key` | TEXT PK | 键 |
| `value` | TEXT NOT NULL | 值 |

### word_lists（听写单元）

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | TEXT PK | UUID |
| `title` | TEXT NOT NULL | 单元标题 |
| `subject` | TEXT | 学科/来源 |
| `created_at` / `updated_at` | INTEGER NOT NULL | 时间戳 |

### words（词语与音频）

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | TEXT PK | UUID |
| `list_id` | TEXT NOT NULL FK→word_lists | 所属单元 |
| `text` | TEXT NOT NULL | 词语 |
| `meaning` | TEXT | 释义 |
| `audio_file` | TEXT NOT NULL | 应用数据目录内的音频文件名 |
| `orig_filename` | TEXT | 原始文件名（备查） |
| `duration_ms` | INTEGER | 时长（用于进度与间隔） |
| `sort` | INTEGER NOT NULL DEFAULT 0 | 排序 |
| `created_at` | INTEGER NOT NULL | 时间戳 |

索引：`idx_words_list(list_id)`

### 外键与约束

- 迁移时执行 `PRAGMA foreign_keys = ON`。
- `flower_logs.student_id`、`draw_logs.class_id`、`words.list_id` 均为外键。

## 5. API 与服务关系

**本项目没有任何网络 API。** 唯一的「接口」是 Flutter 与原生 runner 之间的 MethodChannel。

### MethodChannel：`classroom/audio`

| 通道 | 方向 | 说明 |
|---|---|---|
| `play` | Dart → 原生 | 播放指定音频文件 |
| `pause` | Dart → 原生 | 暂停 |
| `resume` | Dart → 原生 | 继续 |
| `stop` | Dart → 原生 | 停止 |
| 播放完成回调 | 原生 → Dart | 触发后推进听写状态机 |

原生实现为 runner 内置的 **MFPlay（Media Foundation）** 播放器，原生支持 `m4a` / `wav`，**无任何插件依赖**。

### 系统能力调用

| 能力 | 调用方式 |
|---|---|
| 语音合成 | Dart 调 PowerShell + .NET `System.Speech` 批量合成 wav 到临时目录 |
| 可移动磁盘检测 | PowerShell CIM 查询（失败可手输路径） |
| 窗口标题 | 在 `windows\runner\main.cpp` 中以 Unicode 转义写死 |
| 数据目录定位 | 读取 `%APPDATA%` 环境变量（不使用 `path_provider` 插件） |

## 6. 核心数据流

### 小红花记账

```text
教师点击卡片「＋」
    ↓
弹出原因确认（数量 + 快捷原因 + 自定义）
    ↓
Repo.awardFlower(studentId, delta, reason)
    ↓
INSERT INTO flower_logs
    ↓
flowerTotals / flowerLeaderboard 重新聚合
    ↓
页面刷新合计、角标与榜单
```

### 抽签

```text
选择人数与范围
    ↓
读取该范围学生 → 排除本轮已抽（一轮不重复）
    ↓
Random.secure() 先确定结果
    ↓
启动滚动动画（仅展示）
    ↓
动画停定 → 展示结果页（超大字号）
    ↓
Repo.addDrawLog（写入 student_ids + names 冗余）
```

### 听写音频入库

```text
粘贴词语 / 导入教材词表
    ↓
TtsService：PowerShell + System.Speech 合成 wav 到临时目录
    ↓
audio_import：魔数校验 + 时长解析
    ↓
复制音频进应用数据目录，统一命名
    ↓
Repo.importWords 写入 words 表（先复制后写库）
```

### 听写播放

```text
选择单元 → 进入播放页
    ↓
AudioEngine.play(当前词音频)
    ↓
原生 MFPlay 播放 → 完成回调
    ↓
按「每词遍数」决定重播或进入作答间隔
    ↓
作答间隔倒计时（可暂停续秒）
    ↓
下一题 → …… → 对答案页
```

### 备份与恢复

```text
设置页 → 检测可移动磁盘（或手输路径）
    ↓
关闭数据库（确保 WAL 落盘）
    ↓
archive 打包：classroom.db + 全部录音
    ↓
恢复：校验路径（防 zip-slip）→ 清空重建 → 解包
    ↓
重启新实例
```

## 7. 第三方服务

**本项目不接入任何第三方网络服务。** 所有外部能力均来自本机操作系统：

| 系统能力 | 用途 |
|---|---|
| Windows SAPI / .NET `System.Speech` | 标准普通话语音合成 |
| Media Foundation（MFPlay） | 音频播放 |
| PowerShell CIM | 可移动磁盘检测 |

### 依赖与许可证

| 依赖 | 用途 | 类型 |
|---|---|---|
| `sqflite_common_ffi` | SQLite 绑定 | 纯 Dart |
| `excel` | Excel 报表导出 | 纯 Dart |
| `archive` | zip 备份/恢复 | 纯 Dart |
| `uuid` | 主键生成 | 纯 Dart |
| `path` | 路径拼接 | 纯 Dart |
| `sqlite3.dll` | SQLite 运行时 | 官方预编译版 3.53.4，随包分发 |

## 8. 权限与安全设计

### 身份认证

**无。** 单机单用户，不存在登录、会话或令牌。

### 权限模型

**无分级。** 打开应用即拥有全部功能。这是刻意的取舍：目标用户是单机单人使用的教师，引入账号体系只会增加使用成本。

### 数据访问范围

- 数据仅存于本机 `%APPDATA%\classroom_manager\data\`。
- 无任何出网请求，因此不存在数据外泄面。
- 换设备需显式导出备份再导入。

### 敏感信息处理

- 学生姓名、座号、性别属于个人信息，只存本机，不加密（单机离线场景下加密收益有限，且会带来密钥丢失导致数据不可读的风险）。
- 不在日志或界面之外输出学生信息。
- 备份包包含全部学生数据，**恢复/分享备份包时应视为敏感文件**。

### 防刷与风控

不适用——无网络接口、无付费能力。

### 恢复路径安全

- 恢复前校验解包路径，防止 zip-slip 写出应用数据目录之外。
- 备份前关闭数据库，避免打包到未落盘的 WAL。
- 恢复采用「清空重建」，不做增量合并，避免半新半旧的数据状态。

## 9. 关键技术决策

### 为什么做成桌面应用而不是网页/小程序

教室电脑常无外网或网络不稳，且教师不希望学生数据离开本机。桌面应用可以做到**真正离线**、数据不出本机、绿色免安装。代价是无法多设备同步，用 U盘备份兜底。

### 为什么坚持「纯 Dart 依赖 + 无原生插件」

Windows 插件机制需要「开发人员模式」才能创建 symlink，而开发机上未开启。为绕开这个前置条件，项目去掉了 `window_manager` / `path_provider` / `sqlite3_flutter_libs` 三个插件，改为：

- 数据目录用 `%APPDATA%` 环境变量定位；
- 窗口标题在 `main.cpp` 中以 Unicode 转义写死；
- 音频播放自己写 runner 内置 MFPlay 播放器。

这带来的额外好处是交付包依赖更少、构建更可预测。

### 为什么小红花用「只增不改」的流水账

如果允许修改或删除记录，就产生了「谁改的、改成什么」的不可追溯状态，也带来多端合并的冲突问题。改为只插入反向记录后：合计永远可由流水重放得出，纠错本身也留有痕迹，且天然支持未来的多端合并。

（例外：单条流水允许删除，用于清理误操作，且带确认。）

### 为什么抽签结果要在动画前确定

如果动画过程中才生成结果，学生与教师都会怀疑「能不能被操作」。先用 `Random.secure()`（加密级随机）定结果、再放动画，是让公平性可被相信的关键。

### 为什么听写界面不显示单词

听写的前提是学生听音写词。若界面上出现单词文本，投影出来等于给出答案，功能失效。因此播放界面只显示题号。

### 为什么音频要先复制入库再写数据库

如果先写数据库记录再复制文件，一旦断电或复制失败，数据库里就会出现指向不存在文件的记录（脏数据）。反过来先复制后写库，最坏情况只是多一个未被引用的音频文件，不会破坏数据一致性。

### 为什么教材发音要随包分发

「一键导入教材词表」如果依赖联网合成，教室断网就用不了——而教室恰恰是最需要它的地方。因此把 213 个 wav 打包进安装包（约 18MB），换来彻底的离线可用。

### 为什么数据目录用 `%APPDATA%` 而不是安装目录

安装目录（或解压目录）可能被移动、覆盖或放在只读位置。`%APPDATA%` 是每用户可写且稳定的位置，也让「解压即用」与「数据持久」互不冲突。

### 为什么用精简 Windows SDK 也能构建

本机的 Windows SDK 是精简子集（缺 `mfplat.h` / `mfapi.h`）。已适配：手动声明 `MFStartup`、使用该子集的 `MFPCreateMediaPlayer` 入口和 `MFP_EVENT_TYPE_PLAYBACK_ENDED` 事件。因此音频功能不依赖完整 SDK。
