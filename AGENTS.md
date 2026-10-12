# Project Standard Working Rules

These instructions apply to every task in this repository.

1. Read `README.md`, `docs/product-definition.md`, and `docs/technical-design.md` before changing product behavior or architecture.
2. Preserve the menu-bar-only product scope. Do not add a full desktop window, dashboard, sidebar, activity feed, or configuration matrix unless the user explicitly changes the scope.
3. Treat `.project-standard/` as canonical project content and terminal-specific files as generated projections.
4. Never store, copy, log, display, or test with real API keys, tokens, cookies, or account credentials.
5. Adapter writes must be scoped, reversible, atomic, and idempotent. Preserve user-owned content outside managed markers or owned keys.
6. Mark adapter behavior as verified only after testing it against the named client version. Unknown or unsupported mappings must remain visible as such.
7. Keep prototypes under `prototypes/` and keep `prototypes/index.html` current.
