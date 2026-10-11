# AGENT.md — AI 协作入口

本项目是 **小学班级管理系统（本地单机版）**：面向小学语文教师的 Flutter Windows 桌面应用，覆盖名单、小红花、随机抽签、单词听写与报表导出。

`AGENT.md` 只回答一个问题：**AI 在这个项目里应该怎么工作。**

## 项目上下文

- **项目类型**：Flutter Windows 桌面应用，纯离线、无账号、无服务端、数据不出本机。
- **当前技术栈**：Flutter + Dart（纯 Dart 依赖）+ SQLite（`sqflite_common_ffi`）+ runner 内置 MFPlay 播放器 + PowerShell/.NET 语音合成。
- **当前开发版本**：4.0.0（学生小组、组员号及组合抽签筛选）；历史正式发布版本为 3.0.0。
- **当前主要开发方向**：验证 4.0 的旧库迁移、学生信息维护及分小组抽取。
- **源码位置**：`C:\dev\classroom_manager`（**纯 ASCII 路径**）。本工作区文件夹中的 `classroom_manager` 是指向它的 junction 链接，两边看到的是同一份文件。

## 文档阅读顺序

```text
1. README.md          这是什么项目、怎么跑起来
2. doc/REQUIREMENTS.md    功能需求、业务规则与验收标准
3. doc/ARCHITECTURE.md    架构、数据模型、音频管线与技术决策
4. doc/DEVELOPMENT.md     构建（含无 MSVC 方案）、测试、打包与回滚
5. AGENT.md           AI 的工作纪律（本文件）
```

**构建相关任务务必先读 `doc/DEVELOPMENT.md`**——本机没有 Visual Studio，常规 `flutter build windows` 会失败，必须走 AOT 单独重建路径。

## AI 开发原则

- 优先复用现有页面、组件与仓储方法，不重复实现。
- **不新增原生插件**。当前版本刻意采用「无原生插件」方案以规避 Windows 插件机制对「开发人员模式」的依赖；新增插件前必须先说明为什么非加不可。
- **不随意新增依赖**；允许的依赖限于纯 Dart 包。
- 不擅自修改数据库表结构。表结构变更必须新增迁移逻辑，不能直接改 `CREATE TABLE`。
- 不删除用途不明确的代码。`lib/data/audio_import.dart` 与 `Repo.importWords` 虽然「导入录音」入口已下线，但**仍被 TTS 输入与教材词表导入复用**，必须保留。
- 修改 `data/repo.dart`、`data/models.dart` 等公共模块时，必须检查全部调用页面。
- 修改架构或数据模型时同步更新 `doc/ARCHITECTURE.md`；修改功能规则时同步更新 `doc/REQUIREMENTS.md`；修改构建或打包流程时同步更新 `doc/DEVELOPMENT.md`。

## 硬性纪律

### 源码路径

- 源码必须在**纯 ASCII 路径**下（`C:\dev\classroom_manager`），中文路径会破坏 Flutter Windows 构建链。
- 不要在本工作区文件夹内新建源码副本——这里是交付与文档区，源码通过 junction 指向 `C:\dev\`。

### 构建

- 本机**没有 Visual Studio**。`flutter build windows --release` 会报 `Unable to find suitable Visual Studio toolchain`。
- 只要没动 `windows/` 下的 C++ 代码，用 **AOT 单独重建**路径刷新 Dart 侧产物（`app.so` + `flutter_assets/`）。动手前先执行 `git status windows/` 确认 C++ 未变。
- 若确实改过 `windows/` 下的 C++，必须装回 VS 的「使用 C++ 的桌面开发」工作负载，**不要试图绕过**。
- 调用 `tool_backend.dart` 时**必须用 Windows 风格路径**（`C:/tools/...`），Git Bash 的 `/c/...` 会让 dart.exe 读不到。

### 数据与用户资产

- 数据库与录音位于 `%APPDATA%\classroom_manager\data\`，**每台设备独立**。
- 任何备份/恢复/清空操作前，**先确认可恢复**。恢复流程必须包含防 zip-slip 路径校验。
- **不要为了「清空重来」而删除交付文件夹**。先把现有文件夹复制为 `_backup_YYYYMMDD/`，确认新包可用后再替换。zip 不能替代文件夹本身。
- 备份前必须**关闭数据库**确保落盘。

### 交付包

- 交付包必须包含 `data\flutter_assets\assets\tts_seed\` 全部离线发音资源。历史包曾因缺 tts_seed 导致「导入教材词表」需要联网——重新打包时**不要沿用旧包的文件清单**，要重新比对资源列表。
- 打包后验证：解压到临时目录 → 从该目录启动 → 确认能运行（证明包是自包含的）。
- 发布包按版本放入 `Desktop\opc\02-发布\班级管理系统\vX.Y\`，内含 zip + `使用说明.txt`。

### 权限门

以下动作需先取得用户确认：

- 删除或覆盖已有发布包、交付文件夹。
- 修改数据库表结构或执行数据迁移。
- 引入原生插件或新增依赖。
- 对 `%APPDATA%` 下的真实教师数据执行写入、清空或恢复。
- 修改 `windows/` 下的 C++ 代码。

## 当前项目状态

| 项 | 内容 |
|---|---|
| 当前版本 | 3.0.0 |
| 已完成里程碑 | M1 名单、M2 小红花、M3 抽签、M4 听写、M5 报表/备份/打包 |
| 最新发布包 | `02-发布\班级管理系统\v3.0\班级管理系统_v3.0.zip`（约 18MB） |
| 总体状态 | 稳定可用，无阻塞 |

## 已知问题

- **本机缺少 Visual Studio**：无法执行完整的 `flutter build windows`；仅 Dart 侧改动可用 AOT 重建路径。
- **「导入录音」入口已下线**：原页面移至 `C:\dev\classroom_manager\_archive\import_wizard_page.dart` 备查；底层音频探测与批量入库管线保留并被复用。
- **Windows SDK 为精简子集**：缺 `mfplat.h` / `mfapi.h`，已在 runner 中手动声明 `MFStartup`、使用 `MFPCreateMediaPlayer` 入口与 `MFP_EVENT_TYPE_PLAYBACK_ENDED` 事件适配。改音频相关 C++ 时需留意。
- **分小组抽取已实现**：4.0 名单包含可选小组名称和正整数组员号，抽签按两项与性别取交集。
- **历史包不完整**：`v1.0` 含已下线的「导入录音」功能且缺 tts_seed 资源，**不要作为打包参考**。

## 禁止事项

- 不在本工作区文件夹内建立第二份源码。
- 不把源码放到中文路径下。
- 不新增原生插件（除非先开启「开发人员模式」并说明理由）。
- 不直接修改 `CREATE TABLE` 语句来实现表结构变更。
- 不删除 `lib/data/audio_import.dart` 与 `Repo.importWords`。
- 不在未确认可恢复的情况下覆盖或删除交付包与用户数据。
- 不重写 Git 历史、不强推。

## 当前开发重点

```text
当前重点：
1. 维护 v3.0 交付包的稳定性，确保 tts_seed 资源完整
2. 按需迭代：分小组抽取（需先加分组字段）
3. 保持「纯 Dart 依赖 + 无原生插件」的架构约束
```
