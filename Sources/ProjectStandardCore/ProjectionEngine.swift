import Foundation

public enum ProjectionEngineError: LocalizedError {
    case malformedJSON(String)
    case invalidShape(String)
    case targetConflict(String)
    case targetNotWritable(String)
    case rollbackFailed(String)

    public var errorDescription: String? {
        switch self {
        case .malformedJSON(let path): "配置不是有效 JSON：\(path)"
        case .invalidShape(let message): message
        case .targetConflict(let message): message
        case .targetNotWritable(let path): "无法写入 \(path)"
        case .rollbackFailed(let message): "投影失败且回滚未完整完成：\(message)"
        }
    }
}

enum ProjectionMutationStage: Sendable {
    case instructions
    case skills
    case toolsMcp
    case permissionsHooks
}

public struct ProjectionValidation: Sendable, Equatable {
    public let effective: Set<FoundationCategory>

    public init(effective: Set<FoundationCategory>) {
        self.effective = effective
    }

    public var count: Int { effective.count }
}

/// Projects the canonical seven categories into the files each client actually reads.
/// Every mutation is either a marked block, an app-owned symlink, or an exact JSON value
/// recorded in a local receipt so cancellation can preserve user-owned content.
public struct ProjectionEngine {
    private static let mutationLock = NSLock()
    private let fileManager: FileManager
    private let faultInjector: (ProjectionMutationStage) throws -> Void

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.faultInjector = { _ in }
    }

    init(
        fileManager: FileManager = .default,
        faultInjector: @escaping (ProjectionMutationStage) throws -> Void
    ) {
        self.fileManager = fileManager
        self.faultInjector = faultInjector
    }

    @discardableResult
    public func apply(project: LoadedProject, scheme: Scheme, client: ClientKind) throws -> ProjectionValidation {
        try apply(project: project, scheme: scheme, destination: ProjectionDestination(client: client))
    }

    @discardableResult
    public func apply(project: LoadedProject, scheme: Scheme, profile: ConnectionProfile) throws -> ProjectionValidation {
        try apply(project: project, scheme: scheme, destination: profile.projectionDestination)
    }

    private func apply(
        project: LoadedProject,
        scheme: Scheme,
        destination: ProjectionDestination
    ) throws -> ProjectionValidation {
        Self.mutationLock.lock()
        defer { Self.mutationLock.unlock() }
        guard fileManager.isWritableFile(atPath: project.rootURL.path) else {
            throw ProjectionEngineError.targetNotWritable(project.rootURL.path)
        }

        // Parse structured sources only for adapters that currently project them.
        let client = destination.client
        let projectsStructuredConfiguration = client == .codex || client == .claudeCode
        let mcp = projectsStructuredConfiguration ? try loadMCP(from: source(.toolsMcp, in: scheme)) : [:]
        let permissionsHooks = projectsStructuredConfiguration
            ? try loadPermissionsHooks(from: source(.permissionsHooks, in: scheme))
            : PermissionsHooks(permissions: [:], hooks: [:])
        let transaction = try ProjectionTransaction(
            targets: transactionTargets(project: project, scheme: scheme, destination: destination),
            rootURL: project.rootURL,
            fileManager: fileManager
        )

        do {
            try applyInstructions(project: project, scheme: scheme, destination: destination)
            try faultInjector(.instructions)
            try applySkills(project: project, scheme: scheme, destination: destination)
            try faultInjector(.skills)
            switch client {
            case .codex:
                try applyCodexMCP(project: project, scheme: scheme, servers: mcp)
                try faultInjector(.toolsMcp)
                try applyCodexPermissions(project: project, permissions: permissionsHooks.permissions)
                try applyCodexHooks(project: project, scheme: scheme, hooks: permissionsHooks.hooks)
                try faultInjector(.permissionsHooks)
            case .claudeCode:
                try applyClaudeMCP(project: project, scheme: scheme, servers: mcp)
                try faultInjector(.toolsMcp)
                try applyClaudeSettings(project: project, permissionsHooks: permissionsHooks)
                try faultInjector(.permissionsHooks)
            case .smartWork:
                break
            case .dcc:
                break
            case .custom:
                break
            }
        } catch let mutationError {
            do { try transaction.rollback() }
            catch let rollbackError {
                throw ProjectionEngineError.rollbackFailed(
                    "原错误：\(mutationError.localizedDescription)；回滚错误：\(rollbackError.localizedDescription)"
                )
            }
            throw mutationError
        }
        return validate(project: project, scheme: scheme, destination: destination)
    }

    public func cancel(project: LoadedProject, scheme: Scheme, client: ClientKind) throws {
        try cancel(project: project, scheme: scheme, destination: ProjectionDestination(client: client))
    }

    public func cancel(project: LoadedProject, scheme: Scheme, profile: ConnectionProfile) throws {
        try cancel(project: project, scheme: scheme, destination: profile.projectionDestination)
    }

    private func cancel(
        project: LoadedProject,
        scheme: Scheme,
        destination: ProjectionDestination
    ) throws {
        Self.mutationLock.lock()
        defer { Self.mutationLock.unlock() }
        let client = destination.client
        let mcp = client == .claudeCode ? try loadMCP(from: source(.toolsMcp, in: scheme)) : [:]
        let transaction = try ProjectionTransaction(
            targets: transactionTargets(project: project, scheme: scheme, destination: destination),
            rootURL: project.rootURL,
            fileManager: fileManager
        )
        do {
            try cancelInstructions(project: project, destination: destination)
            try faultInjector(.instructions)
            try cancelSkills(project: project, destination: destination)
            try faultInjector(.skills)
            switch client {
            case .codex:
                try removeTextBlock(at: codexConfigURL(project), start: codexMCPStart, end: codexMCPEnd)
                try removeTextBlock(at: codexConfigURL(project), start: codexHooksStart, end: codexHooksEnd)
                try faultInjector(.toolsMcp)
                try removeTextBlock(at: codexRulesURL(project), start: codexPermissionsStart, end: codexPermissionsEnd)
                try faultInjector(.permissionsHooks)
            case .claudeCode:
                try cancelClaudeMCP(project: project, scheme: scheme, servers: mcp)
                try faultInjector(.toolsMcp)
                try cancelClaudeSettings(project: project)
                try faultInjector(.permissionsHooks)
            case .smartWork:
                break
            case .dcc:
                break
            case .custom:
                break
            }
        } catch let mutationError {
            do { try transaction.rollback() }
            catch let rollbackError {
                throw ProjectionEngineError.rollbackFailed(
                    "原错误：\(mutationError.localizedDescription)；回滚错误：\(rollbackError.localizedDescription)"
                )
            }
            throw mutationError
        }
    }

    public func validate(project: LoadedProject, scheme: Scheme, client: ClientKind) -> ProjectionValidation {
        validate(project: project, scheme: scheme, destination: ProjectionDestination(client: client))
    }

    public func validate(project: LoadedProject, scheme: Scheme, profile: ConnectionProfile) -> ProjectionValidation {
        validate(project: project, scheme: scheme, destination: profile.projectionDestination)
    }

    private func validate(
        project: LoadedProject,
        scheme: Scheme,
        destination: ProjectionDestination
    ) -> ProjectionValidation {
        let client = destination.client
        var result = Set<FoundationCategory>()
        let instructionTarget = project.rootURL.appendingPathComponent(destination.instructionFile)
        if let text = try? String(contentsOf: instructionTarget, encoding: .utf8),
           ManagedBlockEditor.contains(scheme: scheme, in: text, identifier: destination.markerIdentifier) {
            for item in scheme.categories where item.exists && [.prompt, .rules, .memory, .requirements].contains(item.category) {
                result.insert(item.category)
            }
        }

        if validateSkills(project: project, scheme: scheme, destination: destination) {
            result.insert(.skills)
        }

        if client == .codex || client == .claudeCode,
           let servers = try? loadMCP(from: source(.toolsMcp, in: scheme)), !servers.isEmpty {
            let valid = client == .codex
                ? validateTextBlock(at: codexConfigURL(project), block: codexMCPBlock(scheme: scheme, servers: servers))
                : validateClaudeMCP(project: project, scheme: scheme, servers: servers)
            if valid { result.insert(.toolsMcp) }
        }

        if client == .codex || client == .claudeCode,
           let configuration = try? loadPermissionsHooks(from: source(.permissionsHooks, in: scheme)), !configuration.isEmpty {
            let valid: Bool
            if client == .codex {
                let mapped = codexPermissionRules(configuration.permissions)
                let permissionsValid = !configuration.hasPermissions ||
                    (mapped.complete && validateTextBlock(at: codexRulesURL(project), block: codexPermissionsBlock(mapped.rules)))
                let hooksValid = !configuration.hasHooks ||
                    validateTextBlock(at: codexConfigURL(project), block: codexHooksBlock(hooks: configuration.hooks))
                valid = permissionsValid && hooksValid
            } else {
                valid = validateClaudeSettings(project: project, configuration: configuration)
            }
            if valid { result.insert(.permissionsHooks) }
        }
        return ProjectionValidation(effective: result)
    }

    // MARK: - Instructions

    private func applyInstructions(project: LoadedProject, scheme: Scheme, destination: ProjectionDestination) throws {
        let target = project.rootURL.appendingPathComponent(destination.instructionFile)
        let existing = (try? String(contentsOf: target, encoding: .utf8)) ?? ""
        let hasStart = existing.contains(ManagedBlockEditor.startMarker(identifier: destination.markerIdentifier))
        let hasEnd = existing.contains(ManagedBlockEditor.endMarker(identifier: destination.markerIdentifier))
        guard hasStart == hasEnd else {
            throw ProjectionEngineError.targetConflict("受管指令区块不完整，请先检查：\(target.path)")
        }
        let output = ManagedBlockEditor.upsert(
            existing: existing,
            block: ManagedBlockEditor.block(for: scheme, identifier: destination.markerIdentifier),
            identifier: destination.markerIdentifier
        )
        try writeTextIfChanged(output, existing: existing, to: target)
    }

    private func cancelInstructions(project: LoadedProject, destination: ProjectionDestination) throws {
        let target = project.rootURL.appendingPathComponent(destination.instructionFile)
        guard fileManager.fileExists(atPath: target.path) else { return }
        let existing = try String(contentsOf: target, encoding: .utf8)
        try writeTextIfChanged(
            ManagedBlockEditor.remove(existing: existing, identifier: destination.markerIdentifier),
            existing: existing,
            to: target
        )
    }

    // MARK: - Skills

    private struct SkillReceipt: Codable {
        let links: [String: String]
    }

    private func skillTargetRoot(_ project: LoadedProject, _ destination: ProjectionDestination) -> URL {
        project.rootURL.appendingPathComponent(destination.skillsDirectory, isDirectory: true)
    }

    private func skillReceiptURL(_ project: LoadedProject, _ destination: ProjectionDestination) -> URL {
        let suffix = switch destination.client {
        case .smartWork: "-smartwork"
        case .dcc: "-dcc"
        case .codex, .claudeCode: ""
        case .custom: "-\(safeName(destination.markerIdentifier))"
        }
        return skillTargetRoot(project, destination).appendingPathComponent(".project-standard\(suffix)-links.json")
    }

    private func skillLinkName(scheme: Scheme, skillName: String, destination: ProjectionDestination) -> String {
        let clientPart = switch destination.client {
        case .smartWork: "-smartwork"
        case .dcc: "-dcc"
        case .codex, .claudeCode: ""
        case .custom: "-\(safeName(destination.markerIdentifier))"
        }
        return "project-standard\(clientPart)-\(safeName(scheme.id))-\(skillName)"
    }

    private func canonicalSkills(in scheme: Scheme) -> [(name: String, url: URL)] {
        guard let root = source(.skills, in: scheme), root.exists else { return [] }
        let entries = (try? fileManager.contentsOfDirectory(at: root.url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return entries.compactMap { url in
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue,
                  fileManager.fileExists(atPath: url.appendingPathComponent("SKILL.md").path) else { return nil }
            return (safeName(url.lastPathComponent), url)
        }.sorted { $0.name < $1.name }
    }

    private func applySkills(project: LoadedProject, scheme: Scheme, destination: ProjectionDestination) throws {
        try cancelSkills(project: project, destination: destination)
        let skills = canonicalSkills(in: scheme)
        guard !skills.isEmpty else { return }
        let root = skillTargetRoot(project, destination)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        var links: [String: String] = [:]
        for skill in skills {
            let name = skillLinkName(scheme: scheme, skillName: skill.name, destination: destination)
            let target = root.appendingPathComponent(name)
            let relative = relativePath(from: root, to: skill.url)
            if fileManager.fileExists(atPath: target.path) {
                let existing = try fileManager.destinationOfSymbolicLink(atPath: target.path)
                guard existing == relative else {
                    throw ProjectionEngineError.targetConflict("Skill 目标已存在且不属于本应用：\(target.path)")
                }
            } else {
                let temporary = root.appendingPathComponent(".\(name).\(UUID().uuidString).tmp")
                try fileManager.createSymbolicLink(atPath: temporary.path, withDestinationPath: relative)
                try fileManager.moveItem(at: temporary, to: target)
            }
            links[name] = relative
        }
        try writeJSON(SkillReceipt(links: links), to: skillReceiptURL(project, destination))
    }

    private func cancelSkills(project: LoadedProject, destination: ProjectionDestination) throws {
        let receiptURL = skillReceiptURL(project, destination)
        guard let data = try? Data(contentsOf: receiptURL),
              let receipt = try? JSONDecoder().decode(SkillReceipt.self, from: data) else { return }
        let root = skillTargetRoot(project, destination)
        var allRemoved = true
        for (name, expected) in receipt.links {
            let target = root.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: target.path) else { continue }
            guard (try? fileManager.destinationOfSymbolicLink(atPath: target.path)) == expected else {
                allRemoved = false
                continue
            }
            try fileManager.removeItem(at: target)
        }
        if allRemoved { try? fileManager.removeItem(at: receiptURL) }
    }

    private func validateSkills(project: LoadedProject, scheme: Scheme, destination: ProjectionDestination) -> Bool {
        let skills = canonicalSkills(in: scheme)
        guard !skills.isEmpty else { return false }
        let root = skillTargetRoot(project, destination)
        return skills.allSatisfy { skill in
            let name = skillLinkName(scheme: scheme, skillName: skill.name, destination: destination)
            return (try? fileManager.destinationOfSymbolicLink(atPath: root.appendingPathComponent(name).path)) == relativePath(from: root, to: skill.url)
        }
    }

    // MARK: - MCP

    private func loadMCP(from source: CategorySource?) throws -> [String: Any] {
        guard let source, source.exists else { return [:] }
        let object = try jsonObject(at: source.url)
        guard let root = object as? [String: Any] else {
            throw ProjectionEngineError.invalidShape("Tools/MCP 根节点必须是对象")
        }
        guard let value = root["mcpServers"] else { return [:] }
        guard let servers = value as? [String: Any] else {
            throw ProjectionEngineError.invalidShape("mcpServers 必须是对象")
        }
        for (name, value) in servers where !(value is [String: Any]) {
            throw ProjectionEngineError.invalidShape("MCP \(name) 的配置必须是对象")
        }
        return servers
    }

    private var codexMCPStart: String { "# project-standard:start mcp" }
    private var codexMCPEnd: String { "# project-standard:end mcp" }
    private var codexHooksStart: String { "# project-standard:start hooks" }
    private var codexHooksEnd: String { "# project-standard:end hooks" }
    private var codexPermissionsStart: String { "# project-standard:start permissions" }
    private var codexPermissionsEnd: String { "# project-standard:end permissions" }

    private func codexConfigURL(_ project: LoadedProject) -> URL {
        project.rootURL.appendingPathComponent(".codex/config.toml")
    }

    private func codexRulesURL(_ project: LoadedProject) -> URL {
        project.rootURL.appendingPathComponent(".codex/rules/project-standard.rules")
    }

    private func codexMCPBlock(scheme: Scheme, servers: [String: Any]) -> String {
        guard !servers.isEmpty else { return "" }
        var lines = [codexMCPStart]
        for name in servers.keys.sorted() {
            guard let raw = servers[name] as? [String: Any] else { continue }
            let normalized = normalizeMCPForCodex(raw)
            lines.append("[mcp_servers.\(tomlQuoted("project-standard.\(safeName(scheme.id)).\(safeName(name))"))]")
            for key in normalized.keys.sorted() where key != "env" {
                if let value = tomlValue(normalized[key]) { lines.append("\(key) = \(value)") }
            }
            if let env = normalized["env"] as? [String: Any], !env.isEmpty {
                lines.append("[mcp_servers.\(tomlQuoted("project-standard.\(safeName(scheme.id)).\(safeName(name))")).env]")
                for key in env.keys.sorted() {
                    if let value = tomlValue(env[key]) { lines.append("\(tomlQuoted(key)) = \(value)") }
                }
            }
            lines.append("")
        }
        lines.append(codexMCPEnd)
        return lines.joined(separator: "\n")
    }

    private func normalizeMCPForCodex(_ raw: [String: Any]) -> [String: Any] {
        var result = raw
        result.removeValue(forKey: "type")
        if result["http_headers"] == nil, let headers = result.removeValue(forKey: "headers") {
            result["http_headers"] = headers
        }
        return result
    }

    private func applyCodexMCP(project: LoadedProject, scheme: Scheme, servers: [String: Any]) throws {
        let target = codexConfigURL(project)
        let existing = (try? String(contentsOf: target, encoding: .utf8)) ?? ""
        try requireCompleteBlock(existing, start: codexMCPStart, end: codexMCPEnd, target: target)
        let cleaned = removeBlock(existing, start: codexMCPStart, end: codexMCPEnd)
        let output = appendBlock(codexMCPBlock(scheme: scheme, servers: servers), to: cleaned)
        try writeTextIfChanged(output, existing: existing, to: target)
    }

    private func claudeMCPURL(_ project: LoadedProject) -> URL {
        project.rootURL.appendingPathComponent(".mcp.json")
    }

    private func mcpKey(scheme: Scheme, name: String) -> String {
        "project-standard.\(safeName(scheme.id)).\(safeName(name))"
    }

    private func applyClaudeMCP(project: LoadedProject, scheme: Scheme, servers: [String: Any]) throws {
        let target = claudeMCPURL(project)
        if servers.isEmpty && !fileManager.fileExists(atPath: target.path) { return }
        var root = try loadJSONObjectIfPresent(at: target)
        if root["mcpServers"] != nil, !(root["mcpServers"] is [String: Any]) {
            throw ProjectionEngineError.invalidShape("mcpServers 必须是对象：\(target.path)")
        }
        var current = root["mcpServers"] as? [String: Any] ?? [:]

        // Remove only unchanged values previously projected from any scheme in this project.
        for oldScheme in project.schemes {
            guard let oldServers = try? loadMCP(from: source(.toolsMcp, in: oldScheme)) else { continue }
            for (name, expected) in oldServers {
                let key = mcpKey(scheme: oldScheme, name: name)
                if let actual = current[key], jsonEqual(actual, expected) { current.removeValue(forKey: key) }
            }
        }
        for (name, value) in servers {
            let key = mcpKey(scheme: scheme, name: name)
            if let existing = current[key], !jsonEqual(existing, value) {
                throw ProjectionEngineError.targetConflict("MCP 键已存在且内容不同：\(key)")
            }
            current[key] = value
        }
        if current.isEmpty { root.removeValue(forKey: "mcpServers") } else { root["mcpServers"] = current }
        try writeJSONObject(root, to: target)
    }

    private func cancelClaudeMCP(project: LoadedProject, scheme: Scheme, servers: [String: Any]) throws {
        let target = claudeMCPURL(project)
        guard fileManager.fileExists(atPath: target.path) else { return }
        var root = try loadJSONObjectIfPresent(at: target)
        var current = root["mcpServers"] as? [String: Any] ?? [:]
        for (name, expected) in servers {
            let key = mcpKey(scheme: scheme, name: name)
            if let actual = current[key], jsonEqual(actual, expected) { current.removeValue(forKey: key) }
        }
        if current.isEmpty { root.removeValue(forKey: "mcpServers") } else { root["mcpServers"] = current }
        try writeJSONObject(root, to: target)
    }

    private func validateClaudeMCP(project: LoadedProject, scheme: Scheme, servers: [String: Any]) -> Bool {
        guard let root = try? loadJSONObjectIfPresent(at: claudeMCPURL(project)),
              let current = root["mcpServers"] as? [String: Any] else { return false }
        return servers.allSatisfy { name, expected in
            current[mcpKey(scheme: scheme, name: name)].map { jsonEqual($0, expected) } ?? false
        }
    }

    // MARK: - Permissions and hooks

    private struct PermissionsHooks {
        let permissions: [String: Any]
        let hooks: [String: Any]
        var hasPermissions: Bool { permissions.values.contains(where: Self.hasContent) }
        var hasHooks: Bool { hooks.values.contains(where: Self.hasContent) }
        var isEmpty: Bool { !hasPermissions && !hasHooks }

        static func hasContent(_ value: Any) -> Bool {
            if let value = value as? [Any] { return !value.isEmpty }
            if let value = value as? [String: Any] { return value.values.contains(where: hasContent) }
            if let value = value as? String { return !value.isEmpty }
            return !(value is NSNull)
        }
    }

    private struct ClaudeSettingsReceipt: Codable {
        var permissions: [String: [String]]
        var hooks: [String: [JSONValue]]
    }

    private func loadPermissionsHooks(from source: CategorySource?) throws -> PermissionsHooks {
        guard let source, source.exists else { return PermissionsHooks(permissions: [:], hooks: [:]) }
        let object = try jsonObject(at: source.url)
        guard let root = object as? [String: Any] else {
            throw ProjectionEngineError.invalidShape("权限/Hooks 根节点必须是对象")
        }
        let permissions = root["permissions"] as? [String: Any] ?? [:]
        let hooks = root["hooks"] as? [String: Any] ?? [:]
        return PermissionsHooks(permissions: permissions, hooks: hooks)
    }

    private func claudeSettingsURL(_ project: LoadedProject) -> URL {
        project.rootURL.appendingPathComponent(".claude/settings.json")
    }

    private func claudeSettingsReceiptURL(_ project: LoadedProject) -> URL {
        project.rootURL.appendingPathComponent(".claude/.project-standard-settings.json")
    }

    private func applyClaudeSettings(project: LoadedProject, permissionsHooks: PermissionsHooks) throws {
        try cancelClaudeSettings(project: project)
        guard !permissionsHooks.isEmpty else { return }
        let target = claudeSettingsURL(project)
        var root = try loadJSONObjectIfPresent(at: target)
        if root["permissions"] != nil, !(root["permissions"] is [String: Any]) {
            throw ProjectionEngineError.invalidShape("permissions 必须是对象：\(target.path)")
        }
        if root["hooks"] != nil, !(root["hooks"] is [String: Any]) {
            throw ProjectionEngineError.invalidShape("hooks 必须是对象：\(target.path)")
        }
        var currentPermissions = root["permissions"] as? [String: Any] ?? [:]
        var currentHooks = root["hooks"] as? [String: Any] ?? [:]
        var receiptPermissions: [String: [String]] = [:]
        var receiptHooks: [String: [JSONValue]] = [:]

        for key in ["allow", "ask", "deny", "additionalDirectories"] {
            guard let desired = permissionsHooks.permissions[key] as? [String] else { continue }
            var current = currentPermissions[key] as? [String] ?? []
            let additions = desired.filter { !current.contains($0) }
            current.append(contentsOf: additions)
            if !current.isEmpty { currentPermissions[key] = current }
            if !additions.isEmpty { receiptPermissions[key] = additions }
        }
        for (event, rawGroups) in permissionsHooks.hooks {
            guard let desired = rawGroups as? [Any] else {
                throw ProjectionEngineError.invalidShape("Hooks.\(event) 必须是数组")
            }
            var current = currentHooks[event] as? [Any] ?? []
            var additions: [JSONValue] = []
            for group in desired where !current.contains(where: { jsonEqual($0, group) }) {
                current.append(group)
                additions.append(try JSONValue(any: group))
            }
            if !current.isEmpty { currentHooks[event] = current }
            if !additions.isEmpty { receiptHooks[event] = additions }
        }
        if !currentPermissions.isEmpty { root["permissions"] = currentPermissions }
        if !currentHooks.isEmpty { root["hooks"] = currentHooks }
        try writeJSONObject(root, to: target)
        try writeJSON(ClaudeSettingsReceipt(permissions: receiptPermissions, hooks: receiptHooks), to: claudeSettingsReceiptURL(project))
    }

    private func cancelClaudeSettings(project: LoadedProject) throws {
        let receiptURL = claudeSettingsReceiptURL(project)
        guard let receiptData = try? Data(contentsOf: receiptURL),
              let receipt = try? JSONDecoder().decode(ClaudeSettingsReceipt.self, from: receiptData) else { return }
        let target = claudeSettingsURL(project)
        guard fileManager.fileExists(atPath: target.path) else { return }
        var root = try loadJSONObjectIfPresent(at: target)
        var permissions = root["permissions"] as? [String: Any] ?? [:]
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for (key, additions) in receipt.permissions {
            var current = permissions[key] as? [String] ?? []
            current.removeAll { additions.contains($0) }
            if current.isEmpty { permissions.removeValue(forKey: key) } else { permissions[key] = current }
        }
        for (event, additions) in receipt.hooks {
            var current = hooks[event] as? [Any] ?? []
            current.removeAll { item in additions.contains { jsonEqual($0.any, item) } }
            if current.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = current }
        }
        if permissions.isEmpty { root.removeValue(forKey: "permissions") } else { root["permissions"] = permissions }
        if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
        try writeJSONObject(root, to: target)
        try? fileManager.removeItem(at: receiptURL)
    }

    private func validateClaudeSettings(project: LoadedProject, configuration: PermissionsHooks) -> Bool {
        guard let root = try? loadJSONObjectIfPresent(at: claudeSettingsURL(project)) else { return false }
        let permissions = root["permissions"] as? [String: Any] ?? [:]
        let hooks = root["hooks"] as? [String: Any] ?? [:]
        for key in ["allow", "ask", "deny", "additionalDirectories"] {
            guard let desired = configuration.permissions[key] as? [String] else { continue }
            let current = permissions[key] as? [String] ?? []
            if !desired.allSatisfy(current.contains) { return false }
        }
        for (event, raw) in configuration.hooks {
            guard let desired = raw as? [Any], let current = hooks[event] as? [Any] else { return false }
            if !desired.allSatisfy({ item in current.contains(where: { jsonEqual($0, item) }) }) { return false }
        }
        return !configuration.isEmpty
    }

    private func codexHooksBlock(hooks: [String: Any]) -> String {
        guard !hooks.isEmpty else { return "" }
        var lines = [codexHooksStart]
        for event in hooks.keys.sorted() {
            guard let groups = hooks[event] as? [Any] else { continue }
            for rawGroup in groups {
                guard let group = rawGroup as? [String: Any] else { continue }
                lines.append("[[hooks.\(event)]]")
                for key in group.keys.sorted() where key != "hooks" {
                    if let value = tomlValue(group[key]) { lines.append("\(tomlKey(key)) = \(value)") }
                }
                if let handlers = group["hooks"] as? [Any] {
                    for rawHandler in handlers {
                        guard let handler = rawHandler as? [String: Any] else { continue }
                        lines.append("[[hooks.\(event).hooks]]")
                        for key in handler.keys.sorted() {
                            if let value = tomlValue(handler[key]) { lines.append("\(tomlKey(key)) = \(value)") }
                        }
                    }
                }
                lines.append("")
            }
        }
        lines.append(codexHooksEnd)
        return lines.joined(separator: "\n")
    }

    private func applyCodexHooks(project: LoadedProject, scheme: Scheme, hooks: [String: Any]) throws {
        let target = codexConfigURL(project)
        let existing = (try? String(contentsOf: target, encoding: .utf8)) ?? ""
        try requireCompleteBlock(existing, start: codexHooksStart, end: codexHooksEnd, target: target)
        let cleaned = removeBlock(existing, start: codexHooksStart, end: codexHooksEnd)
        let output = appendBlock(codexHooksBlock(hooks: hooks), to: cleaned)
        try writeTextIfChanged(output, existing: existing, to: target)
    }

    private struct CodexPermissionRule {
        let pattern: [String]
        let decision: String
    }

    private func codexPermissionRules(_ permissions: [String: Any]) -> (rules: [CodexPermissionRule], complete: Bool) {
        var result: [CodexPermissionRule] = []
        var complete = true
        let supported = Set(["allow", "ask", "deny"])
        for (key, rawValue) in permissions {
            guard let values = rawValue as? [String] else {
                if PermissionsHooks.hasContent(rawValue) { complete = false }
                continue
            }
            guard supported.contains(key) else {
                if !values.isEmpty { complete = false }
                continue
            }
            let decision = key == "allow" ? "allow" : (key == "ask" ? "prompt" : "forbidden")
            for value in values {
                guard value.hasPrefix("Bash("), value.hasSuffix(")") else {
                    complete = false
                    continue
                }
                let command = String(value.dropFirst(5).dropLast())
                var tokens = shellTokens(command)
                if tokens.last == "*" { tokens.removeLast() }
                guard !tokens.isEmpty, !tokens.contains(where: { $0.contains("*") }) else {
                    complete = false
                    continue
                }
                result.append(CodexPermissionRule(pattern: tokens, decision: decision))
            }
        }
        return (result, complete)
    }

    private func codexPermissionsBlock(_ rules: [CodexPermissionRule]) -> String {
        guard !rules.isEmpty else { return "" }
        var lines = [codexPermissionsStart]
        for rule in rules {
            lines.append("prefix_rule(")
            lines.append("    pattern = [\(rule.pattern.map(tomlQuoted).joined(separator: ", "))],")
            lines.append("    decision = \(tomlQuoted(rule.decision)),")
            lines.append("    justification = \(tomlQuoted("Project Standard 项目权限规则")),")
            lines.append(")")
            lines.append("")
        }
        lines.append(codexPermissionsEnd)
        return lines.joined(separator: "\n")
    }

    private func applyCodexPermissions(project: LoadedProject, permissions: [String: Any]) throws {
        let target = codexRulesURL(project)
        let existing = (try? String(contentsOf: target, encoding: .utf8)) ?? ""
        let hasStart = existing.contains(codexPermissionsStart)
        let hasEnd = existing.contains(codexPermissionsEnd)
        guard hasStart == hasEnd else {
            throw ProjectionEngineError.targetConflict("受管权限区块不完整，请先检查：\(target.path)")
        }
        let cleaned = removeBlock(existing, start: codexPermissionsStart, end: codexPermissionsEnd)
        let mapped = codexPermissionRules(permissions)
        let output = appendBlock(codexPermissionsBlock(mapped.rules), to: cleaned)
        try writeTextIfChanged(output, existing: existing, to: target)
    }

    private func shellTokens(_ command: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false
        for character in command {
            if escaped {
                current.append(character)
                escaped = false
            } else if character == "\\" && quote != "'" {
                escaped = true
            } else if let activeQuote = quote {
                if character == activeQuote { quote = nil } else { current.append(character) }
            } else if character == "'" || character == "\"" {
                quote = character
            } else if character.isWhitespace {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        if escaped { current.append("\\") }
        if !current.isEmpty { tokens.append(current) }
        return quote == nil ? tokens : []
    }

    private func transactionTargets(
        project: LoadedProject,
        scheme: Scheme,
        destination: ProjectionDestination
    ) -> [URL] {
        let client = destination.client
        var targets = Set<URL>()
        targets.insert(project.rootURL.appendingPathComponent(destination.instructionFile))

        let skillRoot = skillTargetRoot(project, destination)
        let receiptURL = skillReceiptURL(project, destination)
        targets.insert(receiptURL)
        if let data = try? Data(contentsOf: receiptURL),
           let receipt = try? JSONDecoder().decode(SkillReceipt.self, from: data) {
            for name in receipt.links.keys { targets.insert(skillRoot.appendingPathComponent(name)) }
        }
        for skill in canonicalSkills(in: scheme) {
            let name = skillLinkName(scheme: scheme, skillName: skill.name, destination: destination)
            targets.insert(skillRoot.appendingPathComponent(name))
        }

        switch client {
        case .codex:
            targets.insert(codexConfigURL(project))
            targets.insert(codexRulesURL(project))
        case .claudeCode:
            targets.insert(claudeMCPURL(project))
            targets.insert(claudeSettingsURL(project))
            targets.insert(claudeSettingsReceiptURL(project))
        case .smartWork:
            break
        case .dcc:
            break
        case .custom:
            break
        }
        return targets.sorted { $0.path < $1.path }
    }

    // MARK: - File and format helpers

    private func source(_ category: FoundationCategory, in scheme: Scheme) -> CategorySource? {
        scheme.categories.first { $0.category == category }
    }

    private func jsonObject(at url: URL) throws -> Any {
        do { return try JSONSerialization.jsonObject(with: Data(contentsOf: url)) }
        catch { throw ProjectionEngineError.malformedJSON(url.path) }
    }

    private func loadJSONObjectIfPresent(at url: URL) throws -> [String: Any] {
        guard fileManager.fileExists(atPath: url.path) else { return [:] }
        guard let root = try jsonObject(at: url) as? [String: Any] else {
            throw ProjectionEngineError.invalidShape("配置根节点必须是对象：\(url.path)")
        }
        return root
    }

    private func writeJSONObject(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        let output = data + Data("\n".utf8)
        if (try? Data(contentsOf: url)) == output { return }
        try ensureParent(of: url)
        try output.write(to: url, options: .atomic)
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try ensureParent(of: url)
        try (encoder.encode(value) + Data("\n".utf8)).write(to: url, options: .atomic)
    }

    private func writeTextIfChanged(_ output: String, existing: String, to url: URL) throws {
        guard output != existing else { return }
        if output.isEmpty {
            if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
            return
        }
        try ensureParent(of: url)
        try Data(output.utf8).write(to: url, options: .atomic)
    }

    private func ensureParent(of url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    private func appendBlock(_ block: String, to existing: String) -> String {
        let clean = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !block.isEmpty else { return clean.isEmpty ? "" : clean + "\n" }
        return clean.isEmpty ? block + "\n" : clean + "\n\n" + block + "\n"
    }

    private func removeTextBlock(at url: URL, start: String, end: String) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        let existing = try String(contentsOf: url, encoding: .utf8)
        try requireCompleteBlock(existing, start: start, end: end, target: url)
        try writeTextIfChanged(removeBlock(existing, start: start, end: end), existing: existing, to: url)
    }

    private func requireCompleteBlock(_ text: String, start: String, end: String, target: URL) throws {
        guard text.contains(start) == text.contains(end) else {
            throw ProjectionEngineError.targetConflict("受管配置区块不完整，请先检查：\(target.path)")
        }
    }

    private func removeBlock(_ text: String, start: String, end: String) -> String {
        guard let startRange = text.range(of: start),
              let endRange = text.range(of: end, range: startRange.upperBound..<text.endIndex) else { return text }
        var output = text
        output.removeSubrange(startRange.lowerBound..<endRange.upperBound)
        while output.contains("\n\n\n") { output = output.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        let clean = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "" : clean + "\n"
    }

    private func validateTextBlock(at url: URL, block: String) -> Bool {
        guard !block.isEmpty, let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        return text.contains(block)
    }

    private func relativePath(from directory: URL, to target: URL) -> String {
        let from = directory.standardizedFileURL.pathComponents
        let to = target.standardizedFileURL.pathComponents
        var index = 0
        while index < min(from.count, to.count), from[index] == to[index] { index += 1 }
        return Array(repeating: "..", count: from.count - index).joined(separator: "/")
            + (from.count == index ? "" : "/")
            + to[index...].joined(separator: "/")
    }

    private func safeName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let mapped = value.unicodeScalars.map { allowed.contains($0) ? Character(String($0).lowercased()) : "-" }
        return String(mapped).replacingOccurrences(of: "--", with: "-")
    }

    private func jsonEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        guard JSONSerialization.isValidJSONObject([lhs]), JSONSerialization.isValidJSONObject([rhs]),
              let left = try? JSONSerialization.data(withJSONObject: [lhs], options: [.sortedKeys]),
              let right = try? JSONSerialization.data(withJSONObject: [rhs], options: [.sortedKeys]) else { return false }
        return left == right
    }

    private func tomlKey(_ value: String) -> String {
        value.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil ? value : tomlQuoted(value)
    }

    private func tomlQuoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n") + "\""
    }

    private func tomlValue(_ value: Any?) -> String? {
        switch value {
        case let value as String: return tomlQuoted(value)
        case let value as Bool: return value ? "true" : "false"
        case let value as NSNumber: return value.stringValue
        case let value as [Any]: return "[" + value.compactMap(tomlValue).joined(separator: ", ") + "]"
        case let value as [String: Any]:
            return "{ " + value.keys.sorted().compactMap { key in tomlValue(value[key]).map { "\(tomlKey(key)) = \($0)" } }.joined(separator: ", ") + " }"
        default: return nil
        }
    }
}

