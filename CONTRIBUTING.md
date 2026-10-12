# Contributing

Read README.md, docs/product-definition.md, docs/technical-design.md, and AGENTS.md first. Keep the product a small menu-bar utility.

## Local checks

Use macOS with Xcode and Swift 6 or later:

```sh
scripts/test.sh
scripts/build-app.sh release
```

Use temporary projects and synthetic credentials in fixtures. Never commit real credentials, user configuration, security bookmarks, build output, or client binaries.

## Adapter changes

All writes must be scoped, reversible, atomic, and idempotent. Preserve user-owned data. Test apply, reapply, cancellation, conflicts, and rollback. Add named client versions to the verified matrix only after testing real loading behavior against that version. Custom-agent file mappings alone are not evidence of runtime compatibility.

Describe the problem, resulting behavior, tests run, and any unsupported mapping in your pull request. Include a screenshot for UI changes and keep prototypes under prototypes/.

## Issues

Include macOS/app/client versions, reproduction steps, expected behavior, and sanitized logs. Use the feature template for new clients or mapping requests. Never paste keys or account configuration.

Contributions are licensed under the project's MIT license.
