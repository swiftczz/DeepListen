# DeepListen

[English](README.md) | **简体中文**

> 一款帮助英语学习者听得更多、理解得更清楚，并能反复练习困难句子的原生 macOS 播放器。

[![Release](https://img.shields.io/github/v/release/swiftczz/DeepListen?label=release)](https://github.com/swiftczz/DeepListen/releases/latest)
![Platform](https://img.shields.io/badge/macOS-26.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.3-orange)

DeepListen 主要面向生活在非英语环境中的英语学习者。当日常英语输入有限时，电影、播客、访谈和课程都是很好的学习材料，但自然语速往往太快，普通播放器很难让人真正听清和反复练习。

DeepListen 可以把本地音频、视频和字幕变成一个专注的精听工作区。你可以跟随逐词高亮理解语音，点击任意字幕重新播放，降低难句速度，循环当前句，或者设置 A/B 片段进行反复练习。

## 界面预览

![DeepListen 主界面](docs/images/deeplisten-main.png)

## 为什么使用 DeepListen？

### 为自己创造英语环境

使用你真正感兴趣的内容练习：电影、电视剧、播客、课程、访谈或考试录音。DeepListen 面向本地媒体文件，不会把你的学习材料限制在某个内容平台中。

### 把“听到的声音”和“看到的单词”连接起来

播放时，当前字幕会放大并逐词高亮，帮助你注意连读、弱读、节奏，以及母语者自然表达中那些容易“消失”的单词。

### 精确重复没有听懂的部分

点击任意字幕即可直接跳转。单句内容可以使用“循环本句”，跨越多行字幕的片段则可以手动设置 A 点和 B 点。

### 按自己的节奏练习

降低速度分析发音，恢复正常速度检验理解，也可以随时前进或后退 5 秒，不打断练习注意力。

## 一套简单的精听流程

1. 导入一段英语音频或视频。
2. 将对应的 `.srt` 或 `.vtt` 字幕放在媒体文件旁边。
3. 先连续听一遍，找出没有听清的句子。
4. 点击这句字幕，然后开启“循环本句”。
5. 跟随逐词高亮，模仿发音并反复收听，直到能够听清。
6. 关闭循环，继续在完整上下文中练习。

这套流程适合英语精听、跟读准备、发音辨析，以及 IELTS 等英语听力练习。

## 面向听力练习的功能

### 交互式字幕

- 当前句专注模式和全文上下文模式
- 跟随播放进度的逐词高亮
- 点击任意字幕即可跳转到对应位置
- 全文稿自动跟随，手动滚动后可一键恢复
- 稳定的句间切换：下一句开始前，上一句保持高亮
- 自动清理字幕中的常见标记
- 支持 UTF-8、UTF-16、GB18030 和 ISO-Latin1 编码

普通字幕通常只有整句时间，而没有每个单词的时间。DeepListen 会按照整句持续时间估算单词进度，提供直观的听读辅助。

### 重复练习工具

- “循环本句”自动使用当前字幕的起止时间
- 点击其他字幕时，单句循环会跟随到新句子
- 手动设置 A/B 点，练习跨越多行字幕的短语或片段
- 显示清晰的 A/B 时间和范围
- 支持顺序播放和单曲循环

### 播放控制

- 0.25x–2.0x 倍速播放，步进 0.25x
- 前进和后退 5 秒
- 精确拖动进度条并悬停预览时间
- 支持 macOS 系统媒体控制和“正在播放”信息
- 自动恢复上次选择的媒体和播放位置
- 自动保存倍速、播放模式、主题色和字幕偏好

### 本地媒体库

- 导入单个文件或整个文件夹
- 递归扫描文件夹并跳过隐藏文件
- 按文件名自然排序并自动避免重复导入
- 支持搜索、拖拽排序、多选删除和“在访达中显示”
- 支持格式：`mp3` `m4a` `aac` `wav` `aiff` `aif` `caf` `flac` `mp4` `m4v` `mov` `avi` `mkv`

### 原生 macOS 体验

- 面向 macOS 26 设计的 SwiftUI 界面
- Liquid Glass 控件和 9 种主题色
- 自动适应窄窗口和宽窗口
- 支持键盘导航和 VoiceOver

## 安装

1. 前往 [Releases](https://github.com/swiftczz/DeepListen/releases/latest)，下载适合当前 Mac 架构的 DMG，或选择 universal 通用版本。
2. 打开 DMG，将 `DeepListen.app` 拖入“应用程序”。
3. 首次启动时右键应用并选择“打开”。

发布包使用 Ad-hoc 签名。如果 Gatekeeper 仍然阻止启动，可执行：

```bash
xattr -dr com.apple.quarantine /Applications/DeepListen.app
```

## 字幕匹配规则

字幕必须与媒体文件放在同一目录，并使用相同的主文件名：

```text
英语练习/
├── Lesson 01.mp3
├── Lesson 01.srt      ← 自动匹配
├── Lesson 02.mp4
└── Lesson 02.vtt      ← 自动匹配
```

DeepListen 每次载入媒体时都会重新查找字幕，因此可以先导入媒体，之后再补充字幕文件。

## 快捷键

| 快捷键 | 功能 |
| --- | --- |
| `Space` | 播放 / 暂停 |
| `←` | 后退 5 秒 |
| `→` | 前进 5 秒 |
| `⌘⇧←` | 上一首 |
| `⌘⇧→` | 下一首 |
| `⌘⌥←` | 后退 5 秒 |
| `⌘⌥→` | 前进 5 秒 |
| `⌘⌥A` | 设置 A 点 |
| `⌘⌥B` | 设置 B 点 |
| `⌘⌥Esc` | 清除 A/B 片段 |
| `⌘⌥S` | 显示 / 隐藏字幕 |

在搜索框或其他文本输入区域编辑时，无修饰键的播放快捷键不会触发。

## 从源码构建

### 环境要求

- macOS 26.0 或更高版本
- Swift 6.3 工具链

### 编译并运行

```bash
./script/build_and_run.sh
```

其他开发模式：

| 命令 | 用途 |
| --- | --- |
| `./script/build_and_run.sh --debug` | 构建并使用 LLDB 调试 |
| `./script/build_and_run.sh --logs` | 启动并跟踪进程日志 |
| `./script/build_and_run.sh --telemetry` | 启动并跟踪应用 subsystem 日志 |
| `./script/build_and_run.sh --verify` | 启动并验证进程是否正常存活 |

### 构建发布 DMG

```bash
APP_VERSION=1.0.0 ./script/build_and_run.sh --build-only universal --sign --dmg
APP_VERSION=1.0.0 ./script/build_and_run.sh --build-only arm64     --sign --dmg
APP_VERSION=1.0.0 ./script/build_and_run.sh --build-only x86_64    --sign --dmg
```

- `--build-only <arch>`：使用 release 配置构建 `universal`、`arm64` 或 `x86_64`
- `--sign`：为应用添加 Ad-hoc 签名
- `--dmg`：在 `dist/` 生成 `DeepListen-<arch>-<version>.dmg`
- `APP_VERSION`：写入 `Info.plist` 和 DMG 文件名；如果省略，则使用最新 Git 标签或 `0.0.0-dev`

## 技术栈

- **SwiftUI** — 界面与交互
- **AVFoundation** — 媒体播放和精确跳转
- **MediaPlayer** — 系统媒体控制和“正在播放”信息
- **Observation** — 应用共享状态
- **Swift Package Manager** — 构建和依赖管理

## 项目结构

```text
DeepListen/
├── .github/workflows/      # 发布自动化
├── docs/images/            # README 图片资源
├── Resources/              # 应用图标
├── script/                 # 构建、运行和打包脚本
├── Sources/DeepListen/
│   ├── App/                # 应用入口和菜单命令
│   ├── Models/             # 音轨、字幕、播放和主题模型
│   ├── Services/           # 播放、媒体发现和系统集成
│   ├── Stores/             # 播放状态和媒体库
│   ├── Support/            # 字幕解析和时间格式化
│   └── Views/              # SwiftUI 视图
├── README.md               # 英文文档
├── README_CN.md            # 简体中文文档
└── Package.swift
```

## 许可证

本项目目前用于个人学习，尚未指定开源许可证。
