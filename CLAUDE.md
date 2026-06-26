# CLAUDE.md — AI Monitor

Project-specific guidance for working in this repo. This is a **personal** project
(separate from any work repo); the conventions below override generic/work defaults.

## What this is
A macOS app that monitors AI tool usage — starting with **Claude Code** (rolling
usage limits + an estimated cost figure). Built clean-room from scratch. Keep the
design generic enough to add other AI tools later.

## Tech & layout
- **SwiftUI**, macOS 14+ deployment target.
- **Tuist** generates the Xcode project — there is no committed `.xcodeproj`.
- Layout:
  - `Project.swift` — Tuist manifest (targets live here).
  - `Sources/` — app target sources (`AIMonitorApp.swift`, `UI/`).
  - `Shared/` — model, data, and UI compiled into both the app and the widget.
  - `Widget/` — the WidgetKit extension.

## Build / run
- Generate the project: `tuist generate` (or `tuist generate --no-open`).
- Build (no Xcode UI): `tuist generate --no-open && xcodebuild -scheme AIMonitor -destination 'platform=macOS' build`
- After adding / moving / renaming / deleting files, re-run `tuist generate`.
  Not needed when only editing existing files.

## Conventions
- **File header** (new Swift files):
  ```
  //
  //  {FileName}.swift
  //  AI Monitor
  //
  //  Created by Rodrigo Busata on {MM/DD/YY}.
  //  © {Year} Rodrigo Busata.
  //
  ```
  (Personal project — do **not** use any company copyright.)
- **Access control**: default (`internal`) within a target. Use `public` only for
  types genuinely shared across targets (e.g. a future shared framework / the widget).
- **Previews** go at the end of the file, after the main type and helpers.
- Prefer small, focused types and views.

## Data sources & honesty
- **Tokens**: parsed locally from `~/.claude/projects/**/*.jsonl`. Stays on device.
- **5h / weekly limits**: the unofficial OAuth usage endpoint that Claude Code's
  `/usage` command uses. It is **undocumented and may break**; treat it as
  best-effort and degrade gracefully.
- **Authentication**: the app runs its **own OAuth + PKCE sign-in**
  (`AnthropicOAuth`) — the same unofficial flow and public client ID Claude Code
  uses; there is no official third-party registration. It does **not** read
  Claude Code's keychain item.
- **Extra-usage cost**: the dollar figure is what you're **charged for usage beyond
  the plan** ("extra usage"), not a token-list-price estimate. Label it "Extra usage",
  never "est. API value" or "spent".
- **Est. API value**: a separate, hypothetical figure — what the last 30 days of
  local token usage *would* cost at API list prices. Always labeled an estimate; never
  presented as money charged.
- **Token security**: the access + refresh tokens live only in the app's own
  Keychain item (`OAuthCredentialStore`); never log them or write them anywhere
  else. The usage figures shared with the widget contain no secrets.

## Git
- **Local only** for now. Do **not** add a remote or push without being asked.
- This repo will be connected to a **personal** GitHub account later — keep the work
  email out of commit history (repo-local `user.email` is set to a personal identity).
- The Tuist-generated project (`*.xcodeproj`, `*.xcworkspace`, `Derived/`) **is**
  committed so the app builds/runs without `tuist generate`. After adding / moving /
  renaming / deleting files, run `tuist generate` and commit the regenerated project.
  User-specific state (`xcuserdata/`, `*.xcuserstate`) stays ignored.
