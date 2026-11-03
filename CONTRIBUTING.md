# Contributing

## Build, test, package

```bash
swift build -c release
swift test
zsh tools/make_app.sh
```

There is no Xcode project; `Package.swift` is the whole build.

## Rules that keep this app honest

1. **Probe the server before writing a parser.** Metric names change between
   Strata versions. Print the real `GET /metrics` response first — from memory
   they are always wrong. `tools/probe_metrics.sh` is a starting point.
2. **The fetch layer stays separate from the presentation layer.**
   `StrataClient.swift` and `Snapshot.swift` do network I/O and decoding and touch
   no UI; everything else only formats. Mixed together, a network hiccup becomes a
   rendering bug that nobody can reproduce.
3. **`live` must throw.** Every other section of `/metrics` may be tolerated if a
   field is missing; the `live` section may not. Treating "cannot parse" as "idle"
   once hid a running generation behind an `idle` menu bar item.
4. **Never show a number without its source.** Decode throughput, prompt
   processing and latency are three different things and are never merged into one
   figure. A value that came from the last request is labelled as such.
5. **The client is read-only.** `GET /metrics` and `GET /health` only. No endpoint
   that changes server state, and never the request-body monitor endpoints.
6. **No secrets in output.** The API key never goes to a log, the menu bar, or the
   source. Mask it as first four characters plus `****`.
7. **Localisation:** the key passed to `L()` *is* the Simplified Chinese string, so
   that locale needs no table. Add the `en` and `zhHant` entries in `L10n.swift`
   with your change, using Taiwanese terminology for Traditional Chinese.
8. **Check the real menu bar.** A green build does not mean the display is right —
   look at all three states (`!`, a number, `idle`), with the panel open and closed.
9. **Keep it cheap.** The pulse ring is a Core Animation layer, the status button
   compares before assigning, and panel subtrees sit behind content fingerprints.
   Slow down a visible refresh rate only if you say why.

## Scope

One Mac, one Strata server, one number that matters. Historical graphs, multi-host
aggregation and alerting are out of scope unless the maintainer asks for them.
