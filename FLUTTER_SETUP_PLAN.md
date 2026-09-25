# Flutter 开发环境 — 配置完成记录

配置时间：2026-09-19 · 机器：Windows 10 专业版 22H2 (19045) · 管理员账户 Administrator

## 最终状态：`flutter doctor` 除 Chrome 外全绿

```
[√] Flutter (Channel stable, 3.47.4, at D:\src\flutter)
[√] Windows Version (10 专业版 64 位, 22H2, 2009)
[√] Android toolchain (Android SDK version 36.0.0) — All Android licenses accepted
[√] Visual Studio - develop Windows apps (Visual Studio 生成工具 2022 17.14.41)
[√] Connected device (3 available)
[√] Network resources
[X] Chrome — 未安装；本机 Web 调试请用 Edge（flutter run -d edge）
```

## 已安装组件与路径

| 组件 | 路径 | 版本 |
|---|---|---|
| Flutter SDK (git 仓库，可 `flutter upgrade`) | `D:\src\flutter` | 3.47.4 stable |
| Dart SDK（Flutter 内置，未单独安装） | `D:\src\flutter\bin\cache\dart-sdk` | 3.13.3 |
| pub 缓存（**必须在 D 盘**，见下方坑 2） | `D:\pub-cache` | — |
| Android Studio（原本就在，之前漏检） | `D:\Android Studio` | AI-261.26222 |
| Android SDK | `C:\Users\Administrator\AppData\Local\Android\Sdk` | platform 36 + 37.0 |
| Android NDK | `...\Android\Sdk\ndk\28.2.13676358` | Flutter 3.47 默认要求 |
| Android cmdline-tools（**经典版 19.0**，见坑 1） | `...\Android\Sdk\cmdline-tools\latest` | 19.0 |
| 模拟器 + AEHD 加速驱动（服务名 `aehd`，已 RUNNING） | `...\Android\Sdk\emulator` | 37.1.11 |
| 模拟器镜像 AVD `miga_api36` | `%USERPROFILE%\.android\avd` | android-36 google_apis x86_64 |
| Temurin JDK 17 | `C:\Program Files\Eclipse Adoptium\jdk-17.0.20.101-hotspot` | 17.0.20.1 |
| VS 2022 Build Tools + MSVC + Windows SDK | `C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools` | 17.14.37710.0 / SDK 10.0.26100.0 |
| Git | `C:\Program Files\Git\cmd\git.exe` | 2.55.0 |

> 注：Flutter 优先使用 **Android Studio 自带的 JBR (JDK 25)**，而不是上面的 Temurin 17（doctor 会显示 `D:\Android Studio\jbr\bin\java`）。两者都能正常构建，无需干预。

## 环境变量

| 变量 | 作用域 | 值 |
|---|---|---|
| `PATH` | User（追加） | `D:\src\flutter\bin` |
| `PATH` | Machine（追加） | `...\Android\Sdk\platform-tools`、`...\cmdline-tools\latest\bin`、`...\emulator` |
| `JAVA_HOME` | Machine | `C:\Program Files\Eclipse Adoptium\jdk-17.0.20.101-hotspot\` |
| `ANDROID_HOME` / `ANDROID_SDK_ROOT` | Machine | `C:\Users\Administrator\AppData\Local\Android\Sdk` |
| `PUB_CACHE` | User | `D:\pub-cache` |

**改完 PATH 需新开终端才生效。**

## 踩过的坑（重要，避免重犯）

### 坑 1：新版 Android cmdline-tools 会让 Gradle 崩溃
`cmdline-tools` 23.0（Android CLI）已废弃经典 `sdkmanager` 行为。Gradle 配置阶段仍用
`sdkmanager --install "platforms;android-36"` 这种老语法补装包，新 CLI 会把
`platforms;android-36` 拆成两个包名然后**直接崩溃**（退出码 `-1073740791` = `0xC0000409`），
表现为 `Process 'command sdkmanager.bat' finished with non-zero exit value -1073740791`。

**已处理**：换装经典版 `commandlinetools-win-13114758`（Pkg.Revision 19.0），新版备份在
`D:\setup\cmdline-tools-23-newcli-backup`。**不要**用 `sdkmanager` 升级 cmdline-tools。

### 坑 2：项目在 D 盘、pub 缓存在 C 盘 → Kotlin 编译必然失败
```
IllegalArgumentException: this and base files have different roots:
  C:\Users\...\Pub\Cache\hosted\pub.dev\...\XxxPlugin.kt  and  D:\MIGA\android
