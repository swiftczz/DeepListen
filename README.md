# DeepListen

**简体中文** | [English](README.en.md)

一款为英语精听训练打造的 macOS 播放器。导入任意带字幕的音频或视频，配合 A/B 循环、倍速、全文稿与上下文显示，专注打磨听力。

![平台](https://img.shields.io/badge/platform-macOS%2026.0-blue)
![语言](https://img.shields.io/badge/language-Swift-orange)
![版本](https://img.shields.io/badge/version-0.1.0-green)

## 功能特性

### 音频库

- 支持拖入文件、文件夹或通过 Finder 打开音视频
- 自动递归扫描文件夹，按文件名排序
- 支持格式：`mp3` `m4a` `aac` `wav` `aiff` `aif` `caf` `flac` `mp4` `m4v` `mov` `avi` `mkv`
- 媒体库自动持久化，下次打开自动恢复
- 侧边栏搜索、右键「在访达中显示」、从列表移除

### 字幕

- 自动匹配与媒体**同名**的字幕文件（`.srt` / `.vtt`，大小写不敏感）
- 兼容 UTF-8 / UTF-16 / ISO-Latin1 编码
- 自动去除字幕内的 HTML 标签
- 两种显示模式：
  - **当前句**：高亮当前播放字幕，可选展示上一句 / 下一句上下文
  - **全文稿**：完整字幕列表，点击任意一行跳转播放
- 一键显示 / 隐藏字幕与上下文

### 播放控制

- 播放 / 暂停、前进 / 后退 5 秒、拖动进度条精确定位
- 倍速播放：0.25x – 2.0x，步进 0.25x
- 播放模式：顺序播放 / 单曲循环

### A/B 片段练习

- 设置 A 点、B 点，在时间轴上标记并高亮循环区间
- 区间结束时自动回到 A 点循环
- 一键清除片段

### 外观

- 9 种主题色：系统、蓝、紫、粉、红、橙、黄、绿、石墨
- 主题色持久保存
- 自适应窄窗口布局，侧边栏自动收起

## 快捷键

| 快捷键 | 功能 |
| --- | --- |
| `Space` | 播放 / 暂停 |
| `P` | 上一首 |
| `N` | 下一首 |
| `←` | 后退 5 秒 |
| `→` | 前进 5 秒 |
| `A` | 设置 A 点 |
| `B` | 设置 B 点 |
| `Esc` | 清除 A/B 片段 |
| `S` | 显示 / 隐藏字幕 |

## 字幕匹配规则

把字幕文件与音视频文件放在同一目录，并使用**相同的主文件名**，应用会自动加载：

```
我的素材/
├── Lesson 01.mp3
├── Lesson 01.srt      ← 自动匹配
├── Lesson 02.mp4
└── Lesson 02.vtt      ← 自动匹配
```

## 从源码构建

### 环境要求

- macOS 26.0 及以上
- Swift 6.3 工具链

### 构建并运行

```bash
./script/build_and_run.sh            # 构建并启动
./script/build_and_run.sh --debug    # 构建并在 lldb 中调试
./script/build_and_run.sh --logs     # 启动并跟踪进程日志
./script/build_and_run.sh --telemetry# 启动并跟踪 subsystem 日志
./script/build_and_run.sh --verify   # 启动并验证进程存活
```

脚本会执行 `swift build`，把产物打包成 `dist/DeepListen.app`，并注册到 LaunchServices，之后可直接通过 Finder 双击音视频文件用 DeepListen 打开。

如需仅编译不打包：

```bash
swift build
```

### 打包 DMG（Ad-hoc 签名）

`build_and_run.sh` 还支持纯构建模式，产出 Ad-hoc 签名的 `DeepListen.app` 和 DMG，供 CI 或本地出包：

```bash
APP_VERSION=0.1.0 ./script/build_and_run.sh --build-only universal --sign --dmg
APP_VERSION=0.1.0 ./script/build_and_run.sh --build-only arm64     --sign --dmg
APP_VERSION=0.1.0 ./script/build_and_run.sh --build-only x86_64    --sign --dmg
```

- `--build-only <arch>`：`universal` / `arm64` / `x86_64`，release 配置
- `--sign`：Ad-hoc 签名（`codesign -s -`）
- `--dmg`：在 `dist/` 产出 `DeepListen-<arch>-<version>.dmg`
- `APP_VERSION`：写入 `Info.plist` 与 DMG 文件名，默认 `0.1.0`

> ⚠️ Ad-hoc 签名的 app 首次打开会被 macOS Gatekeeper 拦截。放行方式：右键 app →「打开」，或终端执行 `xattr -dr com.apple.quarantine /Applications/DeepListen.app`。

## 自动发布

推送到 GitHub 的 `v*` tag 会触发 [GitHub Actions](.github/workflows/release.yml) 自动构建并发布：

```bash
git tag v0.1.0
git push origin v0.1.0
```

workflow 会在 `macos-26` runner 上构建三个架构的 DMG（universal / arm64 / x86_64），Ad-hoc 签名，创建 GitHub Release 并附挂这三个 DMG，版本号取自 tag。

也可在仓库的 **Actions → Release → Run workflow** 手动触发进行验证，此时 DMG 作为 workflow artifact 下载，不发 Release。

## 默认音频目录

应用启动时若媒体库为空，会尝试自动加载默认音频：

1. App 包内 `Resources/DefaultAudio/`
2. 从工作目录起向上最多 8 层查找 `备考资料/官方材料/音频/`

找到后会自动导入其中可播放的媒体文件。

## 技术栈

- **SwiftUI** —— 整个 UI 层
- **AVFoundation** —— 音视频播放
- **Observation** —— `@Observable` 状态管理
- **Swift Package Manager** —— 依赖与构建

## 项目结构

```
DeepListen/
├── Package.swift
├── .github/
│   └── workflows/
│       └── release.yml     # tag 触发自动构建 DMG 并发 Release
├── Resources/
│   └── AppIcon.icns
├── script/
│   └── build_and_run.sh    # 本地运行 / CI 打包 DMG
└── Sources/DeepListen/
    ├── App/            # @main 入口与菜单命令
    ├── Models/         # 音轨、字幕、播放模式、主题色
    ├── Stores/         # PlayerStore 播放状态
    ├── Services/       # Finder 定位等系统能力
    ├── Support/        # 字幕解析、时间格式化
    └── Views/          # SwiftUI 视图
```

## 许可证

个人学习用途，暂未指定开源许可证。
