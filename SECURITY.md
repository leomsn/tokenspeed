# Security Policy

## What TokenSpeed can and cannot do to your server

The client is read-only by construction: `StrataClient` only issues `GET /metrics`
and `GET /health`. There is no code path that calls `POST /load`, `POST /unload`,
`POST /slots/…` or any other endpoint that changes server state, and the client
never polls Strata's request-body monitor endpoints (`/api-monitor`, `/api/requests`),
which would return your prompts and answers.

Nothing you send to a server is written to a local log, and no prompt or response
body is ever stored on disk.

## Where the API key lives

- The value you type in the settings window is stored in `UserDefaults` under the
  `apiKey` key (domain `TokenSpeed`), and is never shown again.
- If nothing is saved, the client falls back to the `STRATA_API_KEY` environment
  variable — normally supplied by the LaunchAgent plist.
- The binary is unsigned and rebuilt on every change, so a Keychain item would
  re-prompt on every build; that's why it isn't Keychain. If that trade-off is not
  acceptable for your setup, clear the field in the settings window and keep the
  key in the environment only.

Report a vulnerability privately rather than in a public issue: open a draft
security advisory from the repository's Security tab, or e-mail the maintainer
directly. Include the version from the About window.
