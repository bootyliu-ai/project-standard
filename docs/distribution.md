# 分发 Project Standard

## 当前状态

仓库默认构建使用 ad-hoc 签名，只适合开发机运行。通过聊天工具、网盘、邮件或 AirDrop 发送后，macOS 会为文件增加 quarantine 属性；没有 Developer ID 与 Apple 公证的版本可能被 Gatekeeper 拦截。

正式分享采用站外分发：Universal App、Developer ID Application 签名、Hardened Runtime、Apple 公证、票据装订和 ZIP 校验值。App Sandbox 继续保留。

## 本地测试包

```bash
scripts/package-release.sh local
```

输出：

- `dist/ProjectStandard-<version>-<build>-local-unnotarized.zip`
- 同名 `.sha256`

该包同时包含 Apple silicon 与 Intel 架构，但未经过 Apple 信任链验证。它只用于开发验证，不能作为面向普通用户的正式下载。

生成可拖拽安装的本地 DMG：

```bash
scripts/package-dmg.sh local
```

DMG 内包含 `ProjectStandard.app` 和“应用程序”快捷入口。未公证版本发送到其他 Mac 后，首次打开需在 Finder 中右键应用并选择“打开”。

## 一次性发布准备

1. 加入 Apple Developer Program。
2. 由有权限的账号创建并安装 `Developer ID Application` 证书。
3. 将公证凭据存入 Keychain。命令会对未提供的凭据进行安全交互式提示：

```bash
xcrun notarytool store-credentials project-standard-notary
```

不要把证书私钥、Apple ID 密码、App Store Connect 私钥或公证凭据写入仓库、脚本或环境文件。

查看本机证书的完整名称：

```bash
security find-identity -v -p codesigning
```

## 生成正式分享包

```bash
export PROJECT_STANDARD_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export PROJECT_STANDARD_NOTARY_PROFILE='project-standard-notary'
scripts/package-release.sh notarized
scripts/package-dmg.sh notarized
```

脚本会依次执行：

1. 分别编译 arm64 与 x86_64，并合成为 Universal 可执行文件。
2. 使用 Developer ID 签名、Hardened Runtime 和项目 entitlements。
3. 生成 ZIP 并通过 `notarytool` 等待 Apple 公证结果。
4. 将公证票据 staple 到 App，重新生成 ZIP。
5. 运行 `codesign`、`stapler`、`spctl` 和 Universal 架构检查。
6. 输出 ZIP 与 SHA-256 校验文件。

优先分享文件名以 `macos-universal.dmg` 结尾的正式产物。接收者打开 DMG 后把 `ProjectStandard.app` 拖入“应用程序”，首次启动选择项目目录；需要检测 Codex 账号与 Provider 时，再在菜单栏 App 中授权 `.codex` 目录。

## 发布前检查

```bash
codesign --verify --deep --strict --verbose=2 dist/ProjectStandard.app
xcrun stapler validate dist/ProjectStandard.app
spctl --assess --type execute --verbose=4 dist/ProjectStandard.app
xcrun lipo -archs dist/ProjectStandard.app/Contents/MacOS/ProjectStandard
cd dist
shasum -a 256 -c ProjectStandard-<version>-<build>-macos-universal.zip.sha256
```

每次修改二进制、Info.plist 或 entitlements 后都必须重新签名和公证。公证后的 App 也要在一台没有开发环境、没有已有安全书签的 Mac 上完成首次启动、项目选择、Codex 授权、应用与取消方案的回归验证。
