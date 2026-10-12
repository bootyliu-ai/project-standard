# Project Standard

[简体中文](README.zh-CN.md) · [Product definition](docs/product-definition.md) · [Technical design](docs/technical-design.md)

A minimal macOS menu-bar app for keeping project instructions consistent across AI coding agents.

Define your project's prompt, rules, memory, requirements, skills, MCP tools, and permissions/hooks in `.project-standard/`. Apply a scheme to supported clients with a switch, and remove only the app-owned projection when you turn it off.

## Features

- Compact 320 px menu-bar popover; multiple schemes per project.
- Open canonical files directly in your editor.
- Detect Codex, Claude Code, Smart Work, and DCC; add custom agents.
- Managed instruction blocks, relative skill links, scoped configuration merges, and rollback on failure.
- Watch project changes and revalidate enabled bindings.
- Client-version checks show unsupported or unverified mappings explicitly.

## Requirements and installation

[Download the latest release](https://github.com/bootyliu-ai/project-standard/releases/latest) · [Report an issue](https://github.com/bootyliu-ai/project-standard/issues)

macOS 13 or later. Universal distribution builds support Apple silicon and Intel.

For source builds, install Xcode with Swift 6 or later, then run:

```sh
scripts/test.sh
scripts/build-app.sh release
open .build/ProjectStandard.app
```

Click the shield icon in the menu bar and select a project. A starter scheme is created if the directory has no `.project-standard/`. Existing or incomplete standards are never overwritten.

For a DMG build:

```sh
scripts/package-dmg.sh local
```

Open the resulting DMG under `dist/` and drag the app into Applications. Local builds are ad-hoc signed and **not Apple-notarized**. macOS may block their first launch; use the system's Privacy & Security approval flow if you trust the build. See [distribution instructions](docs/distribution.md) for Developer ID signing and notarization.

## Client support

| Client | Tested baseline | Supported categories |
| --- | --- | --- |
| Codex | CLI 0.146.0; bundled 0.154.0-alpha.6.2 | Up to 7/7; portable Bash permission rules only |
| Claude Code | 2.1.212 | Up to 7/7 |
| Smart Work | 2026.8.19-alpha.1 | Instructions + Skills, up to 5/7 |
| DCC | 1.7.24 | Instructions + Skills, up to 5/7 |
| Custom agent | User-declared file paths | File projection only, up to 5/7; agent loading must be tested separately |

These are historical tested baselines, not claims of compatibility with every current release. Empty categories do not count. File projection checks do not prove that a model obeys instructions. MCP, permissions, and hooks require client-specific support.

## Add your own agent

Click `+` beside the connection list. Enter a name, the project-relative instruction file (for example `AGENTS.md`), and Skills directory (for example `.my-agent/skills`). Your agent must read these files and support the linked `SKILL.md` format. Enable its switch to apply the selected scheme; disable it before editing or deleting its definition.

## Project layout

```text
.project-standard/
  manifest.json
  schemes/base/
    prompt.md
    rules.md
    memory.md
    requirements.md
    skills/
    tools-mcp.json
    permissions-hooks.json
```

See [examples](examples/.project-standard/manifest.json) and the [Chinese guide](README.zh-CN.md) for configuration examples. Do not place credentials in scheme files.

## Development

Native Swift 6, AppKit, SwiftUI, and Swift Package Manager; no third-party package dependencies.

- `Sources/ProjectStandardCore`: discovery, source parsing, projection, bindings, and file watching.
- `Sources/ProjectStandardApp`: menu-bar UI and security-scoped project access.
- `Tests/`: temporary-project fixtures and regression tests.
- `prototypes/`: standalone HTML design prototype; illustrative data, not live detection.

Read [CONTRIBUTING.md](CONTRIBUTING.md) before changing adapters. See [SECURITY.md](SECURITY.md) for security reporting and [CHANGELOG.md](CHANGELOG.md) for release notes.

## License

[MIT](LICENSE). Client names belong to their respective owners; this project is not affiliated with them. No third-party client binaries are bundled.
