---
name: Bug report
about: The app shows something wrong, or stops working
labels: bug
---

**Version** — from the About window (right-click the menu bar item → About).

**What you saw** — which of the three menu bar states was showing (`!`, a number,
or `idle`), and what the panel showed at the same time. A screenshot helps.

**What you expected**

**Steps to reproduce**

**Environment**
- macOS version:
- Client Mac:
- Strata server version and machine (as `/health` reports it):

**Does the server itself agree?** — output of:

```
curl -H "Authorization: Bearer $STRATA_API_KEY" http://<server>:<port>/health
```

Paste the `live` section of `/metrics` if the numbers look wrong. Do not paste
your API key.
