# Changelog

All notable changes to TokenSpeed are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[semantic versioning](https://semver.org/). The version string lives in
`Sources/TokenSpeed/AppInfo.swift`; `tools/make_app.sh` copies it into the bundle.

## 1.0.0 — 2026-11-02

First public release.

### Added

- Menu bar item with three text states (`!` / `123.4t/s` / `idle`) and four icon
  states, driven by Strata's `/metrics` JSON (`live.state` decides the state).
- Detail panel: model/engine/context, request-phase bar, decode and prefill speed
  with sparklines, queue occupancy, per-slot detail, last request, per-GPU
  utilisation/temperature/power/VRAM, CPU, RAM, lifetime totals.
- Settings window: server URL, API key (write-only field), polling interval, panel
  fields, language. Changes apply without relaunching.
- Three UI languages: English, Simplified Chinese, Traditional Chinese.
- About window (the app is an accessory process, so macOS' own About panel does
  not exist) and an application icon.
- `tools/make_app.sh` (bundle with `Info.plist`, `LSUIElement`, ad-hoc signature)
  and `tools/install_launch_agent.sh` (kept running via a LaunchAgent, key from env).
- Unit tests for the three-state rule and the decode contract.

### Performance

- Idle: ~0.15 % CPU with the panel closed, ~0.25 % with it open. Busy with the
  panel closed: 0.1–0.5 %. Busy with the panel open: 2.4 % average, peak 4.4 %.
  Reached by drawing the pulse ring with Core Animation instead of redrawing an
  `NSImage` per frame, comparing before assigning the button's image/title/tooltip,
  and gating panel subtrees behind content fingerprints (was 12–20 %).
