# Bashagt — Agents Everywhere

**English** | [中文](./README_zh.md)

> A **pure-bash** LLM agent kernel — zero runtime dependencies, runs anywhere bash does.

[![Bash](https://img.shields.io/badge/bash-4.0%2B-green?logo=gnubash)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20WSL%20%7C%20Termux%20%7C%20iSH-blue)]()
[![Lines](https://img.shields.io/badge/lines-15,725-orange)]()
[![Functions](https://img.shields.io/badge/functions-431-purple)]()
[![License](https://img.shields.io/badge/license-Apache%202.0-blue)](./LICENSE)
[![Status](https://img.shields.io/badge/status-preview-yellow)]()

---

## 🤔 Why Bashagt?

Have you ever had this experience—

2 AM. A production server alarm goes off. You SSH in, staring at a tangled web of nested call chains and hundreds of thousands of log lines. Your fingers hover over the keyboard. A single thought fills your mind: **"If only Claude were here."**

But it's not.

Claude Code, Codex, Cursor… these AI coding assistants have genuinely changed how we write software. But they share a common, rarely-discussed weakness: **they can't leave their greenhouse.**

---

### 🏭 AI in a Greenhouse

Modern coding agents almost universally depend on Node.js or Python runtimes. On your dev machine, this is a non-issue — `brew install`, `pip install`, environment ready, AI in position.

But step outside your dev machine, and things get interesting:

**Scenario A: The production server in the internal network**

No internet. No random package installations. The artifact repository has Python 2.7 from eight years ago. Node? Never been seen on these premises. The ops lead walks by, glances at your screen — the look says "don't mess with it."

You want to install Claude Code on this machine? Never mind whether you *can* — would you *dare* let it run? A closed-source AI, executing commands, reading and writing files, on a box holding real user data. How fast would your heart be beating?

**Scenario B: The flash of insight on the commute home**

You're on the subway, and a perfect architectural refactoring idea hits you. You pull out your phone, hoping to bounce it off an AI, to have it help you think it through—

Then it dawns on you. Your phone has no Claude Code. No Codex. No AI companion that can read code, write code, reason with you. Your laptop is in your bag, but on this sardine-packed train you don't even have room to open it.

---

### 🧱 The Root Cause

Two different scenarios, one shared root:

> **Existing AI coding tools are locked into the "developer workstation + modern software stack" combination.**

Node and Python are the air they breathe. Once they leave that ecosystem — whether into an internal server room or onto a phone — they suffocate.

And yet: **there are far more machines running Linux in the world than there are developer desks.**

Routers run Linux. Smart TVs run Linux. That Raspberry Pi you bought ten years ago, eating dust in a corner — it runs Linux. Thousands upon thousands of production servers, edge devices, embedded boards… they all share one thing: **nothing but bash.**

bash is the common denominator of the Unix world. It doesn't care about hardware. It doesn't care about distro. It doesn't care about kernel version. Linux has it. macOS has it. Windows has it through WSL. Even your Android phone has it through Termux, your iPhone through iSH.

**So why isn't there an AI agent that runs directly on bash?**

---

### ✨ Enter Bashagt

Bashagt is the answer.

It is a **15,725-line pure bash script**. No Node. No Python. No pip. No npm. No runtime dependency you've ever heard of.

Its entire arsenal consists of three things — three things that are everywhere on any Unix-like system:

```
bash 4.0+   +   jq   +   curl
```

Those aren't three "dependencies." Those are three **standard fixtures.**

Which means: **anywhere bash runs, Bashagt runs.**

| Where you are | How Bashagt runs |
|--------------|------------------|
| 🖥️ Dev machine | Interactive conversation, daily Claude Code replacement |
| 🏭 Internal server | SSH in and go — inspect logs, analyze configs |
| 📱 Android phone | Via Termux, with camera/SMS/GPS access |
| 🍎 iPhone/iPad | Via iSH — brainstorm an architecture refactor on the train |
| 🪟 Windows | Seamless via WSL, full Windows filesystem access |
| 🥧 Raspberry Pi | Plug it in and run — your home AI terminal |
| 🌐 Router / embedded | In theory, if it can run bash 4.0+… |

---

### 🔮 Vision

We believe AI coding assistants shouldn't be locked inside the "developer workstation" bubble.

They should follow you into the server room, ride in your pocket during the commute, sit on a Raspberry Pi managing your NAS, sleep inside a router monitoring your home network.

Bashagt is just a seed. But the direction it points is simple:

> **Every machine that runs bash deserves an AI agent.**

Maybe when this vision becomes reality, people will look back at "you need Node and Python to use an AI coding assistant" the same way we now look at "you need a phone line to use the internet" — with mild disbelief that anyone ever accepted it.

---

*Of course, this is a preview. Many features are still in development, and bugs are plenty. Issues and PRs welcome.*

*If you're interested in the Bashagt project, join the QQ discussion group: 198302483 (answer: State).*

---

## ✨ Features

- 🐚 **Pure Bash** — 15,725 lines, 431 functions, zero Node/Python runtime dependencies
- 🖥️ **Cross-Platform** — Linux (GNU), macOS (BSD), WSL, Termux (Android), iSH (iPhone/iPad)
- 🔧 **24 Built-in Tools** — file read/write/edit/delete, command execution, web search, sub-agent delegation, TODO management, skill system…
- 🤖 **Sub-Agent System** — 11 system agents (plan/explore/review/summarize…) + customizable project agents
- 🧠 **Distributed Memory Network** — 16 engrams × 200 slots = 3,200 persistent memories with semantic search
- 🌐 **HTTP Daemon** — REST API + SSE streaming; deploy as a backend service
- 🔌 **MCP Protocol Support** — Model Context Protocol (stdio/sse/http transports), connect to external tool ecosystems
- 🪝 **Hook Plugin System** — 8 hook points × 6 handler types for deep customization
- 📦 **4-Tier Context Compression** — automatic management of conversations exceeding 250KB
- ↩️ **Trace/Undo** — content-addressed file modification tracking with rollback
- 🔄 **Adaptive Agent Loop** — three safeguard mechanisms against infinite loops
- ⌨️ **Full Readline** — Unicode/CJK support, multi-line editing, history search, Tab completion
- 📱 **Termux-API Integration** — control Android sensors, camera, SMS, and more from your phone
- 🔄 **Self-Evolution** — Bashagt can read and modify its own source code. Add features through conversation: "add a --version flag" — it reads, edits, verifies, done

---

## 🚀 Quick Start

### Core Dependencies

Bashagt has only three dependencies — installable with a single package manager command on any mainstream platform:

| Dependency | Minimum | Purpose |
|-----------|---------|---------|
| **bash** | 4.0+ | Script runtime. Built into virtually all modern systems. |
| **jq** | Any | JSON processing for API communication and config file handling. |
| **curl** | Any | HTTP client for communicating with LLM API endpoints. |

Additionally, **Termux (Android)** requires the `coreutils` package (for `realpath`/`nl` and other GNU tools). See platform-specific instructions below.

---

### Installation: Platform Guides

Installation is uniform across all platforms — three steps:

```
1. Get the script   →   2. Install dependencies   →   3. ./bashagt --install
```

`--install` automatically: creates the `~/.bashagt/` directory tree, generates a default config file, registers bash/zsh hotkeys, and adds `bashagt` to your PATH.

---

#### 🐧 Linux / Unix (General)

Applies to all mainstream Linux distributions (Debian/Ubuntu, RHEL/CentOS, Arch, Alpine, openSUSE, etc.) and traditional Unix.

**Step 1: Install dependencies**

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

> Most Linux distributions ship bash ≥4.0. Verify: `bash --version`

**Step 2: Get Bashagt**

```bash
git clone https://github.com/zhihumomo/bashagt.git
cd bashagt
```

**Step 3: One-click install**

```bash
./bashagt --install
```

This command:
- Copies `bashagt` to `~/.bashagt/`
- Creates a `~/.local/bin/bashagt` symlink (ensure `~/.local/bin` is in your PATH)
- Generates `~/.bashagt/settings.json`
- Registers hotkeys: `Ctrl+G` (bash) or `Ctrl+T` (zsh) for quick access

Afterwards, type `bashagt` from any directory to launch.

---

#### 🍎 macOS

**Step 1: Install dependencies**

macOS ships with bash 3.2 (too old). Install a newer version via Homebrew:

```bash
# Install Homebrew (if not already installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install dependencies
brew install bash jq curl
```

Homebrew-installed bash lives at `/opt/homebrew/bin/bash` (Apple Silicon) or `/usr/local/bin/bash` (Intel). Bashagt uses `#!/usr/bin/env bash`, so as long as the Homebrew path appears before `/bin` in `/etc/paths`, the new version will be used automatically.

```bash
# Verify version (should show 5.x)
bash --version
```

> 💡 **macOS hotkeys**: `--install` auto-detects your terminal app (Terminal.app / iTerm2 / Warp) and binds `Cmd+G` or `Cmd+T` in its preferences. For iTerm2, you may need to manually verify the mapping in Preferences → Keys.

**Steps 2 & 3: Same as Linux**

```bash
git clone https://github.com/zhihumomo/bashagt.git
cd bashagt
./bashagt --install
```

---

#### 🪟 Windows (via WSL)

Bashagt runs on Windows through WSL (Windows Subsystem for Linux).

**Step 1: Install WSL (if not already installed)**

Run in PowerShell or CMD (as Administrator):

```powershell
wsl --install
```

This installs Ubuntu by default. Reboot, enter the WSL terminal, and follow the Linux guide.

**Step 2: Install dependencies**

```bash
sudo apt update
sudo apt install jq curl
```

**Steps 3 & 4: Same as Linux**

```bash
git clone https://github.com/zhihumomo/bashagt.git
cd bashagt
./bashagt --install
```

> 💡 In WSL, `bashagt` can directly access the Windows filesystem (`/mnt/c/`, `/mnt/d/`, etc.) and work with Windows project files.

---

#### 📱 Android (via Termux)

Termux is a terminal emulator and Linux environment for Android — no root required. Bashagt fully supports Termux, including Android system API integration.

**Step 1: Install Termux**

Install Termux from [F-Droid](https://f-droid.org/packages/com.termux/) (recommended — up to date; the Google Play version is no longer maintained).

**Step 2: Install dependencies**

```bash
pkg update && pkg upgrade

# Install core dependencies
pkg install bash jq curl git coreutils

# Verify bash version (Termux installs bash 5.x by default)
bash --version
```

| Extra package | Purpose |
|--------------|---------|
| `coreutils` | Provides `realpath`, `nl`, and other GNU tools that Bashagt depends on. **Required.** |
| `termux-api` | Android API bridge (optional). Enables Bashagt to control phone hardware via Termux-API tools — see "Termux-API Integration" below. |

**Step 3: Install Bashagt**

```bash
git clone https://github.com/zhihumomo/bashagt.git
cd bashagt
./bashagt --install
```

> **Storage access**: Termux can only access the shared internal storage directory `~/storage/shared/` by default. To access external SD cards or other locations, run `termux-setup-storage` to grant storage permissions.

---

##### 🔧 Mounting External Storage

To work with external SD cards or USB storage devices in Termux:

```bash
# Request storage permission (one-time)
termux-setup-storage

# Afterwards, symlinks become available
ls ~/storage/
#   dcim/       → camera photos
#   downloads/  → download directory
#   external-1/ → external SD card (if present)
#   music/      → music
#   shared/     → internal shared storage
```

To use Bashagt on a project stored on external storage, simply switch to the path:

```bash
cd ~/storage/external-1/my-project
bashagt
```

For OTG-connected USB devices, mounting in Termux requires the `termux-usb` tool (see Termux-API below).

---

##### 📲 Controlling Your Phone with Termux-API

With `termux-api` installed, Bashagt can directly invoke Android system APIs for intelligent phone control.

**Installing Termux-API**

1. Install the [Termux:API](https://f-droid.org/packages/com.termux.api/) companion app from F-Droid
2. Install the command-line tools in Termux:

```bash
pkg install termux-api
```

**Available Capabilities**

Once installed, the following `termux-*` commands are immediately available. Bashagt auto-detects these tools in the Termux environment — just ask in conversation:

| Capability | Command | Example |
|-----------|---------|---------|
| 📷 **Camera** | `termux-camera-photo` | "Take a photo and extract any text from it" |
| 📍 **Location** | `termux-location` | "Get my GPS coordinates and find nearby restaurants" |
| 📱 **SMS** | `termux-sms-send` | "Text the boss: meeting moved to 3pm" |
| 📞 **Phone** | `termux-telephony-call` | "Call customer support" |
| 🔊 **Volume** | `termux-volume` | "Set media volume to 50%" |
| 🔔 **Notifications** | `termux-notification` | "Remind me to drink water in 10 minutes" |
| 💡 **Flashlight** | `termux-torch` | "Turn on the flashlight for 10 seconds" |
| 🔋 **Battery** | `termux-battery-status` | "Check battery — alert me if below 20%" |
| 📋 **Clipboard** | `termux-clipboard-get/set` | "Read the clipboard and translate to English" |
| 🎤 **Microphone** | `termux-microphone-record` | "Record 30 seconds and transcribe it" |
| 🎵 **Media** | `termux-media-player` | "Play music from the Downloads folder" |
| 🔄 **Sensors** | `termux-sensor` | "Read the accelerometer — detect if the phone is moving" |
| 💻 **USB** | `termux-usb` | "Detect OTG-connected USB devices" |

> ⚠️ These features require granting Termux the relevant Android permissions (storage, camera, location, SMS, phone, etc.). The system will automatically prompt for permission on first use.

---

#### 📱 iPhone / iPad (via iSH)

iSH is an Alpine Linux emulator for iOS, giving your iPhone/iPad a real Linux terminal.

**Step 1: Install iSH**

Install iSH from the [App Store](https://apps.apple.com/app/ish-shell/id1436902243).

**Step 2: Install dependencies**

Open the terminal in iSH:

```bash
# Update package index (iSH uses the Alpine package manager)
apk update
apk add bash jq curl git coreutils

# Verify bash version
bash --version
```

**Step 3: Install Bashagt**

```bash
git clone https://github.com/zhihumomo/bashagt.git
cd bashagt
./bashagt --install
```

> ⚠️ **iSH limitations**:
> - iSH is an x86 emulation layer; performance is limited by iOS JIT restrictions. LLM API calls go over the network at normal speed, but local bash computation will be slower than native
> - Background daemon mode (`--run`) is not supported, but interactive and oneshot modes work perfectly
> - UTF-8/CJK character rendering is fully functional — Chinese conversations work

---

### Configure API Key

After installation, edit `~/.bashagt/settings.json` with your API details:

```json
{
  "api_url": "https://api.deepseek.com/anthropic",
  "api_key": "sk-your-api-key-here",
  "model": "deepseek-chat",
  "max_tokens": 8192,
  "thinking_budget": 16384
}
```

> **Compatible backends**: Bashagt uses the Anthropic Messages API protocol. The default points to DeepSeek. You can also switch to:
> - **Anthropic official**: `"api_url": "https://api.anthropic.com"`, `"model": "claude-sonnet-4-20250514"`
> - **Other OpenAI-compatible endpoints**: such as Ollama, vLLM, LiteLLM, or other locally-deployed models

**Recommended — secure approach**: Use environment variables instead of storing the API key in a config file:

```bash
export BASHAGT_API_KEY="sk-your-api-key-here"
```

Environment variables take priority over config files (4-tier config: defaults → settings.json → project settings.json → environment variables).

---

### Launch

Once installed and configured, just type `bashagt`:

```bash
# Interactive conversation mode (default)
bashagt

# Oneshot mode — pipe input, output result, exit
echo "Explain this code" | bashagt --oneshot

# Streaming oneshot mode — pure JSONL output, ideal for script parsing
echo "Analyze this log" | bashagt --oneshot --stream

# Start HTTP daemon (default port 9655)
bashagt --run

# Foreground debug mode (daemon + logs to terminal)
bashagt --run --debug --port 9655

# Update to the latest version
./bashagt --update
```

See [Usage Examples](#-usage-examples) below for details on each mode.

---

## 📋 Use Cases

---

### 🛠️ Daily Development

You're refactoring a legacy module with call chains too deep for your IDE to trace. Open a terminal and let Bashagt handle it —

```bash
$ bashagt
bashagt> Where does PaymentService.process() get called in this project?
bashagt> Map out the dependency graph of everything under src/auth/
bashagt> Add Chinese comments to every endpoint in UserController
```

No window switching. No plugin installation. Right there in the terminal — it reads your code and answers directly.

---

### 🔄 CI/CD Code Review

Tired of manually reviewing every PR? Wire it into your CI pipeline:

```bash
# Review the most recent commit
git diff HEAD~1 | bashagt --oneshot

# Review the diff between two branches
git diff main...feature-branch | bashagt --oneshot

# Combine with lint output
eslint src/ --format json | bashagt --oneshot
```

Oneshot mode outputs results and exits — no persistent process, CI-friendly.

---

### 🏭 Production Troubleshooting

A sudden 502 in production. You SSH in, facing gigabytes of logs and config files changed who-knows-when:

```bash
$ ssh production-server
$ cd /var/log/app
$ bashagt

bashagt> What are the top 5 errors in the nginx error log from the last hour?
bashagt> Check /etc/nginx/nginx.conf for anything that could cause a 502
bashagt> Compare the three configs under /etc/nginx/sites-enabled/ — find the inconsistencies
```

No special tools needed — the server already has bash. The entire investigation happens in one terminal session.

---

### 🌐 As a Backend API Service

You want to embed LLM conversation capabilities in your app, without pulling in a massive Python/Node dependency chain:

```bash
# Start the daemon
bashagt --run --port 9655

# Call from your app (any language — if it can HTTP, it can call)
curl -X POST http://localhost:9655/v1/session/new          # Create session
curl -X POST http://localhost:9655/v1/session/{id} \        # Send message
  -d '{"message": "Parse this JSON and generate TypeScript types"}'
curl -N http://localhost:9655/v1/session/{id}/stream         # SSE streaming response
```

A 15K-line bash script is your LLM gateway.

---

### 📱 Mobile Coding Assistant (Termux)

Quickly verify an idea on the train, or patch some code on the fly:

```bash
$ bashagt
bashagt> Write an awk one-liner to count requests per IP from access.log, sorted descending
bashagt> My Android project is at ~/storage/shared/MyApp — find all deprecated API usage
```

With Termux-API, Bashagt can even control your phone:

```bash
bashagt> Take a photo and extract any text you find
bashagt> Text "Boss" in my contacts: "Received, working on it"
bashagt> Get my GPS coordinates and tell me the nearest subway station
```

---

### 🍎 iPhone/iPad Terminal Companion (iSH)

iPad with an external keyboard, no laptop — iSH is your lightweight Linux environment:

```bash
$ bashagt
bashagt> Check this Python code for potential memory leaks
bashagt> Explain what this regex matches: (?<=@)\w+(?=\.)
bashagt> Convert this JSON to YAML
```

Both interactive and oneshot modes work. API calls go over the network — response speed matches desktop.

---

### 🔒 Air-Gapped / Offline Environments

The most extreme scenario: a machine physically isolated from the internet, but with an internal LLM API available (e.g., Ollama or vLLM):

```bash
# Configure the internal API endpoint
export BASHAGT_API_URL="http://192.168.1.100:11434/api/chat"
export BASHAGT_API_KEY="ollama"

# Use as normal
bashagt
```

No Node. No Python. **bash + jq + curl** — any serious Linux distribution ships with them or installs them in a single command.

---

## 🔧 Usage Examples

### Interactive Conversation

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

  > /help          # View built-in slash commands
  > Analyze the performance bottleneck in this code
  > Find all callers of login()
  > Write unit tests for this module
```

### Pipe Mode

```bash
# Code review
git diff HEAD~1 | bashagt --oneshot

# Log analysis
tail -100 /var/log/app.log | bashagt --oneshot

# Config generation
cat schema.json | bashagt --oneshot --stream
```

### Daemon API

```bash
# Start the service
bashagt --run --port 9655

# Create a session
curl -X POST http://localhost:9655/v1/session/new

# Send a message
curl -X POST http://localhost:9655/v1/session/{id} \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello"}'

# SSE streaming subscription
curl -N http://localhost:9655/v1/session/{id}/stream
```

---

## 🔄 Self-Evolution: Let Bashagt Write Its Own Features

This may be Bashagt's most distinctive capability — because it is itself a plain-text bash script, and it has tools to read, edit, and execute files, **Bashagt can modify its own source code.**

You say a sentence. It adds a feature.

---

### How Does It Work?

The process is exactly the same as when it modifies your project code:

```
You say: "Add a --version flag"
         ↓
Bashagt: Reads its own main() function to understand argument parsing
         ↓
Bashagt: Uses the edit_file tool to insert a --version branch at the right spot
         ↓
Bashagt: Runs ./bashagt --version with the bash tool to verify
         ↓
Bashagt: Confirms success, reports done ✅
```

No editor. No knowing which line to change. No testing. The entire process flows in conversation.

---

### Live Demo

Say you want Bashagt to show token usage stats for the current session. You just say:

```
bashagt> Add a /stats slash command that shows token usage and API call count for this session
```

Bashagt will navigate its own source to find where slash commands are registered (`_slash_dispatch`), locate the statistics variables (`TURN_TOKENS_IN`, `TURN_TOKENS_OUT`…), and insert the new command implementation. It'll even run `bash -n` for a syntax check when done.

---

### What This Means

Bashagt's development model is no longer "write code, submit PR, wait for merge, wait for release." Instead—

> **In your own terminal, through conversation, customize your own Bashagt anytime.**

Want a new CLI flag? Say it. Want to add validation logic to a tool? Say it. Want a custom banner on startup? Say it. These changes live in your local Bashagt copy — no waiting on upstream, no forking repos.

Of course, not every change suits this approach — major architectural refactors still deserve proper development and testing. But for the countless "could it do this small thing?" moments, self-evolution makes every Bashagt user a co-author.

---

## ⚙️ Configuration

Bashagt uses a 4-tier configuration priority (later overrides earlier):

```
Defaults  →  ~/.bashagt/settings.json  →  Project .bashagt/settings.json  →  Environment variables
```

| Setting | Env Variable | Default | Description |
|---------|-------------|---------|-------------|
| `api_url` | `BASHAGT_API_URL` | DeepSeek Anthropic endpoint | API address |
| `api_key` | `BASHAGT_API_KEY` | — | API key |
| `model` | `BASHAGT_MODEL` | `deepseek-chat` | Model name |
| `max_tokens` | `BASHAGT_MAX_TOKENS` | 8192 | Max output tokens |
| `thinking_budget` | `BASHAGT_THINKING_BUDGET` | 16384 | Thinking budget |
| `proxy_url` | `BASHAGT_PROXY_URL` | — | Proxy URL (http/socks4/socks5) |
| `context_window` | `BASHAGT_CONTEXT_WINDOW` | 128000 | Context window size |

---

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│                    main()                            │
│         (CLI parsing → init → mode dispatch)          │
├─────────────────────────────────────────────────────┤
│  • --install       Initialize system directories      │
│  • --run           Start HTTP daemon                  │
│  • --oneshot       Single-shot pipe mode              │
│  • (default)       Interactive REPL                   │
└────────────────────┬────────────────────────────────┘
                     │
     ┌───────────────▼──────────────────────┐
     │          agent_loop()                 │
     │  Interactive REPL or oneshot entry     │
     └───────────────┬──────────────────────┘
                     │
     ┌───────────────▼──────────────────────┐
     │          run_turn()                   │
     │  User input → API call → response     │
     │         ↓  stop_reason?                │
     │  end_turn ← return to user             │
     │  tool_use → dispatch_tool → loop       │
     └───────────────┬──────────────────────┘
                     │
     ┌───────────────▼──────────────────────┐
     │       dispatch_tool()                  │
     │  24 tools: read_file, write_file,      │
     │  edit_file, bash, agent, web_search,   │
     │  make_todos, skill, request...         │
     └──────────────────────────────────────┘

━━━━━━━━━━━━ Subsystems ━━━━━━━━━━━━

  Memory Network      Sub-Agent System       Hook System
  ┌──────────┐       ┌────────────┐       ┌──────────┐
  │16 engrams│       │11 sys agents│       │ 8 points  │
  │×200 slots│       │ N proj agents│      │ 6 types   │
  │sem search │       │ parallel    │       │ lifecycle │
  │sleep compr│       │ async sched │       │ hot-reload│
  └──────────┘       └────────────┘       └──────────┘
```

### Core Subsystems

| Subsystem | Section | Purpose |
|-----------|---------|---------|
| Tool System | §8–§10 | 24 tool definitions, implementations, dispatch |
| Agent System | §7 | Sub-agent loading, invocation, communication |
| Memory Network | §7c | 16 engram distributed memory, semantic search, sleep compression |
| Context Compression | §5 | 4-tier compression (>250KB threshold) |
| HTTP/SSE | §6a | curl wrapper, SSE stream parsing |
| Daemon | §11d | HTTP server, worker pool, cron scheduler |
| MCP Client | §11c | stdio/sse/http transports, dynamic external tool registration |
| Input Layer | §2b–§2c | Custom Readline, Unicode/CJK support |
| Trace/Undo | §7f | Content-addressed file tracking, frame rollback |
| Adaptive Loop | §11b | Three safeguards (token/time/turn) |
| Hook System | §2 | 8 points × 6 types extensible architecture |

---

## 🤝 Contributing

The project is currently in **preview** — features are iterating rapidly and bugs exist. Welcome:

- 🐛 Submit [Issues](https://github.com/zhihumomo/bashagt/issues) to report bugs
- 💡 Propose feature requests
- 🔀 Submit Pull Requests
- 📖 Improve documentation

Developer reference: see [`CLAUDE.md`](./CLAUDE.md) for the complete developer documentation.

The repository includes a comprehensive test suite (30 test scripts, ~384 KB) covering all major subsystems — tools, hooks, trace, compression, input, UI, SSE, skills, and end-to-end scenarios. No API key is needed for unit tests.

Run tests:

```bash
cd test
./run_all.sh                # unit + integrity tests (no API needed)
./run_all.sh --all          # full suite including E2E (requires API key)
```

---

## 📝 Changelog

### 2026-06-04 — Architecture Hardening & Bug Fixes

**🏗️ Architecture** — `init_system_dirs()` (831→21 lines) decomposed into `_init_settings_template()` and `_init_system_agents()`. New JSON message access facade — `msg_count()`, `msg_last_user_text()`, `msg_replace_all()` — single source of truth for message array reads/writes. `_cc_invalidate msgs` centralized into `msg_add_*` and `msg_replace_all`, eliminating scattered cache invalidation. `_turn_init()` extracted from `run_turn()` (48 lines → standalone function). `_turn_flush_feedback()` and `_turn_flush_assistant()` converge 10 deferred-read sites into 2 dedicated flush functions. `http_retry()` with exponential backoff + full jitter wraps S5 compression HTTP calls.

**🐛 Bug Fixes** — Critical: `_turn_flush_assistant`/`msg_add_tool_results` ordering restored — assistant(tool_use) now correctly precedes user(tool_result) in message array, preventing API 400 "orphaned tool_result" errors. `_compress_api()` L3 split-point now pair-aware; adjusts `old_count` to avoid breaking tool_use/tool_result pairs. PASTE_END escape sequence recovery: timeout-truncated paste brackets retry with longer timeout, preventing `_IN_PASTING` sticky-state and permanent redraw suppression. `tool_edit_file()` duplicate detection uses direct double-match regex (single-pass, no BASH_REMATCH capture bug). `_trace_hash()` restored to `_cc_hash` delegation. Unbound variable `$trimmed` (missing underscore prefix) fixed in `run_turn()` pre_turn hook context.

**🎨 UX** — SSE `--spin-callback` + `_fmt_spin_tick` polling timer restored; spinner keeps live elapsed counter during format HTTP streaming. Early spinner frame insertion restored: spinner activates at function entry to cover ~500ms computation gap before HTTP request.

Also in this update:
- `_input_cleanup()` decoupled from daemon/MCP/history lifecycle
- `P2-3`: hardcoded `MEM_NET_DIR`/`TODO_FILE` fallback paths removed
- Test suite fixes: `test_trace.sh` (Windows paths), `test_input_history.sh` (dynamic line extraction), `test_paste_bugs.sh` (Bug B verification), `test_slash_handlers.sh` (msg facade mocks)

### 2026-06-03 — Performance & Test Suite

**⚡ Performance Optimization** — reduced subshell overhead across the hot path. Multiple sequential `jq` calls in `call_api_nonstreaming()`, `_call_agent_core()`, `agent_status()`, `build_agent_schema()`, and `tool_list_agents()` have been consolidated into single `jq` invocations with batch extraction via `IFS read`. New `_prof_get_all()` function replaces 8 `_prof_get_field` calls with a single fork. `_pe_assemble_request()` and `build_request_body()` deduplicated `thinking` JSON construction.

Also in this update:
- **SSE spinner tick** — new `--spin-callback` mechanism keeps the status timer alive during format HTTP polling
- **Edit file fix** — corrected `BASH_REMATCH` backreference comment in `tool_edit_file()` multi-occurrence check
- **Test suite in repository** — 30 test scripts (~384 KB) now tracked in version control; `.gitignore` updated to include `test/`

### 2026-06-02 — Safe Mode

**🛡️ Safe Mode** — a confirmation layer for destructive tool execution. When enabled (`/safe` or Shift+Tab), `write_file`, `edit_file`, `delete_file`, and `bash` are intercepted with an inline TUI confirmation dialog before execution. Denied tools return `{"status":"denied"}` that the agent is explicitly instructed not to retry (§2.1). Ideal for production servers or any scenario where you want a human-in-the-loop guardrail before the AI touches files or runs commands.

Also in this update:
- **Interrupted turn stats** — pressing Esc/Ctrl-C now displays token usage and elapsed time before the "interrupted" message
- **Config rename** — `diff_dark_mode` → `dark_mode` (simpler, same function)
- **Dynamic request menu height** — the Human Oversight dialog now uses actual rendered line count instead of a static estimate, fixing scroll-back artifacts
- **Newline sanitization** — request context text strips newlines for clean single-line rendering

---

## 📄 License

Licensed under **Apache License 2.0**. See [LICENSE](./LICENSE) for the full text.

In short: you are free to use, modify, and distribute this code, including for commercial purposes, provided you retain the original copyright notice and license text.

---

## 🙏 Acknowledgments

- [Anthropic](https://www.anthropic.com/) — Messages API protocol
- [DeepSeek](https://www.deepseek.com/) — Default model backend
- [jq](https://jqlang.github.io/jq/) — Command-line JSON processor
- [Termux](https://termux.dev/) — Android terminal environment
- [iSH](https://ish.app/) — Linux shell on iOS

---

Bashagt proves one thing: the barrier to entry for AI coding assistants doesn't need to be Node, or Python, or a GPU, or even a container. It can be that `/bin/bash` that sits there waiting on every Linux machine since boot. From that starting point, servers, Raspberry Pis, phones, routers — all become potential AI nodes.

Maybe someday every Linux/Unix terminal will be running Bashagt, bringing agents everywhere.