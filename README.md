# 小学班级管理系统

面向小学语文教师的 Windows 桌面课堂管理工具。支持班级名单、小红花奖励、随机抽签、单词听写、Excel 报表和 U 盘备份。应用纯离线运行，不需要账号或网络，学生数据保存在本机。

## 功能

- 管理多个班级和学生名单，支持批量导入；4.0 新增可选小组名称和组员号。
- 记录小红花奖励与扣减，查看今日流水和周、月、累计榜单。
- 按班级、性别、小组、组员号组合抽取学生，一轮内不重复。
- 使用 Windows SAPI 离线合成听写语音，并提供教材词表预置音频。
- 导出 Excel 报表，并通过 U 盘备份或恢复数据。

## 技术栈

当前版本：4.0.0。旧数据库在启动时自动补充小组字段，保留已有学生、红花及抽签记录。

- Flutter Windows 桌面应用，Dart SDK >=3.4.0 <4.0.0
- SQLite（sqflite_common_ffi 与随包分发的 sqlite3.dll）
- 纯 Dart 的 Excel 导出和 zip 备份
- Windows Media Foundation（MFPlay）音频播放

应用运行数据位于 %APPDATA%\classroom_manager\data\，不会上传到云端。

## 目录结构

~~~text
lib/
├── main.dart / app.dart
├── pages/       页面，一个页面一个文件
├── data/        数据库、模型、仓储与数据工具
└── services/    音频、TTS、备份、报表
assets/
├── tts_seed/    教材离线音频
└── fonts/       应用字体
windows/         Windows runner 与 MFPlay
test/            自动化测试
tools/           资源生成与校验脚本
_archive/        已下线页面，仅留存备查
~~~

## 开发

在 Windows 上安装 Flutter SDK 和 Visual Studio 的「使用 C++ 的桌面开发」工作负载，然后在仓库目录运行：

```powershell
flutter pub get
flutter run -d windows
```

构建 Windows 发布版：

```powershell
flutter build windows --release
```

本机无 Visual Studio 时，纯 Dart 改动可以单独重建 AOT 产物，详见 [开发说明](doc/DEVELOPMENT.md)。

4.0 测试使用独立的临时数据目录：

```powershell
$env:APPDATA = Join-Path ([System.IO.Path]::GetTempPath()) ('classroom_v4_test_' + [guid]::NewGuid().ToString('N'))
flutter test test/group_fields_test.dart
```

功能规则见 [需求说明](doc/REQUIREMENTS.md)，数据模型见 [架构说明](doc/ARCHITECTURE.md)。

## 仓库

GitHub 仓库：[jying3040-cmd/offline-classroom-manager](https://github.com/jying3040-cmd/offline-classroom-manager)，默认分支为 main。本机源码工作目录为 C:\dev\classroom_manager。