```
Kotlin 增量编译要把源文件写成相对项目根的路径，跨盘无法计算相对路径。
**已处理**：`PUB_CACHE` 指向 `D:\pub-cache`（用户级持久变量）。
若以后把项目搬到别的盘，`PUB_CACHE` 必须跟着放到同一盘。`flutter clean` 治不了这个。

### 坑 3：VS Build Tools 曾注册损坏
首次安装被中断，导致 `vswhere` 枚举不到实例、`flutter doctor` 报"未安装"，
且 `repair` 也无法生成日志。**已处理**：`InstallCleanup.exe -f` 彻底清理后重新安装，
现在 vswhere 正常返回、`MSBuild.exe` 与 Windows SDK 齐全。若再出现 doctor 报 VS 未安装，
优先怀疑注册损坏而不是组件缺失。

### 坑 4：真机签名冲突
手机 `24129PN74C` (45e38878) 上已装的 `com.miga.android` 是用**另一把密钥**签的：
```
INSTALL_FAILED_UPDATE_INCOMPATIBLE: Existing package com.miga.android signatures do not match
```
要用 debug 包覆盖，必须先 `adb uninstall com.miga.android`（**会清空 App 数据**）。
或者用 `--release` 配合正确的签名配置。

## 常用命令

```powershell
flutter doctor -v                  # 体检
flutter devices                    # 查看设备（真机 / Windows / Edge）
flutter emulators --launch miga_api36
flutter run -d 45e38878            # 跑真机
flutter run -d windows             # 跑 Windows 桌面
flutter run -d edge                # 跑 Web（用 Edge，因为没有 Chrome）
flutter build apk --debug          # 打 Android debug 包
flutter pub upgrade                # 升级依赖
```

## D:\MIGA 这个项目

- 当前**只有 android / linux 平台目录，没有 `windows/`**。要跑 Windows 桌面需先执行一次：
  ```powershell
  cd D:\MIGA
  flutter create --platforms=windows .
  ```
  该命令只补平台目录，不动 `lib/`。
- Android debug 构建已验证：`build\app\outputs\flutter-apk\app-debug.apk`（169.5 MB），
  在模拟器 `miga_api36` 上安装并成功启动。
- 旧的构建产物已备份到 `D:\setup\miga-apk-backup`（`flutter clean` 前备份的）。
- `android/build.gradle.kts` 里有针对 `file_picker 8.3.7` 强制 `compileSdk = 36` 的补丁。
- 构建时有 warning：`m3e_core`、`share_plus` 仍在应用 Kotlin Gradle Plugin（KGP），
  Flutter 未来版本会拒绝构建，属于上游插件问题，暂时无碍。

## Windows 桌面冒烟测试（已完成）

独立示例工程 `D:\src\smoke_win`（不污染 MIGA 仓库）：

```
flutter create --platforms=windows D:\src\smoke_win
cd D:\src\smoke_win
flutter build windows --debug
√ Built build\windows\x64\runner\Debug\smoke_win.exe
```

并实际运行过 `smoke_win.exe`（进程正常存活），确认 MSVC + Windows SDK 链路完全打通。

## 未做 / 可选项

- **Chrome 未安装**：Web 目标用 Edge 即可（`flutter run -d edge`）。若确实需要 Chrome，
  `winget install Google.Chrome`。
- **未单独安装 Dart SDK**：Flutter 自带，日常用 `D:\src\flutter\bin\dart.bat`。
- **未给 D:\MIGA 添加 windows 平台目录**：留给你决定（命令见上）。
- 系统代理为 `127.0.0.1:7890`，但实测 GitHub / Google 直连正常且更快
  （Google 源 7.65 MB/s vs 代理 0.02 MB/s）。git 未配置代理。