private enum JSONValue: Codable, Equatable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null

    init(any: Any) throws {
        switch any {
        case let value as String: self = .string(value)
        case let value as Bool: self = .bool(value)
        case let value as NSNumber: self = .number(value.doubleValue)
        case let value as [String: Any]: self = .object(try value.mapValues { try JSONValue(any: $0) })
        case let value as [Any]: self = .array(try value.map { try JSONValue(any: $0) })
        case is NSNull: self = .null
        default: throw ProjectionEngineError.invalidShape("配置包含不支持的 JSON 值")
        }
    }

    var any: Any {
        switch self {
        case .string(let value): value
        case .number(let value): value
        case .bool(let value): value
        case .object(let value): value.mapValues(\.any)
        case .array(let value): value.map(\.any)
        case .null: NSNull()
        }
    }
}

private final class ProjectionTransaction {
    private enum State {
        case missing
        case file(Data, NSNumber?)
        case symlink(String)
        case directory
    }

    private struct Snapshot {
        let url: URL
        let state: State
    }

    private let fileManager: FileManager
    private let snapshots: [Snapshot]
    private let initiallyMissingDirectories: [URL]

    init(targets: [URL], rootURL: URL, fileManager: FileManager) throws {
        self.fileManager = fileManager
        self.snapshots = try targets.map { url in
            if let destination = try? fileManager.destinationOfSymbolicLink(atPath: url.path) {
                return Snapshot(url: url, state: .symlink(destination))
            }
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                return Snapshot(url: url, state: .missing)
            }
            if isDirectory.boolValue { return Snapshot(url: url, state: .directory) }
            let data = try Data(contentsOf: url)
            let permissions = (try? fileManager.attributesOfItem(atPath: url.path)[.posixPermissions]) as? NSNumber
            return Snapshot(url: url, state: .file(data, permissions))
        }

