# Project Standard

[English](README.md) · [贡献指南](CONTRIBUTING.md) · [MIT 许可证](LICENSE)

Project Standard 是一个极简的 macOS 菜单栏应用。它把一个项目的 Prompt、Rules、记忆、项目要求、Skills、Tools/MCP、权限/Hooks 保存为统一方案，再由端适配器应用到 Codex、Claude Code、DCC、Smart Work 和用户添加的自研 Agent。

## 当前产物

- `Package.swift`、`Sources/`：可编译的原生 macOS 菜单栏应用。
- `Tests/`：项目解析与安全投影测试。
- `scripts/build-app.sh`：生成可双击的 `.build/ProjectStandard.app`。
- `scripts/package-release.sh`：生成 Universal 本地测试包或 Developer ID 签名、公证后的正式分享包。
- `scripts/package-dmg.sh`：生成包含“应用程序”快捷入口的拖拽安装 DMG；同样支持本地测试或 Developer ID 公证模式。
- `scripts/probe-clients.sh`：运行脱敏的客户端版本、能力和 Codex App Server 回归探针。
- `docs/product-definition.md`：已确认的产品范围与交互。
- `docs/technical-design.md`：可实施的 macOS 技术方案、数据模型、适配器和安全边界。
- `docs/implementation-status.md`：当前已完成能力、验证结果与交付边界。
- `prototypes/workspace-standard-hub.html`：可交互菜单栏 Popover 原型。
- `examples/.project-standard/`：项目内统一方案源文件示例。

直接打开 `prototypes/index.html` 可进入原型。原型中的文件打开行为用提示模拟；正式应用使用 `NSWorkspace` 打开真实路径。

## 核心原则

1. `.project-standard/` 是项目基础内容的唯一来源。
2. 端配置是投影结果，不反向成为方案真相。
3. 账号、认证方式和 Provider 路由只用于识别接入配置，不进入方案，也不保存密钥。
4. 应用与取消只修改本应用拥有的区块、链接和配置键。
5. 新适配器必须先声明能力和限制，再允许显示“已生效”。

## 构建与运行

```bash
scripts/test.sh
scripts/build-app.sh
scripts/probe-clients.sh
scripts/run-example.sh
```

对外分享前按 [`docs/distribution.md`](docs/distribution.md) 配置 Developer ID 与 Apple 公证，然后运行 `scripts/package-release.sh notarized`。当前仓库中的 ad-hoc 签名 App 只能作为本机开发产物。

`run-example.sh` 使用 `examples/` 作为演示项目。正式 `.app` 首次启动后点击菜单栏图标，可以选择任意项目目录；目录尚未配置时，应用会原子创建一个包含七类基础文件的默认方案。已有 `.project-standard` 不会被覆盖。

当前实现按实际内容逐类校验：

- 四类指令内容写入 Codex/Smart Work 的 `AGENTS.md` 或 Claude Code 的 `CLAUDE.md` 受管区块。
- Skills 以相对符号链接写入 Codex/Smart Work 的 `.agents/skills/` 或 Claude Code 的 `.claude/skills/`。
- MCP 键级合并到 Codex `.codex/config.toml` 或 Claude Code `.mcp.json`。
- Hooks 写入两端的项目配置；Claude 权限规则逐项合并到 `.claude/settings.json`，可移植的 `Bash(...)` 规则写入 Codex `.codex/rules/project-standard.rules`。

“本机接入”右侧的 `＋` 可添加自定义端。只需填写端名称、它读取的项目指令文件和项目 Skills 目录；路径必须位于项目内。自定义端以独立受管区块和链接回执覆盖 Prompt、Rules、记忆、项目要求与 Skills（`5/7`），可单独应用、取消、编辑和删除。未声明协议的 MCP、权限与 Hooks 不会被虚报为生效。

Smart Work `2026.8.19-alpha.1` 已验证项目 `AGENTS.md` 与 `.agents/skills`，因此当前准确覆盖 Prompt、Rules、记忆、项目要求和 Skills（`5/7`）。DCC `1.7.24` 已验证会启动本地 Claude Code，并读取项目 `CLAUDE.md` 与 `.claude/skills`，当前同样准确覆盖 `5/7`；DCC 的 MCP、权限与 Hooks 在独立加载行为完成验证前不计为生效。Claude Code `2.1.212` 继续覆盖 `7/7`。

由于 DCC 与 Claude Code 通常安装在用户目录 `~/.local/bin`，应用保留 App Sandbox，并只对 `.local/bin` 及两端版本目录声明只读访问。发现过程自动完成，不再要求用户授权隐藏目录；应用仅读取 `dcc`、`claude` 的可执行路径和版本，不读取 DCC、Claude 的账号或凭据文件。

空分类不会虚报生效。方案提供 Skill、MCP 和权限/Hooks 内容并通过目标校验后，界面会显示到 `7/7 生效`。应用使用 FSEvents 监听源文件和投影目标；不可用时降级为事件驱动的 vnode 监听，不使用定时轮询。已开启的绑定发生变化后自动重新读取、投影并验证，冲突会显示在对应接入行。一次应用或取消涉及的所有目标文件属于同一事务，任一步失败都会恢复此前修改。

Codex 接入优先使用 App Server 的账号事件和生效配置识别认证与 Provider。App Sandbox 首次阻止访问时，页脚会显示“授权 Codex”；选择 `.codex` 目录后保存 security-scoped bookmark。应用模型不包含邮箱、Token、API Key 或 Cookie。检测到未经验证的客户端版本时仍可使用，但不会显示绿色的已验证状态。

## 结构化源文件

`tools-mcp.json` 使用两端都能表达的 MCP server 对象：

```json
{
  "tools": [],
  "mcpServers": {
    "docs": {
      "type": "http",
      "url": "https://example.com/mcp"
    }
  }
}
```

`permissions-hooks.json` 中，Claude 支持 `allow`、`ask`、`deny`、`additionalDirectories`；Hooks 使用两端当前共同支持的事件结构：

```json
{
  "permissions": {
    "allow": ["Bash(git status)"]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "./scripts/check.sh" }
        ]
      }
    ]
  }
}
```

项目文件只能引用环境变量名，不能保存 Token、API Key 或 Cookie。

Codex 当前可移植映射覆盖 `Bash(command)` 形式的 `allow`、`ask`、`deny`。其他 Claude 专用工具权限仍保留在方案源中，但不会被 Codex 计为已生效。
