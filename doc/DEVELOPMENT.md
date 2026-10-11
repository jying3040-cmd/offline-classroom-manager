# DEVELOPMENT.md — 开发、测试、构建与打包

> 本文回答：这个项目**应该怎么继续开发**。
> 系统设计见 `ARCHITECTURE.md`，功能规则见 `REQUIREMENTS.md`。

## 1. 开发环境

| 项 | 值 |
|---|---|
| Flutter SDK | `C:\tools\flutter` |
| Dart SDK | 随 Flutter 提供；项目约束 `>=3.4.0 <4.0.0` |
| Visual Studio | **本机已卸载**；仅改动 `windows/` 下 C++ 代码时才需要重新安装 |
| 源码路径 | `C:\dev\classroom_manager`（**必须纯 ASCII**） |
| 数据库 | SQLite（`sqlite3.dll` 3.53.4，官方预编译版） |
| 运行时数据 | `%APPDATA%\classroom_manager\data\` |

> **路径是硬约束**：Flutter Windows 构建链对中文路径兼容性差，源码必须放在纯 ASCII 路径下。本工作区文件夹中的 `classroom_manager` 只是指向源码的 junction 链接。

### 源码仓库与 Git 连接

- GitHub 仓库：[jying3040-cmd/offline-classroom-manager](https://github.com/jying3040-cmd/offline-classroom-manager)
- 远端名称：origin，地址为 https://github.com/jying3040-cmd/offline-classroom-manager.git
- 远端默认分支：main
- 本机源码目录：C:\dev\classroom_manager

检查远端配置、获取远端分支并查看本地状态：

```cmd
cd /d C:\dev\classroom_manager
git remote -v
git fetch origin
git status --short --branch
```

本机 origin 指向上述仓库，本地 main 接续远端初始提交。4.0 源码、测试与开发文档统一纳入本仓库；构建产物和临时测试数据库不纳入 Git。同步前先 fetch 并检查本地与远端状态。

## 2. 安装与启动

### 开发运行

```cmd
cd /d C:\dev\classroom_manager
C:\tools\flutter\bin\flutter.bat run -d windows
```

### 运行已构建版本

```cmd
build\windows\x64\runner\Release\classroom_manager.exe
```

> `sqlite3.dll` 必须与 exe 同目录；已部署一次即长期存在。

## 3. 环境变量

**本项目不使用环境变量。** 数据目录通过读取 `%APPDATA%` 定位；窗口标题在 `windows\runner\main.cpp` 中以 Unicode 转义写死。

| 项 | 说明 |
|---|---|
| `%APPDATA%\classroom_manager\data\` | 运行时数据目录（数据库 + 音频），**每台设备独立** |
| 密钥 | 无（单机离线，不使用任何密钥） |

## 4. 目录规范

| 位置 | 放什么 |
|---|---|
| `lib/main.dart` | 入口，保持薄（初始化数据库 + 启动 App） |
| `lib/app.dart` | 主题与设计 token（颜色、卡片样式） |
| `lib/pages/` | 一个页面一个文件，文件名小写下划线 |
| `lib/data/` | 数据库、模型、仓储与数据工具 |
| `lib/services/` | 平台能力封装（音频、TTS、备份、报表、教材词表） |
| `windows/` | C++ runner 与 CMake 配置 |
| `assets/tts_seed/g01..g18/` | 教材词表离线发音（目录声明不递归，每组需单独在 `pubspec.yaml` 列出） |
| `assets/fonts/` | 字体 |
| `_archive/` | 已下线页面备查（如 `import_wizard_page.dart`） |
| `tools/` | 辅助脚本 |

### 新增文件判断

- 新页面 → `lib/pages/`，并在 `pages/home_shell.dart` 的导航中加入。
- 新数据操作 → 加到 `lib/data/repo.dart`，**不要在其他地方写 SQL**。
- 新平台能力 → `lib/services/`，并考虑是否必须新增依赖（默认不加）。
- 新离线发音资源 → `assets/tts_seed/gNN/`，**并同步在 `pubspec.yaml` 中声明该目录**。

## 5. 编码规范

### 命名

- 文件名：小写下划线（`roster_page.dart`、`audio_engine.dart`）。
- 类名：PascalCase；页面类以 `Page` 结尾。
- 数据库字段：小写下划线（`class_id`、`created_at`）。
- 仓储方法：小驼峰动词开头（`listClasses`、`awardFlower`）。

### 错误处理

- 异步操作使用 `await` + `try/catch`，失败时给出可理解的提示，不静默吞错。
- 数据写入遵循「先复制后写库」顺序，避免脏数据。
- 非关键失败（如检测不到可移动磁盘）应降级而非中断。

### 日志

- 使用 `debugPrint`，避免在正式构建中输出学生个人信息。
- 交付构建不应残留调试输出。

### 注释原则

- 注释解释「为什么」，尤其是看起来可以简化但不能改的地方（如「先复制后写库」「结果先定后动画」）。
- 不写复述代码的注释。

### 主题与样式

- 颜色统一取自 `lib/app.dart` 中的常量（`ink` / `cream` / `candyColors` 等），不在页面里硬编码色值。
- 卡片样式沿用 2.5px 粗描边 + 18px 圆角的贴纸风格。
- 面向投影：字号偏大、对比度偏高。

### 模块依赖原则

- `pages/` → `services/` / `data/repo.dart` → `data/db.dart`。
- `data/` 不依赖 `pages/`。
- `services/` 不直接操作数据库（通过 `repo`）。

## 6. Git 分支规范

| 分支 | 职责 |
|---|---|
| `main` | 可发布状态 |
| `develop` | 集成分支（多线并行时使用） |
| `feature/*` | 单个功能开发 |
| `fix/*` | 缺陷修复 |

## 7. Feature 开发流程

```text
main / develop
    ↓
创建 feature 分支
    ↓
开发（lib/ 下的 Dart 代码）
    ↓
flutter analyze 静态检查
    ↓
构建并真机/本机运行验证
    ↓
定期同步 main / develop
    ↓
更新受影响的文档
    ↓
合并回 main / develop
```

> 只改 Dart 代码时**不需要** Visual Studio；改到 `windows/` 下的 C++ 才需要。

## 8. Commit 规范

```text
feat:      新功能
fix:       缺陷修复
refactor:  重构
docs:      文档变更
chore:     杂项
```

示例：

```text
feat(draw): 抽签增加一轮不重复开关
fix(tts): 修复断电时产生脏音频记录
docs(build): 补充无 MSVC 重建步骤
```

## 9. 测试规范

### 静态检查

```cmd
cd /d C:\dev\classroom_manager
C:\tools\flutter\bin\flutter.bat analyze
```

要求 0 问题。

### 手工测试

4.0 新增 `test/group_fields_test.dart`，覆盖旧库迁移、字段保存/清空和组合筛选。运行时必须将 APPDATA 指向新建的临时目录（目录名以 `classroom_v4_test_` 开头），避免接触真实教师数据。其余功能按下列步骤手工验证：

1. **名单**：新建班级、切换、添加/编辑/删除、批量导入去重。
2. **小红花**：加减确认流程、取消不写入、单条流水删除后合计刷新、榜单口径（本周从周一起）。
3. **抽签**：结果与动画一致、一轮不重复、1~5 人、范围筛选、历史在学生改名后仍可读。
4. **听写**：**断网**状态下导入教材词表、播放流程（遍数→间隔→下一题→对答案）、暂停续秒、播放界面不出现单词。
5. **报表**：今日/本周/本月导出，两个工作表内容正确，能打开所在文件夹。
6. **备份恢复**：备份包含数据库与全部录音；恢复到另一台电脑后听写可用；非法路径被拒绝。
7. **投影可读性**：结果页大字号在投影/白板上清晰。

### 核心链路检查

```text
新建班级 → 导入学生 → 抽签 → 加红花 → 导出报表 → 备份 → 恢复
```

## 10. 构建

### 标准构建（需要 Visual Studio）

```cmd
cd /d C:\dev\classroom_manager
C:\tools\flutter\bin\flutter.bat build windows --release
```

### 无 Visual Studio 时重建 Dart 侧产物

本机 Visual Studio 已卸载，上面的命令会报：

```text
Unable to find suitable Visual Studio toolchain. Please run `flutter doctor` for more details.
```

先确认真实状态（卸载后可能残留空目录）：

```bash
ls "/c/Program Files (x86)/Microsoft Visual Studio/2022"   # 为空 => 确实已卸载
```

**关键认识**：Flutter Windows 构建是两层独立产物。

| 层 | 由谁产出 | 是否需要 MSVC |
|---|---|---|
| C++ runner 外壳（`classroom_manager.exe`、`flutter_windows.dll`） | CMake + MSVC | **需要** |
| Dart AOT 快照（`data/app.so`）+ `data/flutter_assets/` | `flutter assemble`（gen_snapshot） | **不需要** |

所以**只要没改 `windows/` 下的 C++ 代码**，就能完整刷新发布包。动手前先确认：

```bash
git status windows/     # 应无改动
```

#### 方式一：使用现成 Skill（推荐）

本机已安装 `flutter-windows-build-without-msvc` Skill，内含 `scripts/rebuild_windows_release.py`：

```bash
python scripts/rebuild_windows_release.py \
    --project C:/dev/classroom_manager \
    --flutter-root C:/tools/flutter \
    --sync "C:/Users/7/Desktop/opc/01-项目/小学班级管理系统/交付/班级管理系统/data"
```

它会执行 `flutter assemble`，并把结果同步到 CMake Release 输出目录与所有 `--sync` 目标。

#### 方式二：手工执行

```cmd
:: 1) 只跑 assemble，产物落在 build\flutter_assets\ 与 build\windows\app.so
set FLUTTER_ROOT=C:\tools\flutter
set PROJECT_DIR=C:\dev\classroom_manager
set FLUTTER_EPHEMERAL_DIR=C:\dev\classroom_manager\windows\flutter\ephemeral
set FLUTTER_TARGET=lib\main.dart
set DART_OBFUSCATION=false
set TRACK_WIDGET_CREATION=true
set TREE_SHAKE_ICONS=true
set PACKAGE_CONFIG=C:\dev\classroom_manager\.dart_tool\package_config.json
C:\tools\flutter\bin\cache\dart-sdk\bin\dart.exe C:\tools\flutter\packages\flutter_tools\bin\tool_backend.dart windows-x64 Release

:: 2) 手工执行 CMake 的 install 规则
copy /y build\windows\app.so build\windows\x64\runner\Release\data\app.so
rmdir /s /q build\windows\x64\runner\Release\data\flutter_assets
xcopy /e /i /y build\flutter_assets build\windows\x64\runner\Release\data\flutter_assets
```

> **陷阱**：`tool_backend.dart` 必须用 Windows 风格路径调用（`C:/...`），Git Bash 的 `/c/...` 路径 dart.exe 读不到。

> **前提**：若改过 `windows/` 下的 C++ 代码，则**必须**装回 VS 的「使用 C++ 的桌面开发」工作负载重新链接，不能走此路径。

### 版本号

版本号在 `pubspec.yaml` 的 `version:` 字段（当前 `3.0.0`）。`FLUTTER_BUILD_NAME` 只有在 Dart 代码实际引用时才会进入 AOT 快照：

```dart
const String _appVersion =
    String.fromEnvironment('FLUTTER_BUILD_NAME', defaultValue: '1.0.0');
```

没有这样的引用时，tree-shaker 会删掉它，重建出的 `app.so` 会与旧版字节相同——版本号在应用内不可验证。

### 验证改动真的生效

Dart 的字符串字面量以 **UTF-16LE** 存储，用 UTF-8 搜索会全部返回 0（假通过）：

```python
d = open('build/windows/app.so', 'rb').read()
for s in ['导入录音', '输入词语', '3.0.0']:
    print(s, d.count(s.encode('utf-16-le')))
```

文件体积变化也是有效信号（删页面会变小，加图标会改变 tree-shaken 的字体子集大小）。

## 11. 打包与发布

### 运行依赖

`classroom_manager.exe` + `flutter_windows.dll` + `sqlite3.dll` + `data\` 目录。整个 Release 文件夹拷到目标机器即可运行。

### 发布包目录约定

每个版本在 `Desktop\opc\02-发布\班级管理系统\` 下建 `vX.Y\`，内含两件东西（发给老师时整包拷走）：

```text
02-发布\班级管理系统\v3.0\
├── 班级管理系统_v3.0.zip      ← 解压即用
└── 使用说明.txt               ← 一页纸指南
```

### 打包步骤

1. 按第 10 节构建（或重建 Dart 侧产物），并同步到 `交付\班级管理系统\data\`。
2. **确认 `data\flutter_assets\assets\tts_seed\` 完整**（213 个 wav，18 个分组）。
3. 打包为 zip。
4. 校验压缩包：

```python
import zipfile
z = zipfile.ZipFile(path)
print(len(z.namelist()), z.testzip() is None)
```

5. **端到端验证**：把 zip 解压到临时目录，**从该目录启动**，确认能运行（证明包自包含）。
6. 放入 `02-发布\班级管理系统\vX.Y\`。

> **常见陷阱**：重新打包时沿用旧包的文件清单，会漏掉后来新增的资源（例如 `assets/tts_seed/`），导致应用静默降级到运行时兜底。**必须比对新旧包的资源列表**，不要假设旧包是完整的。

## 12. 回滚

| 场景 | 做法 |
|---|---|
| 新构建有问题 | 用 `02-发布\` 中上一版本的 zip 重新分发 |
| 交付文件夹被改坏 | 从 `_backup_YYYYMMDD/` 恢复（**打包前必须先建这个备份**） |
| Dart 侧重建出错 | 重新执行第 10 节流程；`app.so` 可反复重建 |
| C++ 侧改动出错 | 需要 Visual Studio 才能回退重链 |
| 数据库结构变更出错 | 依赖迁移的幂等性；必要时从备份恢复数据库 |
| 用户数据被误操作 | 从 U盘备份恢复 |

**要点**：**不要为了「清空重来」而删除交付文件夹。** 先把现有文件夹复制为 `_backup_YYYYMMDD/`，确认新包可用后再替换。zip 不能替代文件夹本身——当被替换的就是那个文件夹时。

## 13. 常见问题

| 问题 | 原因与处理 |
|---|---|
| `Unable to find suitable Visual Studio toolchain` | 本机无 VS；按第 10 节走 AOT 重建路径（前提：未改 `windows/`） |
| `Error when reading '...': No such file or directory`（dart.exe） | 用了 Git Bash 的 `/c/...` 路径；改用 `C:/...` |
| 重建后应用行为没变 | 改动未进入 AOT 快照；用 UTF-16LE 搜索验证，或检查 `app.so` 体积 |
| 改了版本号但应用内不显示 | Dart 代码未引用 `FLUTTER_BUILD_NAME`，被 tree-shaker 删除 |
| 导入教材词表提示联网 | 发布包缺 `assets/tts_seed/`；重新打包并确认资源完整 |
| 应用启动即退出 | `sqlite3.dll` 未与 exe 同目录 |
| 换电脑后数据为空 | 数据在 `%APPDATA%`，每台设备独立；需用备份迁移 |
| 备份后听写没声音 | 备份未包含录音文件；备份必须打包数据库 + 全部录音 |
| 恢复后应用没重启 | 恢复流程应在完成后自动拉起新实例 |
| 恢复包报路径非法 | 防 zip-slip 校验生效；检查压缩包内是否含越权路径 |
| 新页面不显示在导航 | 忘记在 `pages/home_shell.dart` 的导航中加入 |
| 新增发音目录没生效 | `pubspec.yaml` 中未声明该 `assets/tts_seed/gNN/` 目录（目录声明不递归） |
| `flutter analyze` 报错 | 提交前必须修到 0 问题 |
| 中文路径下构建失败 | 源码必须位于纯 ASCII 路径（`C:\dev\classroom_manager`） |