        var missing = Set<URL>()
        for target in targets {
            var directory = target.deletingLastPathComponent()
            while directory.path.hasPrefix(rootURL.path), directory.standardizedFileURL != rootURL.standardizedFileURL {
                var isDirectory: ObjCBool = false
                if !fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
                    missing.insert(directory)
                }
                directory.deleteLastPathComponent()
            }
        }
        self.initiallyMissingDirectories = missing.sorted {
            $0.pathComponents.count > $1.pathComponents.count
        }
    }

    func rollback() throws {
        for snapshot in snapshots.reversed() {
            switch snapshot.state {
            case .missing:
                try removeCurrentIfSafe(at: snapshot.url)
            case .file(let data, let permissions):
                if (try? Data(contentsOf: snapshot.url)) == data { continue }
                try replaceCurrent(at: snapshot.url)
                try fileManager.createDirectory(
                    at: snapshot.url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: snapshot.url, options: .atomic)
                if let permissions {
                    try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: snapshot.url.path)
                }
            case .symlink(let destination):
                if (try? fileManager.destinationOfSymbolicLink(atPath: snapshot.url.path)) == destination {
                    continue
                }
                try replaceCurrent(at: snapshot.url)
                try fileManager.createDirectory(
                    at: snapshot.url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fileManager.createSymbolicLink(atPath: snapshot.url.path, withDestinationPath: destination)
            case .directory:
                var isDirectory: ObjCBool = false
                if !fileManager.fileExists(atPath: snapshot.url.path, isDirectory: &isDirectory) {
                    try fileManager.createDirectory(at: snapshot.url, withIntermediateDirectories: true)
                } else if !isDirectory.boolValue {
                    throw ProjectionEngineError.targetConflict("回滚目标被外部内容占用：\(snapshot.url.path)")
                }
            }
        }

        for directory in initiallyMissingDirectories {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            let children = try fileManager.contentsOfDirectory(atPath: directory.path)
            if children.isEmpty { try fileManager.removeItem(at: directory) }
        }
    }

    private func replaceCurrent(at url: URL) throws {
        if (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil {
            try fileManager.removeItem(at: url)
            return
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }
        if isDirectory.boolValue {
            let children = try fileManager.contentsOfDirectory(atPath: url.path)
            guard children.isEmpty else {
                throw ProjectionEngineError.targetConflict("回滚目标目录包含外部内容：\(url.path)")
            }
        }
        try fileManager.removeItem(at: url)
    }

    private func removeCurrentIfSafe(at url: URL) throws {
        try replaceCurrent(at: url)
    }
}
