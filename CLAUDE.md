# Project Memory

- The product is a minimal native macOS menu-bar utility with one compact popover, approximately 320 px wide.
- A project can contain multiple schemes. Each scheme contains Prompt, Rules, memory, project requirements, Skills, Tools/MCP, and permissions/Hooks.
- The selector circle changes the current scheme. The scheme name/summary opens details. One click performs one action.
- Detail rows show the canonical source path and open that file or reveal that directory.
- Application targets are client connection profiles: client + auth mode + Provider/route + user config source.
- Switching authentication or Provider configuration must not remove project foundations. Re-detect and revalidate the projection.
- Credentials never enter the scheme, UI, logs, or profile fingerprint.
- `.project-standard/` is canonical; Codex and Claude files are generated, reversible projections.
- The project picker accepts any directory. If `.project-standard` is absent, it atomically creates a one-scheme seven-category starter; it never overwrites an existing or incomplete standard directory.
- MVP 4 projects all seven categories when the scheme contains real content. It uses managed instruction/TOML blocks, project-level relative skill links, namespaced MCP keys, Codex exec-policy rules, and a Claude settings ownership receipt.
- Empty categories are not counted. Portable `Bash(...)` allow/ask/deny entries map to Codex project rules; Claude supports its broader permission model and Hooks directly.
- Codex discovery uses App Server `account/read`, `account/updated`, `config/read`, and `fs/watch`; the CLI status command is only a fallback. Claude discovery uses `claude auth status --json`. Only normalized non-secret labels are retained.
- The app uses FSEvents with an event-driven vnode fallback, coalesces changes, and automatically reapplies enabled bindings. Projection conflicts stay visible on the affected connection row.
- Every multi-file apply/cancel runs under a process lock with a pre-mutation snapshot and restores prior files, links, receipts, permissions, and newly created empty directories if any later step fails.
- Capability claims are version-gated. Codex CLI 0.146.0, the ChatGPT-bundled Codex 0.154.0-alpha.6.2, and Claude Code 2.1.212 are verified baselines; new versions remain usable but show a re-verification state until probes pass and the matrix is updated.
- Smart Work 2026.8.19-alpha.1 is detected from its `com.dichat.smartwork` app bundle. Its verified project surfaces are `AGENTS.md` and repo-scoped `.agents/skills`, so it reports 5/7; MCP and permissions/Hooks remain unsupported until their load paths are verified.
- DCC 1.7.24 and Claude Code are automatically detected through sandboxed read-only exceptions limited to `~/.local/bin` and their version directories. Credential and configuration directories remain inaccessible. DCC's verified Claude-backed project surfaces are `CLAUDE.md` and `.claude/skills`, so it reports 5/7.
- Users can add custom agents from the connection-list `+` with a name, project-relative instruction file, and project-relative Skills directory. Each custom agent owns separate UUID-scoped blocks and link receipts, supports 5/7 categories, and never infers MCP, permissions, or Hooks support.
- Product definition: `docs/product-definition.md`; implementation plan: `docs/technical-design.md`; prototype: `prototypes/workspace-standard-hub.html`.
- Distribution: `scripts/package-release.sh` builds a universal local test ZIP or a Developer ID signed, hardened, notarized and stapled ZIP. The notarized mode requires an installed signing identity and a Keychain-backed notarytool profile; credentials never enter the repository.
- `scripts/package-dmg.sh` creates a drag-to-Applications DMG in local unnotarized or Developer ID notarized mode. Only the notarized `macos-universal.dmg` is suitable for frictionless external distribution.

- Open-source preparation (2026-10-12): MIT license, bilingual README, contribution/security guides, issue/PR templates and macOS CI are included. Public repository: https://github.com/bootyliu-ai/project-standard. Build outputs stay excluded from source control and are distributed as explicitly unnotarized Release assets.
