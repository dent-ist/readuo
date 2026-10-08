# Readuo first-release design handoff

- `readuo-first-release.html` is the editable visualization fragment. It intentionally has no document wrapper, network calls, Flutter code, or Firebase integration.
- `readuo-first-release-preview.html` is the generated standalone QA wrapper. It embeds the fragment in the visualization sandbox and starts on `login`.
- The screen catalog contains 116 first-release screens and states in nine groups. Use the group and screen selectors to inspect any state directly; product-like interactions remain local to the preview.
- Camera, sign-in, system permissions, sharing, catalogue lookup, support submission, push delivery, and moderation actions are represented as design states only.

Regenerate the standalone wrapper after changing the fragment:

```powershell
& "$env:USERPROFILE\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe" `
  "$env:USERPROFILE\.codex\plugins\cache\openai-bundled\visualize\1.0.37\skills\visualize\scripts\render.py" `
  "C:\dev\ai\readuo\design\readuo-first-release.html" `
  "C:\dev\ai\readuo\design\readuo-first-release-preview.html" --force
```

Run structural checks:

```powershell
node C:\dev\ai\readuo\qa\check-readuo.cjs
```

See `docs/readuo-first-release-spec.md` for implementation requirements and `docs/readuo-design-audit.md` for verification evidence and remaining release dependencies.
