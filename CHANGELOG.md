# Changelog

All notable changes to TokenSpeed are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[semantic versioning](https://semver.org/). The version string lives in
`Sources/TokenSpeed/AppInfo.swift`; `tools/make_app.sh` copies it into the bundle.

## 1.0.2 — 2026-11-07

### Added

- Maya server support. Maya is a Strata variant; TokenSpeed auto-detects the
  flavor from the `engine.maya_version` marker in `/metrics` and treats every
  server without that marker as Strata, so existing setups behave exactly as
  before. The model line shows the engine as `Maya x.y.z`.
- Panel parity on Maya: decode/prefill speed with sparklines, the busy-state
  progress bar, last request, per-GPU utilisation/temperature/power/VRAM, CPU,
  RAM and lifetime totals all read the Maya fields. The queue line maps Maya's
  `active` to running and omits the parallel-capacity figure the variant does
  not report; the Slots card hides when the server sends no slots. Idle prefill
  prefers Maya's direct per-request `prefill_tok_s` over deriving it from
  `prompt_ms`.

### Fixed

- On Maya, whole sections used to vanish silently: `requests[]` entries there
  carry no `id` and `hardware.gpus[]` carries no `name`, and both fields were
  mandatory in the decoder. They are optional now; before this, a Maya server
  showed no GPU/CPU/RAM data and no last-request card at all.
- `/health` now understands Maya's `unloaded` boolean (the inverse of `loaded`).

## 1.0.1 — 2026-11-03

### Fixed

- A failing fetch no longer stays failed forever. `URLSession` carries the
  "network offline" reachability verdict on its session, so a long-running
  process could stay in the failure state for hours while `curl` still reached
  the server. After three consecutive connection failures the client now
  discards that session and builds a new one, which also closes the connections
  the failed attempts left behind. Errors where the server answered — a wrong
  status code or a body we cannot parse — do not count towards that threshold.
- Changing the server URL or the API key replaces the client; the old session is
  now invalidated instead of dropped, so its pooled connections are closed.

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
