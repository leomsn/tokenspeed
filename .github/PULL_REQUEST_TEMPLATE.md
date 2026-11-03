<!-- What does this change let someone see or do? One or two sentences. -->

**How I verified it** — which of the three menu bar states was observed, and with
the panel open and closed. Type checks are not evidence that the display is right,
especially for the non-numeric states (`!`, `idle`).

- [ ] `swift build -c release` succeeds
- [ ] `swift test` succeeds
- [ ] If the change touches fetching or decoding: the three-state rule and the
      "`live` must throw" tests still describe reality (see `Tests/TokenSpeedTests`)
- [ ] If the change adds UI text: entries added for `en` and `zhHant` in `L10n.swift`
