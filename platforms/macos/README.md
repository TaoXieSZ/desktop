[English](#english) | [简体中文](#简体中文)

---

# English

## macOS Platform

This directory contains macOS-related source code for the official AhaKey desktop baseline.

The goal of this platform directory is to keep macOS implementation clearly separated from Windows, since the two platforms use different runtime stacks, UI models, and system capabilities.

### Why macOS is separated

The macOS client is not a small variant of the Windows client. It involves:

- Swift, SwiftUI, and Apple-native frameworks
- macOS-specific UI patterns and window models
- Apple system integration (CoreBluetooth, Apple Speech, LaunchAgents)
- a native voice agent stack written in Swift, with its own LLM and tool-calling layer
- platform-specific workflow design (push-to-talk relay routes for IDEs / chat apps, OLED art, LED state sync)

So macOS source lives under `platforms/macos/`, not mixed into `platforms/windows/`.

### What this directory contains

- the official macOS client source under `platforms/macos/client/`
- macOS-specific platform logic
- build instructions and packaging scripts
- platform documentation

### Current status

The macOS client has moved past the post-migration cleanup phase and is in **active feature development** as of `v0.1.1-alpha`.

Recent additions (see top-level `CHANGELOG.md` for the full list):

- **Voice Agent** — supervisor + sub-agent orchestrator, structured tool-calling, per-agent memory, OpenAI-compatible LLM client, persistent sessions.
- **Feishu / Lark integration** — message sending and contact lookup via `lark-cli` under the user's own identity, with a local contact alias book.
- **Dual workspace** — root toggle between *IDE 工作台* (classic keyboard config) and *Agent 工作台* (voice agent), unified design system, single onboarding flow.
- **Voice input HUD** — floating push-to-talk overlay backed by Apple Speech, with relay routes for IDEs / WeChat / etc.
- **Build pipeline updates** — refreshed `build.sh` / `build-debug.sh`, new packaging and signing helpers.

For the source map, build instructions, and BLE protocol docs, see `platforms/macos/client/README.md`.

### Notes

- Release binaries (`.dmg`, signed `.app`) are not stored in source directories
- Packaged macOS builds are distributed through GitHub Releases only
- macOS source is kept separate from Windows code and is not mixed into `platforms/windows/`

---

# 简体中文

## macOS 平台目录

这个目录用于存放 AhaKey 官方桌面客户端基线中的 macOS 相关源码。

之所以单独拆出这个平台目录，是因为 macOS 和 Windows 在运行时栈、UI 模型以及系统能力上都有明显不同，需要分别组织。

### 为什么 macOS 要单独拆开

macOS 客户端并不是 Windows 客户端的一个小变体。它涉及：

- Swift / SwiftUI 与 Apple 原生框架
- macOS 特有的 UI 与窗口模型
- Apple 系统级集成（CoreBluetooth、Apple Speech、LaunchAgent）
- 用 Swift 实现的原生 voice agent，带独立的 LLM 与工具调用层
- 平台特有的工作流设计（IDE / 聊天软件的按住说话中继、OLED 图形、LED 状态同步）

所以 macOS 源码会放在 `platforms/macos/` 下，而不是和 Windows 混在一起。

### 这个目录包含什么

- 官方 macOS 客户端源码（位于 `platforms/macos/client/`）
- macOS 平台相关逻辑
- 构建与打包脚本
- 平台文档

### 当前状态

macOS 客户端已走过迁入后整理阶段，自 `v0.1.1-alpha` 起进入**活跃功能开发期**。

近期新增能力（完整列表见仓库根目录的 `CHANGELOG.md`）：

- **Voice Agent** — supervisor + sub-agent 编排、结构化工具调用、独立记忆、OpenAI 协议兼容 LLM 客户端、跨次启动会话保留。
- **飞书 / Lark 集成** — 通过 `lark-cli` 以用户自己的身份发消息和查联系人，本地维护联系人别名表。
- **双工作台** — 根工作台支持 *IDE 工作台*（经典键位配置）和 *Agent 工作台*（语音助手）切换，共用设计系统与统一引导流程。
- **语音输入 HUD** — 基于 Apple Speech 的浮动按住说话面板，针对 IDE / 微信等做了中继路由。
- **构建链路更新** — 调整 `build.sh` / `build-debug.sh`，新增打包与签名辅助脚本。

源码索引、构建说明与 BLE 协议文档见 `platforms/macos/client/README.md`。

### 说明

- 发布二进制（`.dmg`、签名 `.app`）不存放在源码目录
- macOS 安装包统一通过 GitHub Releases 分发
- macOS 源码不会混入 `platforms/windows/`
