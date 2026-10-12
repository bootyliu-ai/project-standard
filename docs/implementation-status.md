# 实现状态

## 2026-09-18 · MVP 5.0

已完成：

- 原生 `NSStatusItem + NSPopover` 菜单栏应用，SwiftUI 渲染约 320 px 宽的紧凑内容。
- 任意项目目录选择、缺少规范时原子创建默认七类方案、security-scoped bookmark 持久化和命令行 `--project` 开发入口；已有内容不被覆盖。
- `.project-standard/manifest.json` 解析、schema 校验、重复方案拒绝和七类路径解析。
- 方案选择与详情查看使用独立点击目标。
- 详情显示真实相对路径；文件由默认应用打开，目录在 Finder 中定位。
- 不执行 shell 配置、不读取凭据的 Codex/Claude/Smart Work 安装发现；身份不确定时显示“认证 / Provider 待识别”。
- 每个接入的应用/取消与本机 binding 持久化。
- 自定义端新增、编辑和删除；用户只需配置名称、项目指令文件和 Skills 目录。每个自定义端使用独立 UUID 受管区块、Skill 链接和回执，可准确投影并校验 `5/7`，共享目标时仍可独立取消。
- 自定义端路径强制为项目内相对路径，拒绝绝对路径、父目录跳转与 `.project-standard` 源目录；MCP、权限和 Hooks 在未声明适配协议时不计为生效。
- Codex `AGENTS.md`、Claude Code `CLAUDE.md` 的受管区块投影，支持幂等更新、验证和精确取消。
- Codex `.agents/skills/` 与 Claude Code `.claude/skills/` 的项目级相对链接；链接回执用于精确取消，用户改动过的链接不会被删除。
- Codex 项目 `.codex/config.toml` 的 MCP/Hooks 受管 TOML 区块；Claude `.mcp.json` 的 namespaced MCP 键级合并。
- Codex `.codex/rules/project-standard.rules` 的受管权限区块，将可移植的 `Bash(...)` allow/ask/deny 映射为 allow/prompt/forbidden，并支持精确取消。
- Claude `.claude/settings.json` 权限/Hooks 的逐项合并、ownership receipt 和撤销，保留用户键和值。
- 结构化配置预解析、原子写入、幂等重投影、逐分类真实校验和配置形状冲突保护。
- 通过 Codex App Server `account/read`、`account/updated`、`config/read` 与 `fs/watch` 识别账号类型、Provider 并监听切换；CLI 状态命令仅作为降级路径。
- App Sandbox 下通过系统目录选择器一次性授权 `.codex` 并保存 security-scoped bookmark，不增加主目录或 Full Disk Access 权限。
- Claude Code 继续使用官方 `auth status --json`；两端只保留归一化非秘密标签，不读取或保存邮箱与凭据。
- Smart Work 通过 `com.dichat.smartwork` App Bundle、版本和内置运行时识别；`2026.8.19-alpha.1` 已验证项目 `AGENTS.md` 与 `.agents/skills`，提供准确的 `5/7` 投影，不读取 Application Support 下的认证或 Provider 文件。
- DCC 通过受控可执行路径和版本化 symlink 识别；`1.7.24` 已验证其本地 Claude Code 包装行为，项目 `CLAUDE.md` 与 `.claude/skills` 提供准确的 `5/7` 投影。
- App Sandbox 仅对 `~/.local/bin`、DCC 版本目录和 Claude Code 版本目录声明只读临时例外，解决菜单栏 App 缺少终端 `PATH` 的问题；无需用户授权隐藏目录，也不开放 `.dcc` 或 `.claude` 配置目录。
- 客户端认证/Provider 切换后把原绑定迁移到新发现的当前 profile，项目级投影持续有效。
- Codex CLI 0.146.0、ChatGPT 内置 Codex 0.154.0-alpha.6.2、Claude Code 2.1.212 的版本能力矩阵；每次发现自动探测必要协议面，新版本显示待回归而不沿用旧验证结论。
- `scripts/probe-clients.sh` 脱敏真实客户端探针，可验证版本、能力和 Codex App Server 握手。
- 应用与取消的多文件事务快照、进程级串行锁和反向回滚；恢复文件、符号链接、receipt、权限及本次新建的空目录。
- FSEvents 监听规范源与投影目标并以 650 ms 合并事件；启动失败时自动使用递归 vnode 事件监听，不依赖定时轮询。
- 变化后自动重载、逐接入修复已开启绑定并重新校验；损坏的受管区块保留原文件，并在对应接入行显示需处理状态。
- `.app` 打包、App Sandbox entitlement、ad-hoc 开发签名与右键退出。
- Universal 本地测试包，以及 Developer ID、Hardened Runtime、Apple 公证、票据装订、Gatekeeper/架构校验和 SHA-256 输出的正式分发脚本。

投影引擎最高覆盖 `7/7`。空 Skills、空 MCP、空权限/Hooks 不计为生效；示例方案仍会按实际内容显示，不虚报。

验证结果：

- Swift Debug/Release 构建通过。
- 24 个核心测试通过，包括首次项目初始化与不覆盖保护、Codex/Claude `7/7` fixture、Smart Work/DCC/自定义端 `5/7` fixture、自定义端路径边界与共享目标独立取消、Bundle 和授权目录发现、幂等、用户配置保留、精确取消、应用/取消事务回滚、App Server 配置事件、自定义 Provider、能力矩阵、真实文件变更事件和损坏受管区块保护。
- Codex CLI `0.146.0` 已以 `--strict-config` 启动并接受生成的 MCP/Hooks TOML；Hooks feature 为 stable。
- Codex CLI `0.146.0` 的 `execpolicy check` 已接受生成的项目权限规则并匹配预期 allow 决策。
- 本机脱敏回归探针已分别完成 CLI Codex 0.146.0 与 ChatGPT 内置 Codex 0.154.0-alpha.6.2 的真实 App Server 握手，通过 `account/read` 与 `config/read` 形成 `Codex · ChatGPT 登录` 接入；未输出邮箱或凭据。
- Claude Code `2.1.212` 已通过 `claude doctor` 读取生成的项目 MCP、权限和 Hooks 配置。
- Smart Work `2026.8.19-alpha.1` 的本机 Bundle 与运行时代码已确认项目读取 `AGENTS.md`，并把项目路径上的 `.agents/skills` 作为 Repo scope 扫描。
- DCC `1.7.24` 的本机安装 symlink 与源码已确认其启动 Claude Code 并透传参数，项目规则和 Skills 继续使用 Claude Code 的项目入口。
- `Info.plist` 与 entitlements 校验通过。
- `.app` codesign 严格验证通过。
- 开发版已成功启动并加载三方案、七分类的示例项目。

## 完成边界

当前确认范围已经实现，没有遗留的 MVP 功能项。正式 Developer ID 签名与公证流程已经脚本化，但本机尚未安装签名证书，无法生成 Apple 信任链认可的正式包。后续还有新增客户端、客户端协议变化与可选的 App Store 分发工作；这些不会影响当前本地使用。所有新增适配或版本必须在脱敏 fixture 和目标客户端探针通过后，才能增加验证范围。
