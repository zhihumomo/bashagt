# Bashagt — Agents Everywhere / 无处不在的智能体

[English](./README.md) | **中文**

> 一个**纯 Bash** 实现的 LLM 智能体内核 — 零运行时依赖，能在任何类 Unix 环境运行。

[![Bash](https://img.shields.io/badge/bash-4.0%2B-green?logo=gnubash)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20WSL%20%7C%20Termux%20%7C%20iSH-blue)]()
[![Lines](https://img.shields.io/badge/lines-16,796-orange)]()
[![Functions](https://img.shields.io/badge/functions-464-purple)]()
[![License](https://img.shields.io/badge/license-Apache%202.0-blue)](./LICENSE)
[![Status](https://img.shields.io/badge/status-preview-yellow)]()

---

## 🤔 为什么需要 Bashagt？

你有没有过这样的体验——

凌晨两点，生产服务器突然报警。你 SSH 上去，面对一团层层嵌套的调用链和十几万行日志，手指悬在键盘上，脑子里只有一个念头：**"要是 Claude 在这儿就好了。"**

可它不在。

Claude Code、Codex、Cursor……这些 AI 编码助手确实改变了我们写代码的方式。但它们有一个共同的、几乎没人愿意提的软肋：**它们离不开自己的"温室"**。

---

### 🏭 温室里的 AI

现代编码智能体工具几乎无一例外地依赖 Node.js 或者 Python 运行时。这在你的开发机上完全不是问题——Homebrew 一敲，pip install 一跑，环境就绪，AI 就位。

但当你离开开发机，走进下面这些场景，事情就变得微妙起来：

**场景 A：内网机房里的生产服务器**

没有外网。不能随便装包。制品库里躺着的 Python 是八年前的 2.7，Node 更是见都没见过。运维组长从你身后走过，瞟了你屏幕一眼，意思是"别乱搞"。

你说你要在这台机器上装 Claude Code？先不说能不能装上——装上了你敢让它跑吗？一个闭源 AI，跑在存着用户数据的生产环境里，你心跳会不会加速？

**场景 B：下班路上的突发灵感**

通勤地铁上，你突然想到一个绝妙的架构重构方案。掏出手机，想跟 AI 聊聊，让它帮你理一下思路——

然后你意识到，手机上没有 Claude Code。没有 Codex。没有任何一个能读代码、能写代码、能跟你来回推演的 AI 伙伴。电脑在包里，但挤成沙丁鱼的地铁里你连打开它的空间都没有。

---

### 🧱 问题的本质

这两个场景看似不同，根因却是同一个：

> **现有 AI 编码工具被锁死在"开发者工作站 + 现代软件栈"这个组合上。**

Node 和 Python 是它们呼吸的空气。一旦离开这个生态——无论是进了内网机房，还是上了手机平板——它们就"窒息"了。

可现实是：**世界上运行着 Linux 的地方，远比你放开发机的桌子多得多。**

路由器里跑着 Linux。电视盒子里跑着 Linux。你十年前买的树莓派在角落里吃着灰，它上面也跑着 Linux。还有成千上万台生产服务器、边缘设备、嵌入式板卡……它们共同的特点是：**只有 bash。**

bash 是 Unix 世界的公分母。它不挑硬件，不挑发行版，不挑内核版本。Linux 有它，macOS 有它，Windows 的 WSL 有它，就连你 Android 手机上的 Termux、iPhone 上的 iSH，都有它。

**那为什么没有一个 AI 智能体，可以直接跑在 bash 上？**

---

### ✨ 于是就有了 Bashagt

Bashagt 就是这个问题的答案。

它是一个 **16796 行纯 bash 脚本**。没有 Node。没有 Python。没有 pip。没有 npm。没有任何你叫得上名字的运行时依赖。

它的全部身家就是三个东西——三样在任何类 Unix 系统上都唾手可得的东西：

```
bash 4.0+   +   jq   +   curl
```

那不是三个"依赖"，那是三个"标配"。

这意味着：**任何有 bash 的地方，就是 Bashagt 可以工作的地方。**

| 你在哪里 | Bashagt 怎么跑 |
|---------|---------------|
| 🖥️ 开发机 | 交互式对话，替代 Claude Code 日常使用 |
| 🏭 内网服务器 | SSH 上去直接跑，排查日志、分析配置 |
| 📱 Android 手机 | 通过 Termux 运行，还能调用摄像头/短信/GPS |
| 🍎 iPhone/iPad | 通过 iSH 运行，地铁上随时跟 AI 推演方案 |
| 🪟 Windows | 通过 WSL 无缝运行，访问 Windows 文件系统 |
| 🥧 树莓派 | 插上电就能跑，做个家用 AI 终端 |
| 🌐 路由器/嵌入式 | 理论上，只要能跑 bash 4.0+…… |

---

### 🔮 愿景

我们相信，AI 编程助手不应该被锁在"开发者工作站"这个小圈子里面。

它应该能跟着你进机房，能揣在兜里陪着你通勤，能蹲在树莓派上帮你打理 NAS，能睡在路由器里监控家庭网络。

Bashagt 只是一颗种子。但它指向的方向很简单：

> **每一台运行着 bash 的机器，都应该能拥有一个 AI 智能体。**

或许等这个愿景成真的时候，人们回过头来看"必须装 Node 和 Python 才能用 AI 编程助手"这件事，会觉得和我们看"必须插着电话线才能上网"一样不可思议。

---

*当然，目前是 preview 版，很多功能还在开发，bug 也不会少。欢迎提 Issue 和 PR。*

*如果你对 Bashagt 项目感兴趣，欢迎加入项目 QQ 交流群 198302483。 答案 State。*

---

## ✨ 特性

- 🐚 **纯 Bash 实现** — 16,796 行代码，464 个函数，无 Node/Python 运行时依赖
- ⚡ **零 Fork 热路径** — 增量消息拼接、哈希驱动缓存、纯 bash 请求体、跨回合持久化渲染器；最小化每轮 subshell 开销
- 🖥️ **全平台覆盖** — Linux (GNU)、macOS (BSD)、WSL、Termux (Android)、iSH (iPhone/iPad)
- 🔧 **24 个内置工具** — 文件读写编辑删除、命令执行、网页搜索、子智能体调用、TODO 管理、技能系统……
- 🤖 **子智能体系统** — 11 个系统智能体（plan/explore/review/summarize……）+ 可自定义项目智能体
- 🧠 **分布式记忆网络** — 16 个 engram × 200 slots = 3,200 条持久记忆，支持语义搜索
- 🌐 **HTTP 守护进程** — REST API + SSE 流式输出，可作为后端服务运行
- 🔌 **MCP 协议支持** — Model Context Protocol（stdio/sse/http 三种传输），连接外部工具生态
- 🪝 **Hook 插件系统** — 8 个挂载点、6 种处理器类型，可深度定制行为
- 📦 **四级上下文压缩** — 自动管理超过 250KB 的对话上下文
- ↩️ **Trace/Undo** — 内容寻址的文件修改追踪，支持回滚
- 🔄 **自适应智能体循环** — 三条保护机制，防止无限循环
- 🧠 **穷尽式推理** — 系统提示要求最大化推理投入：全面分解问题、对所有边界情况严格逻辑压力测试、完整记录思考过程
- ⌨️ **完整 Readline** — 支持 Unicode/CJK 字符、多行编辑、历史搜索、Tab 补全、稳定的自动换行渲染
- 📱 **Termux-API 集成** — 在 Android 手机上控制传感器、摄像头、短信等
- 🔄 **自我进化** — Bashagt 能读懂并修改自己的源码。你可以直接用对话让它给自己加功能：说一句"帮我加个 --version 参数"，它读代码、改代码、验证、完成

---

## 🚀 快速开始

### 核心依赖

Bashagt 的依赖极简，仅需以下三个基础工具（在所有主流平台上都可通过包管理器一键安装）：

| 依赖 | 最低版本 | 用途 |
|------|---------|------|
| **bash** | 4.0+ | 脚本运行时。绝大多数现代系统已内置。 |
| **jq** | 任意版本 | JSON 解析与处理，用于 API 通信和配置文件读写。 |
| **curl** | 任意版本 | HTTP 客户端，与 LLM API 端点通信。 |

此外，在 **Termux (Android)** 上还需额外安装 `coreutils` 包（用于 `realpath`/`nl` 等 GNU 工具）。各平台安装步骤见下方。

---

### 安装：各平台详细指南

Bashagt 的安装流程统一为三步：

```
1. 获取脚本   →   2. 安装依赖   →   3. ./bashagt --install
```

其中 `--install` 会自动完成：创建 `~/.bashagt/` 目录树、生成默认配置文件、注册 bash/zsh 快捷键、注册 `bashagt` 命令到 PATH。

---

#### 🐧 Linux / Unix（通用）

适用于所有主流 Linux 发行版（Debian/Ubuntu、RHEL/CentOS、Arch、Alpine、openSUSE 等）及传统 Unix。

**第一步：安装依赖**

```bash
# Debian / Ubuntu
sudo apt install jq curl

# RHEL / CentOS / Fedora
sudo dnf install jq curl

# Arch Linux
sudo pacman -S jq curl

# Alpine Linux
sudo apk add jq curl bash
```

> 大多数 Linux 的默认 bash 版本 ≥4.0。确认版本：`bash --version`

**第二步：获取 Bashagt**

```bash
git clone https://github.com/zhihumomo/bashagt.git
cd bashagt
```

**第三步：一键安装**

```bash
./bashagt --install
```

此命令会：
- 将 `bashagt` 复制到 `~/.bashagt/`
- 创建 `~/.local/bin/bashagt` 符号链接（确保 `~/.local/bin` 在 PATH 中）
- 生成 `~/.bashagt/settings.json` 配置文件
- 注册热键：`Ctrl+G`（bash）或 `Ctrl+T`（zsh）快速打开对话

完成后在任意目录输入 `bashagt` 即可启动。

---

#### 🍎 macOS

**第一步：安装依赖**

macOS 自带 bash 3.2（太旧），需要安装新版 bash。推荐使用 Homebrew：

```bash
# 安装 Homebrew（如尚未安装）
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 安装依赖
brew install bash jq curl
```

Homebrew 安装的 bash 位于 `/opt/homebrew/bin/bash`（Apple Silicon）或 `/usr/local/bin/bash`（Intel）。Bashagt 的 shebang 为 `#!/usr/bin/env bash`，只需确保 Homebrew 路径在 `/etc/paths` 中排在 `/bin` 之前即可自动使用新版。

```bash
# 确认版本（应显示 5.x）
bash --version
```

> 💡 **macOS 快捷键**：`--install` 会自动检测当前终端应用（Terminal.app / iTerm2 / Warp 等），并在终端偏好设置中绑定 `Cmd+G` 或 `Cmd+T` 作为快捷启动键。如果使用 iTerm2，需要在 Preferences → Keys 中手动添加或确认映射。

**第二步 & 第三步：同 Linux**

```bash
git clone https://github.com/zhihumomo/bashagt.git
cd bashagt
./bashagt --install
```

---

#### 🪟 Windows（基于 WSL）

Bashagt 通过 WSL (Windows Subsystem for Linux) 在 Windows 上运行。

**第一步：安装 WSL（如尚未安装）**

在 PowerShell 或 CMD（管理员）中运行：

```powershell
wsl --install
```

默认安装 Ubuntu。重启后进入 WSL 终端，按 Linux 指南继续。

**第二步：安装依赖**

```bash
sudo apt update
sudo apt install jq curl
```

**第三步 & 第四步：同 Linux**

```bash
git clone https://github.com/zhihumomo/bashagt.git
cd bashagt
./bashagt --install
```

> 💡 在 WSL 中，`bashagt` 可以直接访问 Windows 文件系统（`/mnt/c/`、`/mnt/d/` 等），可以操作 Windows 项目文件。

---

#### 📱 Android（基于 Termux）

Termux 是 Android 上的终端模拟器与 Linux 环境，无需 root。Bashagt 完整支持 Termux，包括与 Android 系统 API 集成。

**第一步：安装 Termux**

从 [F-Droid](https://f-droid.org/packages/com.termux/) 安装 Termux（推荐 F-Droid 版本，更新及时；Google Play 版本已停止维护）。

**第二步：安装依赖**

```bash
pkg update && pkg upgrade

# 安装核心依赖
pkg install bash jq curl git coreutils

# 确认 bash 版本（Termux 默认安装 bash 5.x）
bash --version
```

| 补充包 | 用途 |
|--------|------|
| `coreutils` | 提供 `realpath`、`nl` 等 GNU 工具，Bashagt 依赖这些。**必须安装。** |
| `termux-api` | Android API 桥接（可选）。安装后 Bashagt 可通过 Termux-API 工具控制手机硬件，见下方"Termux-API 集成"。 |

**第三步：安装 Bashagt**

```bash
git clone https://github.com/zhihumomo/bashagt.git
cd bashagt
./bashagt --install
```

> **关于存储访问**：Termux 默认只能访问内部存储的共享目录 `~/storage/shared/`。如需访问外部 SD 卡或其他位置，运行 `termux-setup-storage` 授予存储权限。

---

##### 🔧 挂载外部磁盘

在 Termux 中操作外部 SD 卡或 USB 存储设备，使用以下方法：

```bash
# 申请存储权限（仅需一次）
termux-setup-storage

# 之后即可通过软链接访问
ls ~/storage/
#   dcim/       → 相机照片
#   downloads/  → 下载目录
#   external-1/ → 外部 SD 卡（如有）
#   music/      → 音乐
#   shared/     → 内部共享存储
```

如果需要在 Bashagt 中操作外部存储上的项目，直接将工作目录切换到对应路径：

```bash
cd ~/storage/external-1/my-project
bashagt
```

对于通过 OTG 连接的 USB 设备，Termux 中挂载需借助 `termux-usb` 工具（见下方 Termux-API）。

---

##### 📲 使用 Termux-API 掌控你的手机

安装 `termux-api` 包后，Bashagt 可以直接调用 Android 系统 API，实现对手机硬件的智能控制。

**安装 Termux-API**

1. 安装 F-Droid 上的 [Termux:API](https://f-droid.org/packages/com.termux.api/) 配套应用
2. 在 Termux 中安装命令行工具：

```bash
pkg install termux-api
```

**可用能力**

安装后，以下 `termux-*` 命令立即可用。Bashagt 在 Termux 环境下会自动感知这些工具，你可以在对话中直接要求：

| 能力 | 命令示例 | 对话用法举例 |
|------|---------|-------------|
| 📷 **拍照** | `termux-camera-photo` | "帮我拍张照，然后分析照片里的文字" |
| 📍 **定位** | `termux-location` | "获取当前 GPS 位置，查找附近的餐厅" |
| 📱 **短信** | `termux-sms-send` | "给张三发条短信，内容为会议改到下午三点" |
| 📞 **通话** | `termux-telephony-call` | "拨打 10086 客服热线" |
| 🔊 **扬声器** | `termux-volume` | "把媒体音量调到 50%" |
| 🔔 **通知** | `termux-notification` | "十分钟后提醒我喝水" |
| 💡 **手电筒** | `termux-torch` | "打开闪光灯 10 秒" |
| 🔋 **电池** | `termux-battery-status` | "检查手机电量，低于 20% 就提醒我" |
| 📋 **剪贴板** | `termux-clipboard-get/set` | "读取剪贴板内容并翻译成英文" |
| 🎤 **麦克风** | `termux-microphone-record` | "录音 30 秒然后转文字" |
| 🎵 **媒体** | `termux-media-player` | "播放 Downloads 文件夹里的音乐" |
| 🔄 **传感器** | `termux-sensor` | "读取加速度传感器数据，检测手机是否在移动" |
| 💻 **USB** | `termux-usb` | "检测 OTG 连接的 USB 设备" |

> ⚠️ 使用这些功能需要在 Android 系统中授予 Termux 对应权限（存储、相机、定位、短信、通话等），首次使用时系统会自动弹出权限请求。

---

#### 📱 iPhone / iPad（基于 iSH）

iSH 是在 iOS 上运行的 Alpine Linux 模拟器，让 iPhone/iPad 拥有真正的 Linux 终端。

**第一步：安装 iSH**

从 [App Store](https://apps.apple.com/app/ish-shell/id1436902243) 安装 iSH。

**第二步：安装依赖**

在 iSH 中打开终端：

```bash
# 更新包索引（iSH 使用 Alpine 包管理器）
apk update
apk add bash jq curl git coreutils

# 确认 bash 版本
bash --version
```

**第三步：安装 Bashagt**

```bash
git clone https://github.com/zhihumomo/bashagt.git
cd bashagt
./bashagt --install
```

> ⚠️ **iSH 限制须知**：
> - iSH 是 x86 模拟层，性能受限于 iOS 的 JIT 限制，LLM API 调用本身通过网络，速度正常，但本地 bash 计算会比真机慢
> - 不支持后台守护进程模式（`--run`），但交互式和单次模式完全可用
> - UTF-8/CJK 字符渲染正常，支持中文对话

---

### 配置 API Key

安装完成后，编辑 `~/.bashagt/settings.json` 填入 API 信息：

```json
{
  "api_url": "https://api.deepseek.com/anthropic",
  "api_key": "sk-your-api-key-here",
  "model": "deepseek-chat",
  "max_tokens": 8192,
  "thinking_budget": 16384
}
```

> **兼容后端**：Bashagt 使用 Anthropic Messages API 协议。默认配置指向 DeepSeek，你也可以切换到：
> - **Anthropic 官方**：`"api_url": "https://api.anthropic.com"`，`"model": "claude-sonnet-4-20250514"`
> - **其他 OpenAI 兼容端点**：如 Ollama、vLLM、LiteLLM 等本地部署的模型

**安全方式（推荐）**：不将 API Key 写入配置文件，而是使用环境变量：

```bash
export BASHAGT_API_KEY="sk-your-api-key-here"
```

环境变量优先级高于配置文件（四级配置：默认值 → settings.json → 项目 settings.json → 环境变量）。

---

### 启动

安装和配置完成后，在终端输入 `bashagt` 即可：

```bash
# 交互式对话模式（默认）
bashagt

# 单次模式 — 管道输入，输出结果后退出
echo "解释这段代码" | bashagt --oneshot

# 流式单次模式 — 纯 JSONL 格式输出，适合脚本解析
echo "分析日志" | bashagt --oneshot --stream

# 启动 HTTP 守护进程（默认端口 9655）
bashagt --run

# 前台调试模式（守护进程 + 日志输出到终端）
bashagt --run --debug --port 9655

# 更新脚本到最新版本
./bashagt --update
```

各模式的详细用法见下方 [使用示例](#-使用示例) 章节。

---

## 📋 使用场景

---

### 🛠️ 日常开发辅助

你正在重构一个老模块，调用链深到 IDE 都跳不动。打开终端，让 Bashagt 代劳——

```bash
$ bashagt
bashagt> 这个项目里有哪些地方调用了 PaymentService.process()？
bashagt> 帮我梳理一下 src/auth/ 下所有文件的依赖关系
bashagt> 给 UserController 的每个接口写中文注释
```

不用切窗口，不用装插件，就在终端里，它读完你的代码直接回答。

---

### 🔄 CI/CD 代码审查

每次 PR 都靠人肉 review 太累。把它挂到 CI 管道里：

```bash
# 审查最近一次提交的变更
git diff HEAD~1 | bashagt --oneshot

# 审查指定两个分支的差异
git diff main...feature-branch | bashagt --oneshot

# 结合 lint 输出一起送审
eslint src/ --format json | bashagt --oneshot
```

单次模式输出完就退出，不占常驻进程，CI 友好。

---

### 🏭 生产服务器排障

线上突然 502。你 SSH 上去，面对几十 G 的日志和一堆不知什么时候改过的配置文件：

```bash
$ ssh production-server
$ cd /var/log/app
$ bashagt

bashagt> 近一小时内 nginx 错误日志里的 top 5 报错是什么？
bashagt> 检查 /etc/nginx/nginx.conf 里有没有可能导致 502 的配置
bashagt> 对比 /etc/nginx/sites-enabled/ 下三个配置文件，找出不一致的地方
```

不需要装任何特殊工具——服务器上本来就有 bash。整个排查过程在终端里一口气完成。

---

### 🌐 作为后端 API 服务

你想在自己的应用里嵌入一个 LLM 对话能力，但不想引入 Python/Node 的庞大依赖链：

```bash
# 启动守护进程
bashagt --run --port 9655

# 你的应用代码里调用（任意语言，能发 HTTP 就行）
curl -X POST http://localhost:9655/v1/session/new          # 创建会话
curl -X POST http://localhost:9655/v1/session/{id} \        # 发送消息
  -d '{"message": "解析下面这段 JSON 并生成对应的 TypeScript 类型"}'
curl -N http://localhost:9655/v1/session/{id}/stream         # SSE 流式接收回复
```

一个 15K 行的 bash 脚本就是你的 LLM 网关。

---

### 📱 手机上的编程助手（Termux）

地铁上想快速验证一个想法，或者临时需要改一段代码：

```bash
$ bashagt
bashagt> 用 awk 写一个命令，统计 access.log 里每个 IP 的请求次数，按降序排列
bashagt> 我的 Android 项目在 ~/storage/shared/MyApp，找到所有用了 deprecated API 的地方
```

配上 Termux-API，还能让 Bashagt 帮你操控手机：

```bash
bashagt> 拍张照，然后看看照片里有没有文字，有的话提取出来
bashagt> 给通讯录里的"老板"发短信："已收到，正在处理"
bashagt> 获取当前 GPS 坐标，告诉我离这儿最近的地铁站
```

---

### 🍎 iPhone/iPad 上的终端伴侣（iSH）

iPad 外接了键盘但不想带笔记本——iSH 就是你的轻量 Linux 环境：

```bash
$ bashagt
bashagt> 我有一段 Python 代码，帮我检查有没有潜在的内存泄漏
bashagt> 解释一下这段正则表达式在匹配什么: (?<=@)\w+(?=\.)
bashagt> 把这个 JSON 转成 YAML 格式
```

交互式和单次模式都能跑，API 调用走网络，响应速度和桌面端无异。

---

### 🔒 内网 / 离线环境

最极端的场景：一台跟互联网物理隔离的机器，但你能在内网部署一个 LLM API（比如 Ollama 或 vLLM）：

```bash
# 配置内网 API 端点
export BASHAGT_API_URL="http://192.168.1.100:11434/api/chat"
export BASHAGT_API_KEY="ollama"

# 照常使用
bashagt
```

整台机器上不需要 Node，不需要 Python。**bash + jq + curl 三件套**，任何一个正经 Linux 发行版都自带或一行命令装齐。

---

## 🔧 使用示例

### 交互式对话

```bash
$ bashagt

  ██████╗  █████╗ ███████╗██╗  ██╗ █████╗  ██████╗ ████████╗
  ██╔══██╗██╔══██╗██╔════╝██║  ██║██╔══██╗██╔════╝ ╚══██╔══╝
  ██████╔╝███████║███████╗███████║███████║██║  ███╗   ██║
  ██╔══██╗██╔══██║╚════██║██╔══██║██╔══██║██║   ██║   ██║
  ██████╔╝██║  ██║███████║██║  ██║██║  ██║╚██████╔╝   ██║
  ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝    ╚═╝

  Model: deepseek-v4-pro[1m]           Thinking: status
  Endpoint: api.deepseek.com/anthropic
  Author: Lucas                        Version: preview-0.1

  > /help          # 查看内置斜杠命令
  > 帮我分析这段代码的性能瓶颈
  > 查找所有调用 login() 函数的地方
  > 给这个模块写单元测试
```

### 管道模式

```bash
# 代码审查
git diff HEAD~1 | bashagt --oneshot

# 日志分析
tail -100 /var/log/app.log | bashagt --oneshot

# 配置生成
cat schema.json | bashagt --oneshot --stream
```

### 守护进程 API

```bash
# 启动服务
bashagt --run --port 9655

# 创建会话
curl -X POST http://localhost:9655/v1/session/new

# 发送消息
curl -X POST http://localhost:9655/v1/session/{id} \
  -H "Content-Type: application/json" \
  -d '{"message": "你好"}'

# SSE 流式订阅
curl -N http://localhost:9655/v1/session/{id}/stream
```

---

## 🔄 自我进化：让 Bashagt 给自己写功能

这可能是 Bashagt 最特别的能力——因为它本身就是一个纯文本的 bash 脚本，而它又拥有读写文件、执行命令的工具，所以 **Bashagt 可以直接修改自己的源代码**。

你说一句话，它加一个功能。

---

### 它是怎么做到的？

过程非常简单，和它帮你改项目代码一模一样：

```
你说："帮我加个 --version 参数，打印版本号"
         ↓
Bashagt: 先读自己的 main() 函数，理解命令行参数解析的结构
         ↓
Bashagt: 用 edit_file 工具在合适位置插入 --version 分支
         ↓
Bashagt: 用 bash 工具运行 ./bashagt --version 验证效果
         ↓
Bashagt: 确认无误，报告完成 ✅
```

你不需要打开编辑器，不需要知道代码在哪一行，不需要测试。整个过程在对话中一气呵成。

---

### 实际演示

假设你想让 Bashagt 支持显示当前会话的 token 用量统计。你就这么说：

```
bashagt> 帮我加一个 /stats 斜杠命令，显示本次会话的 token 用量和 API 调用次数
```

Bashagt 会自己去源码中找到斜杠命令的注册位置（`_slash_dispatch`），找到统计相关的变量（`TURN_TOKENS_IN`、`TURN_TOKENS_OUT`……），然后插入新命令的实现代码。写完还会自动跑一遍 `bash -n` 做语法检查。

---

### 这意味着什么？

这意味着 Bashagt 的开发模式不再是"你写代码，提交 PR，等合并，再发布"。而是——

> **在你自己的终端里，用对话的方式，随时定制你自己的 Bashagt。**

想要一个新的 CLI 参数？说一句。想给某个工具加个校验逻辑？说一句。想在启动时显示一段自定义 banner？说一句。这些改动就留在你本地的 Bashagt 拷贝里，不需要等上游，不需要 fork 仓库。

当然，不是所有改动都适合这样随手做——架构级的大变更还是需要正经的开发和测试。但对于大量"能不能加个小功能"类的需求，自我进化让 Bashagt 的使用者同时也是它的共同作者。

---

## ⚙️ 配置体系

Bashagt 采用四级配置优先级（后者覆盖前者）：

```
默认值  →  ~/.bashagt/settings.json  →  项目 .bashagt/settings.json  →  环境变量
```

| 配置项 | 环境变量 | 默认值 | 说明 |
|--------|---------|--------|------|
| `api_url` | `BASHAGT_API_URL` | DeepSeek Anthropic 端点 | API 地址 |
| `api_key` | `BASHAGT_API_KEY` | — | API 密钥 |
| `model` | `BASHAGT_MODEL` | `deepseek-chat` | 模型名称 |
| `max_tokens` | `BASHAGT_MAX_TOKENS` | 8192 | 最大输出 token |
| `thinking_budget` | `BASHAGT_THINKING_BUDGET` | 16384 | 思考预算 |
| `proxy_url` | `BASHAGT_PROXY_URL` | — | 代理地址 (http/socks4/socks5) |
| `context_window` | `BASHAGT_CONTEXT_WINDOW` | 128000 | 上下文窗口大小 |

---

## 🏗️ 架构概览

```
┌─────────────────────────────────────────────────────┐
│                    main()                            │
│         (CLI 解析 → 初始化 → 模式分发)                 │
├─────────────────────────────────────────────────────┤
│  • --install       初始化系统目录                      │
│  • --run           启动 HTTP 守护进程                  │
│  • --oneshot       单次管道模式                        │
│  • (默认)          交互式 REPL                        │
└────────────────────┬────────────────────────────────┘
                     │
     ┌───────────────▼──────────────────────┐
     │          agent_loop()                 │
     │  交互式 REPL 或 单次处理入口             │
     └───────────────┬──────────────────────┘
                     │
     ┌───────────────▼──────────────────────┐
     │          run_turn()                   │
     │  用户输入 → API 调用 → 响应解析          │
     │         ↓  stop_reason?                │
     │  end_turn ← 返回用户                    │
     │  tool_use → dispatch_tool → 循环        │
     └───────────────┬──────────────────────┘
                     │
     ┌───────────────▼──────────────────────┐
     │       dispatch_tool()                  │
     │  24 个工具: read_file, write_file,      │
     │  edit_file, bash, agent, web_search,   │
     │  make_todos, skill, request...         │
     └──────────────────────────────────────┘

━━━━━━━━━━━━ 子系统 ━━━━━━━━━━━━

  记忆网络            子智能体系统           Hook系统
  ┌──────────┐       ┌────────────┐       ┌──────────┐
  │16 engrams│       │11 系统智能体│       │ 8 挂载点  │
  │×200 slots│       │ N 项目智能体│       │ 6 处理器  │
  │语义搜索   │       │ 并行批处理  │       │  生命周期  │
  │睡眠压缩   │       │ 异步调度    │       │  热重载   │
  └──────────┘       └────────────┘       └──────────┘
```

### 核心子系统

| 子系统 | 代码段 | 功能 |
|--------|-------|------|
| 工具系统 | §8–§10 | 24 个工具定义、实现、调度 |
| 智能体系统 | §7 | 子智能体加载、调用、通信 |
| 记忆网络 | §7c | 16 engram 分布式记忆，语义搜索，睡眠压缩 |
| 上下文压缩 | §5 | 四级压缩策略 (>250KB 阈值) |
| HTTP/SSE | §6a | curl 封装，SSE 流解析 |
| 守护进程 | §11d | HTTP 服务器、工作池、Cron 调度 |
| MCP 客户端 | §11c | stdio/sse/http 传输，外部工具动态注册 |
| 输入层 | §2b–§2c | 自研 Readline，Unicode/CJK 支持 |
| Trace/Undo | §7f | 内容寻址文件追踪，帧回滚 |
| 自适应循环 | §11b | 三条保护机制 (token/时间/轮次) |
| Hook 系统 | §2 | 8 点 × 6 类型的可扩展架构 |

---

## 🤝 贡献

目前项目处于 **preview** 阶段，功能正在快速迭代中，也存在不少 bug。欢迎：

- 🐛 提交 [Issue](https://github.com/zhihumomo/bashagt/issues) 报告 bug
- 💡 提 Feature Request
- 🔀 提交 Pull Request
- 📖 完善文档

仓库包含完整的测试套件（30 个测试脚本，约 384 KB），覆盖所有主要子系统——工具、Hook、Trace、压缩、输入、UI、SSE、技能及端到端场景。单元测试无需 API key。

运行测试：

```bash
cd test
./run_all.sh                # 单元 + 完整性测试（无需 API）
./run_all.sh --all          # 完整套件，含 E2E（需要 API key）
```

---

## 📝 更新日志

### 2026-06-09 — 集中化调色板 & 配置简化

**🎨 集中化调色板** — 所有终端颜色（语法高亮、界面、diff、闪光、banner、提示符）现在统一定义在单个 `_color_palette()` 函数中 — 色系唯一真理来源。新增 `_color_assemble()` 和懒缓存 `_color_get()` + `_CLR_CACHE`，消除了 `_colors_resolve()`、`_bsrp_assemble()`、`_stream_render()`、`_in_submit_flash()`、`_safe_preview_diff()`、`print_banner()`、`_ui_emit()` 等函数中上百行深色/浅色模式的分支重复代码。深色/浅色模式切换现在只需清空缓存，无需重新执行所有颜色分支。新增调色板条目包括 `diff_add_bg`/`diff_add_fg`/`diff_del_bg`/`diff_del_fg`、`flash_bg`/`flash_fg`/`flash_safe_bg`/`flash_safe_fg`、`prompt_input`/`prompt_safe_on`、`banner_logo_L1`–`L6`/`banner_label` 以及多种强调色。

**🗑️ 移除 `compress_threshold`** — `DEFAULT_COMPRESS_THRESHOLD` 和 `compress_threshold` 配置键从 `_init_settings_template()` 和 `load_config()` 中移除，简化用户配置界面。

**📦 Script 预览框** — bash 命令预览现在渲染为带边框的盒子（`╭── Script ──...╮`），支持 ANSI 剥离后的宽度计算、终端宽度自适应和溢出截断。超过显示宽度的行尾部追加 `…`；超过 30 行显示 `...($N more lines)` 提示。

**🐛 ANSI 剥离修复** — `_strip_ansi_sgr()` 关键修复：多序列 ANSI 剥离现改用 `${_s#*$'\033['*m}` 替代 `${_s#*m}`，正确处理连续转义序列。

**📚 库生成更新** — `_emit_render_lib()` 和 `_emit_request_ui_lib()` 现在嵌入模式感知的 `_clr()` 辅助函数，替代硬编码的 ANSI 颜色变量（`DIM=`、`YELLOW=` 等），使生成的 `render.sh` 和 `request_ui.sh` 库在调用时能响应 `BASHAGT_DARK_MODE`。

**🔍 调试日志扩展** — 新增 `log DEBUG` 日志点：子智能体迭代计数（`iter=$N`）、SSE 数据大小警告（>10KB）、格式化回调生命周期（`before jq`/`after jq`）、stream wrap fd 追踪（`fd1=`/`fd7=`/`fd8=` 含 `readlink`）、FIFO 初始化状态、`main()` `ppid=` 及参数日志。

### 2026-06-05 — 零 Fork 热路径 & 持久化渲染器

**⚡ 零 Fork 热路径** — 增量消息分段缓存（`MSG_PREFIX_INNER`/`MSG_TAIL_INNER`）替代每次消息追加时的全量 jq。`_msg_append_to_tail()` 使用纯 bash 字符串操作 — O(1)，零 jq fork。哈希驱动上下文缓存（`CONTEXT_STATIC` + `_context_rebuild`）仅在时间/记忆/TODO 变化时重建动态上下文。Skill 列表按 `_SKILL_DIR_MTIME` 缓存，工具 JSON 300s TTL 缓存。`_pe_assemble_request()` 热路径用 `printf -v` 构建请求体 — 常见路径零 jq。Profile 字段直接从 `_PROF_*` 全局变量读取（消除每次 API 调用 8 个 subshell fork）。`_hook_fire()` 支持输出到文件模式避免 `$()` subshell。`_hook_job_context()` 将所有 job 文件批量合并为单次 `jq -s`。

**🖥️ 持久化渲染器** — 交互模式通过 `_persistent_renderer_init()` 一次性创建 FIFO + 渲染器，通过 fd 7 跨所有回合复用。消除每轮 `mkfifo` + fork + wait + `rm` 的开销。渲染器自驱动 spinner 动画（0.1s 定时器，`/dev/tty`），主进程不再负责动画。`done` 帧不再杀死渲染器 — 渲染器跨回合持续运行。

**🛡️ 管道韧性** — `trap '' PIPE` 防止 SIGPIPE 杀死 shell。`tool_start`/`tool_end` 的 `_stream_emit` 优雅处理 FIFO 断裂。`_in_dispatch` 通知输出重定向到 `/dev/tty` 绕过可能已断的 stdout。FIFO 拆除三级 fd 恢复链：`1>&9` → `1>&2` → `/dev/tty`。渲染器拆除增加 SIGTERM→SIGKILL 超时回退。

**🐛 Bug 修复** — `_json_unescape()` 使用 `printf -v _bs` 获取反斜杠（避免某些 shell 的 `\}` 解析风险）。`_in_buf_reposition()` 和 `_in_buf_redraw_line()` 在旧渲染存在自动换行时回退到全量重绘。`_in_buf_redraw()` 在 `\033[J` 前添加 `\r` 防止多行收缩后的光标漂移残留。

本次更新还包括：
- 系统提示词：在 §1 ROLE & IDENTITY 中新增 "Reasoning Effort: Absolute maximum" 深度推理指令
- 续行提示符 `⋯` → `⋯ `（末尾空格）
- `_stream_render`、`http_sse_connect`、`_stream_wrap_turn` 管道诊断 DEBUG 日志
- `_tm()` 延迟追踪通过 `BASHAGT_TIMING` 环境变量控制
- `SYS_JSON_CACHE`：系统提示词 JSON 缓存至 BASHAGT.md/skills 变更
- `_count_active_todos()`：30s TTL 缓存
- `load_bashagt_md` / `_reload_skills_if_stale`：每轮 stat 检查（移除节流以保证正确性）
- 测试修复：`test_ui_primitives.sh` SPINNER 数组初始化及 T3 断言；`test_protocol_assembly.sh` `_PE_DYN_MSG` 全局变量适配

### 2026-06-04 — 架构加固与 Bug 修复

**🏗️ 架构** — `init_system_dirs()` (831→21 行) 拆分为 `_init_settings_template()` 和 `_init_system_agents()`。新增 JSON 消息访问门面 — `msg_count()`、`msg_last_user_text()`、`msg_replace_all()` — 统一消息数组读写入口。`_cc_invalidate msgs` 集中到 `msg_add_*` 和 `msg_replace_all` 中，消除分散的缓存失效调用。`_turn_init()` 从 `run_turn()` 中提取为独立函数（48 行）。`_turn_flush_feedback()` 和 `_turn_flush_assistant()` 将 10 处分散的延迟读取收敛为 2 个专用刷新函数。`http_retry()` 指数退避 + 全抖动包装 S5 压缩 HTTP 调用。

**🐛 Bug 修复** — 关键：`_turn_flush_assistant`/`msg_add_tool_results` 调用顺序修复 — assistant(tool_use) 现在正确排在 user(tool_result) 之前，避免 API 400 "orphaned tool_result" 错误。`_compress_api()` L3 切分点现在感知配对完整性；自动调整 `old_count` 避免切割 tool_use/tool_result 对。PASTE_END 转义序列恢复：超时截断的粘贴括号用更长超时重试读取，防止 `_IN_PASTING` 粘滞状态和永久性界面冻结。`tool_edit_file()` 重复检测改用直接双匹配正则（单次 pass，无 BASH_REMATCH 捕获 bug）。`_trace_hash()` 恢复委托给 `_cc_hash`。修复 `run_turn()` pre_turn 钩子上下文中未绑定变量 `$trimmed`（缺少下划线前缀）。

**🎨 UX** — SSE `--spin-callback` + `_fmt_spin_tick` 轮询计时器恢复；格式化 HTTP 流式传输期间 spinner 保持实时计时。提前 spinner 帧插入恢复：spinner 在函数入口激活，覆盖 HTTP 请求前约 500ms 的计算间隙。

本次更新还包括：
- `_input_cleanup()` 与 daemon/MCP/history 生命周期解耦
- `P2-3`：移除硬编码 `MEM_NET_DIR`/`TODO_FILE` 回退路径
- 测试套件修复：`test_trace.sh`（Windows 路径）、`test_input_history.sh`（动态行号提取）、`test_paste_bugs.sh`（Bug B 验证）、`test_slash_handlers.sh`（消息门面 mock）

### 2026-06-03 — 性能优化与测试套件

**⚡ 性能优化** — 减少热路径中的 subshell 开销。`call_api_nonstreaming()`、`_call_agent_core()`、`agent_status()`、`build_agent_schema()`、`tool_list_agents()` 中多次连续的 `jq` 调用已合并为单次 `jq` 调用，通过 `IFS read` 批量提取。新增 `_prof_get_all()` 函数用一次 fork 替代 8 次 `_prof_get_field` 调用。`_pe_assemble_request()` 和 `build_request_body()` 去重了 `thinking` JSON 构建逻辑。

本次更新还包括：
- **SSE 旋转指示器** — 新增 `--spin-callback` 机制，在格式化 HTTP 轮询期间保持状态计时器活跃
- **编辑文件修复** — 修正 `tool_edit_file()` 中 `BASH_REMATCH` 反向引用注释
- **测试套件纳入仓库** — 30 个测试脚本（约 384 KB）已纳入版本控制；`.gitignore` 更新以包含 `test/`

### 2026-06-02 — 安全模式

**🛡️ 安全模式** — 为破坏性工具执行增加确认层。启用后（`/safe` 命令或 Shift+Tab 切换），`write_file`、`edit_file`、`delete_file`、`bash` 四种工具在执行前会弹出 TUI 确认框。被拒绝的工具返回 `{"status":"denied"}`，智能体会收到明确指令不得重试（§2.1）。特别适合生产环境或任何需要在 AI 触碰文件/执行命令前加入人类把关的场景。

本次更新还包括：
- **中断轮次统计** — 按 Esc/Ctrl-C 中断后现在会显示 token 用量和耗时
- **配置项重命名** — `diff_dark_mode` → `dark_mode`（更简洁，功能不变）
- **动态请求菜单高度** — Human Oversight 对话框改用实际渲染行数而非静态估算，修复回滚残留问题
- **换行符清理** — 请求上下文文本自动剥离换行符，单行干净渲染

---

## 📄 许可证

本项目基于 **Apache License 2.0** 开源。详见 [LICENSE](./LICENSE) 文件。

简而言之：你可以自由使用、修改、分发本项目代码，包括用于商业目的，但需保留原始版权声明和许可证文本。

---

## 🙏 致谢

- [Anthropic](https://www.anthropic.com/) — Messages API 协议
- [DeepSeek](https://www.deepseek.com/) — 默认模型后端
- [jq](https://jqlang.github.io/jq/) — 命令行 JSON 处理器
- [Termux](https://termux.dev/) — Android 终端环境
- [iSH](https://ish.app/) — iOS 上的 Linux Shell

---

Bashagt 证明了一件事：AI 编程助手的门槛，不需要是 Node，不需要是 Python，不需要 GPU，甚至不需要容器。它可以是每一台 Linux 机器开机就在那里的那个 `/bin/bash`。从这个起点出发，服务器、树莓派、手机、路由器——都成了潜在的 AI 节点。

或许以后每台 Linux/Unix 终端上都会运行着 Bashagt，让 Agent 无处不在。