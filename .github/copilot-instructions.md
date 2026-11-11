# Copilot instructions

Follow [AGENTS.md](../AGENTS.md) in the repository root. It holds the rules for every coding agent in this project: the issue and branch workflow, the module contract, the working conventions and the checks to run before a pull request.

The most important rules:

- Work on a `feature/<name>` or `bugfix/<name>` branch from `main`. Never push to `main`.
- Plain Lua 5.1 for the WoW Forever client (Retail API, `## Interface: 16001`), no libraries.
- Every `Gulli-<Name>` folder is one addon. A module works without `Gulli-Toolkit` and registers with it through `GulliToolkit.Register` when it is there.
- QuestCleaner: nothing is removed without the preview; every abandon and delete runs from the **OK** click.
- Every UI text goes into all 8 languages in that addon's `Locales.lua`.
- Before a pull request, run `for t in tests/*/test.lua; do lua5.1 "$t"; done`.
- Before you file or fix a bug, follow [the file-issue skill](../.agents/skills/file-issue/SKILL.md).
- Before you finish a task, check `README.md` and the module's `docs/<name>/README.md`.
