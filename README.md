# ClawManager

A native macOS app for monitoring and interacting with Claude Code CLI sessions.

## Overview

ClawManager watches `~/.claude/projects/` for active Claude Code sessions and provides a real-time GUI to monitor conversations, view streaming output, and interact with running sessions.

## Features

- **Session Discovery** — Automatically detects Claude Code sessions from JSONL project files
- **Live Streaming** — Displays Claude's responses in real-time via NDJSON event parsing
- **Interactive Mode** — Send messages to active Claude Code sessions directly from the app
- **Native macOS** — Built with pure SwiftUI, no external dependencies

## Requirements

- macOS 15+
- Swift 6.1
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed

## Building

```bash
swift build
```

## Running

```bash
swift run ClawManager
```

Or open in Xcode and run the `ClawManager` target.

## Architecture

- **Models** — Session, Message, and InteractiveState data types
- **Services** — Session discovery and interactive CLI communication (Swift actors)
- **Stores** — Observable state management with `SessionStore` and `UIState`
- **Views** — SwiftUI views organized by feature (Detail, Sidebar, etc.)
- **Theme** — Design system tokens via `DS.*` namespace
