# TokenSpeed

Decode speed of your local [Strata](https://github.com/Niko1221/Strata) server,
permanently in the macOS menu bar.

A native menu-bar item — no Dock icon, no browser tab, no terminal TUI. It shows
one thing well: how fast your local inference server is decoding right now, and
what it is doing while it does.

Source: <https://github.com/leomsn/tokenspeed>

## What you get

The menu bar item has exactly three text states and four icon states:

| state | text | meaning |
|---|---|---|
| fetch failed | `!` | server down, unreachable, or the key was rejected — go look |
| busy | `123.4t/s` | live decode speed from `live.tok_s` |
| idle | `idle` | nothing to do — **never** shows the stale last speed |

The icon is a green ring (no data yet), a filled dot (idle), a dot plus a pulsing
ring (busy), or a blinking red dot (failure).

Clicking the item opens a panel: model/engine/context, a state bar that grows
while a request is reading vs. generating, decode and prefill speed with a
sparkline each, queue occupancy (`running · queued · waiting / parallel`),
per-slot detail, the last request, per-GPU utilisation/temperature/power/VRAM,
CPU, RAM and lifetime totals. English, Simplified Chinese and Traditional
Chinese; all numbers use thousands separators.

Right-click gives: refresh now, pause/resume polling, show/hide panel, keep panel
on top, About, Settings, Quit.

## Semantics, because that is the hard part

- **Idle is not zero and not the last number.** Strata keeps `hardware.tok_s`
  populated after a request finishes; showing it while `live.state == "idle"`
  would claim the machine is still decoding. TokenSpeed shows `idle` instead.
- **A parse error is a failure, not an idle.** The `live` section is the only one
  the decoder refuses to tolerate: if it cannot be read, the app shows `!`.
  Silently falling back to "idle" once masked a live generation as an idle
  server, which looked like a stuck UI.
- **Decode ≠ prefill ≠ latency.** They are never merged into one number, and
  every speed in the panel is labelled with where it came from — `current`,
  `this request`, or `last request`.

## Requirements

- macOS 13 or later (AppKit + SwiftUI, no third-party dependencies).
- A Strata server reachable from this Mac, with an API key configured. Strata's
  `/metrics` is not reachable from a browser (CORS is never opened for it), which
  is why this is a native process.

## Build and test

```bash
git clone https://github.com/leomsn/tokenspeed.git
cd tokenspeed
swift build -c release
.build/release/TokenSpeed          # runs until you quit it from the menu
```

```bash
swift test
```

The tests pin the three-state rule and the "`live` must throw" rule, since both
were found by being broken in production.

## Install as a menu-bar item

```bash
tools/make_app.sh
```

That produces `TokenSpeed.app` — an ad-hoc-signed bundle with `LSUIElement`, a real
icon, and a version taken from `Sources/TokenSpeed/AppInfo.swift` (the only place
a version is written). To keep it running across logins:

```bash
export STRATA_API_KEY=<your server key>
tools/install_launch_agent.sh
```

The installer writes `~/Library/LaunchAgents/com.eroeasy.tokenspeed.plist` with mode
600 and reloads the agent; the key is taken from the environment so it never
enters the repository.

## Configuration

Settings (⌘,) covers the server URL, the API key, the polling interval, which
panel fields to show, and the language. Every change takes effect immediately —
no relaunch. The key field is write-only: once saved, no code path reads it back
into the UI, so screenshots and screen shares cannot leak it.

If you change the server URL, a previously passing key check is dropped: the
check verified the old host.

## Cost

Measured on an Apple Silicon Mac polling a second machine over the LAN, sampling
`top` four times per state:

| state | CPU |
|---|---|
| idle, panel closed | ~0.15 % |
| idle, panel open | ~0.25 % |
| busy, panel closed | 0.1 – 0.5 % |
| busy, panel open | 2.4 % average (peak 4.4 %) |

Polling is 1–2 s by default on purpose: an observer that slows the thing it
observes has gotten the job backwards.

## Repository layout

```
Sources/TokenSpeed/   one type per file; StrataClient/Snapshot are the fetch layer,
                      the rest is presentation and formatting only
Tests/TokenSpeedTests three-state and decode-contract tests
tools/                make_app.sh, install_launch_agent.sh, metric probes
```

## Security and privacy

Read-only by construction; see [SECURITY.md](SECURITY.md). No request body or
response text is ever written to disk.

## Contributing

Bug reports and pull requests are welcome. Please include the version shown in
the About window, and which of the three menu-bar states you saw.

## License

[MIT](LICENSE).
