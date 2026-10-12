import AppKit
import Combine
import Darwin
import Foundation
import ProjectStandardCore

struct ConnectionRowState: Identifiable {
    let profile: ConnectionProfile
    var enabled: Bool
    var status: String
    var validatedCategories: Int
    var hasIssue: Bool

    var id: String { profile.id }
}

struct CustomClientEditorState: Equatable {
    let id: String?
    var name: String
    var instructionFile: String
    var skillsDirectory: String

    static let new = CustomClientEditorState(
        id: nil,
        name: "",
        instructionFile: "AGENTS.md",
        skillsDirectory: ".agents/skills"
    )
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var project: LoadedProject?
    @Published var selectedSchemeID: String?
    @Published var detailSchemeID: String?
    @Published private(set) var connections: [ConnectionRowState] = []
    @Published private(set) var footerMessage = "选择一个项目开始"
    @Published private(set) var hasError = false
    @Published private(set) var codexNeedsConfigurationAccess = false
    @Published var customClientEditor: CustomClientEditorState?

    private let loader = ProjectLoader()
    private let initializer = ProjectInitializer()
    private let projector = ProjectionEngine()
    private let accessStore: ProjectAccessStore
    private let codexAccessStore: ProjectAccessStore
    private let bindingStore: BindingStore
    private let customClientStore: CustomClientStore
    private var bindings: [String: BindingRecord]
    private var customClients: [CustomClientDefinition]
    private var projectWatcher: ProjectFileWatcher?
    private var codexMonitor: CodexAppServerMonitor?
    private var codexSnapshot: CodexConnectionSnapshot?
    private var codexConfigRoot: URL?
    private var connectionRefreshGeneration = 0
    private var lastProjectFingerprint: String?
    private var connectionErrors: [String: String] = [:]

    init() {
        let supportRoot = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("ProjectStandard", isDirectory: true)
        let accessStore = ProjectAccessStore(applicationSupportURL: supportRoot)
        let codexAccessStore = ProjectAccessStore(
            applicationSupportURL: supportRoot,
            bookmarkName: "codex-config-bookmark.data"
        )
        let bindingStore = BindingStore(fileURL: supportRoot.appendingPathComponent("bindings.json"))
        let customClientStore = CustomClientStore(fileURL: supportRoot.appendingPathComponent("custom-clients.json"))
        self.accessStore = accessStore
        self.codexAccessStore = codexAccessStore
        self.bindingStore = bindingStore
        self.customClientStore = customClientStore
        self.bindings = bindingStore.load()
        self.customClients = customClientStore.load()
        self.codexConfigRoot = codexAccessStore.restore()

        if let argumentURL = Self.projectArgumentURL() {
            accessStore.useWithoutPersisting(argumentURL)
            loadProject(argumentURL)
        } else if let restored = accessStore.restore() {
            loadProject(restored)
        } else {
            refreshConnections()
            startCodexMonitor(cwdURL: nil)
        }
    }

    var selectedScheme: Scheme? {
        guard let selectedSchemeID else { return project?.schemes.first }
        return project?.schemes.first { $0.id == selectedSchemeID }
    }

    var detailScheme: Scheme? {
        guard let detailSchemeID else { return nil }
        return project?.schemes.first { $0.id == detailSchemeID }
    }

    func selectScheme(_ id: String) {
        selectedSchemeID = id
    }

    func showScheme(_ id: String) {
        detailSchemeID = id
    }

    func closeScheme() {
        detailSchemeID = nil
    }

    func beginAddingCustomClient() {
        customClientEditor = .new
    }

    func editCustomClient(_ profile: ConnectionProfile) {
        guard let definition = profile.customDefinition else { return }
        guard !bindings.values.contains(where: { $0.profileID == profile.id }) else {
            footerMessage = "请先关闭该自定义端，再修改配置"
            hasError = true
            return
        }
        customClientEditor = CustomClientEditorState(
            id: definition.id,
            name: definition.name,
            instructionFile: definition.instructionFile,
            skillsDirectory: definition.skillsDirectory
        )
    }

    func updateCustomClientName(_ value: String) {
        customClientEditor?.name = value
    }

    func updateCustomInstructionFile(_ value: String) {
        customClientEditor?.instructionFile = value
    }

    func updateCustomSkillsDirectory(_ value: String) {
        customClientEditor?.skillsDirectory = value
    }

    func closeCustomClientEditor() {
        customClientEditor = nil
    }

    func saveCustomClient() {
        guard let editor = customClientEditor else { return }
        do {
            let definition = try CustomClientDefinition(
                id: editor.id ?? UUID().uuidString.lowercased(),
                name: editor.name,
                instructionFile: editor.instructionFile,
                skillsDirectory: editor.skillsDirectory
            )
            if let index = customClients.firstIndex(where: { $0.id == definition.id }) {
                customClients[index] = definition
            } else {
                customClients.append(definition)
            }
            try customClientStore.save(customClients)
            customClientEditor = nil
            footerMessage = editor.id == nil ? "已添加自定义端" : "自定义端已更新"
            hasError = false
            refreshConnections()
        } catch {
            report(error)
        }
    }

    func deleteCustomClient() {
        guard let editor = customClientEditor, let id = editor.id else { return }
        let profileID = "custom-\(id)"
        guard !bindings.values.contains(where: { $0.profileID == profileID }) else {
            footerMessage = "请先关闭该自定义端，再删除"
            hasError = true
            return
        }
        do {
            customClients.removeAll { $0.id == id }
            try customClientStore.save(customClients)
            customClientEditor = nil
            footerMessage = "已删除自定义端"
            hasError = false
            refreshConnections()
        } catch {
            report(error)
        }
    }

    func chooseProject() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "选择项目目录"
        panel.message = "选择任意项目目录；尚未配置时会创建默认项目规范"
        panel.prompt = "选择"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try accessStore.save(url)
            let created = try initializer.initializeIfNeeded(rootURL: url)
            loadProject(
                url,
                successMessage: created ? "已创建默认项目规范 · 点击方案编辑内容" : nil
            )
        } catch {
            report(error)
        }
    }

    func chooseCodexConfiguration() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "授权 Codex 配置目录"
        panel.message = "选择 .codex 目录，用于读取账号/Provider 事件；应用不会读取或保存凭据内容。"
        panel.prompt = "授权"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = Self.userHomeURL()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard url.lastPathComponent == ".codex" ||
                FileManager.default.fileExists(atPath: url.appendingPathComponent("config.toml").path) else {
            footerMessage = "请选择 .codex 或包含 config.toml 的目录"
            hasError = true
            return
        }
        do {
            try codexAccessStore.save(url)
            codexConfigRoot = url
            codexNeedsConfigurationAccess = false
            startCodexMonitor(cwdURL: project?.rootURL)
            footerMessage = "Codex 配置已授权 · 正在连接"
            hasError = false
        } catch {
            report(error)
        }
    }

    func reloadProject() {
        guard let rootURL = project?.rootURL else { return }
        loadProject(rootURL, preserveSelection: true)
    }

    func refreshConnections() {
        connectionRefreshGeneration += 1
        let generation = connectionRefreshGeneration
        let snapshot = codexSnapshot
        let customClients = customClients
        Task { [weak self] in
            let profiles = await Task.detached(priority: .utility) {
                ConnectionDetector(preferBundledCodex: true, customClients: customClients)
                    .discover(codexSnapshot: snapshot)
            }.value
            guard let self, self.connectionRefreshGeneration == generation else { return }
            self.applyDiscoveredProfiles(profiles)
        }
    }

    private func applyDiscoveredProfiles(_ profiles: [ConnectionProfile]) {
        guard let project else {
            connections = profiles.map {
                ConnectionRowState(
                    profile: $0,
                    enabled: false,
                    status: $0.detail,
                    validatedCategories: 0,
                    hasIssue: $0.capabilities.verification != .verified
                )
            }
            return
        }
        migrateBindingsToCurrentProfiles(profiles, project: project)
        connections = profiles.map { profile in
            let key = BindingStore.key(projectID: project.manifest.projectId, profileID: profile.id)
            guard let binding = bindings[key],
                  let scheme = project.schemes.first(where: { $0.id == binding.schemeID }) else {
                return ConnectionRowState(
                    profile: profile,
                    enabled: false,
                    status: profile.detail,
                    validatedCategories: 0,
                    hasIssue: false
                )
            }
            let validated = projector.validate(project: project, scheme: scheme, profile: profile).count
            let issue = connectionErrors[key]
            let capabilityIssue = profile.capabilities.verification != .verified
            return ConnectionRowState(
                profile: profile,
                enabled: true,
                status: issue.map { "需处理 · \($0)" }
                    ?? (capabilityIssue
                        ? "需复验 · \(profile.capabilities.detail)"
                        : (validated > 0 ? "\(validated)/7 生效 · \(scheme.name)" : "待修复 · \(scheme.name)")),
                validatedCategories: validated,
                hasIssue: issue != nil || capabilityIssue || validated == 0
            )
        }
    }

    func toggleConnection(_ profileID: String) {
        guard let project,
              let index = connections.firstIndex(where: { $0.id == profileID }) else { return }
        let profile = connections[index].profile
        let key = BindingStore.key(projectID: project.manifest.projectId, profileID: profileID)
        do {
            if let removedBinding = bindings[key] {
                let otherBinding = profile.client == .custom ? nil : bindings.values.first {
                    $0.projectID == project.manifest.projectId &&
                    $0.client == profile.client &&
                    $0.profileID != profileID
                }
                if let otherBinding,
                   let scheme = project.schemes.first(where: { $0.id == otherBinding.schemeID }) {
                    _ = try projector.apply(project: project, scheme: scheme, profile: profile)
                } else {
                    let boundScheme = project.schemes.first { $0.id == removedBinding.schemeID } ?? selectedScheme
                    if let boundScheme {
                        try projector.cancel(project: project, scheme: boundScheme, profile: profile)
                    }
                }
                bindings.removeValue(forKey: key)
                connectionErrors.removeValue(forKey: key)
                try bindingStore.save(bindings)
                footerMessage = "已取消 \(profile.client.displayName) 投影"
            } else {
                guard let scheme = selectedScheme else { return }
                let validated = try projector.apply(project: project, scheme: scheme, profile: profile).count
                bindings[key] = BindingRecord(
                    projectID: project.manifest.projectId,
                    profileID: profileID,
                    client: profile.client,
                    schemeID: scheme.id,
                    validatedCategories: validated
                )
                connectionErrors.removeValue(forKey: key)
                try bindingStore.save(bindings)
                footerMessage = "已应用 \(scheme.name) · \(validated)/7 生效"
            }
            hasError = false
            lastProjectFingerprint = projectFingerprint(project.rootURL)
            refreshConnections()
        } catch {
            report(error)
        }
    }

    func openCategory(_ source: CategorySource) {
        guard source.exists else {
            footerMessage = "文件不存在：\(source.relativePath)"
            hasError = true
            return
        }
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: source.url.path, isDirectory: &isDirectory)
        if isDirectory.boolValue {
            NSWorkspace.shared.activateFileViewerSelecting([source.url])
        } else if !NSWorkspace.shared.open(source.url) {
            footerMessage = "无法打开：\(source.relativePath)"
            hasError = true
        }
    }

    func stopProjectAccess() {
        codexMonitor?.stop()
        codexAccessStore.stop()
        accessStore.stop()
    }

    private func loadProject(
        _ rootURL: URL,
        preserveSelection: Bool = false,
        successMessage: String? = nil
    ) {
        do {
            let loaded = try loader.load(rootURL: rootURL)
            let previousSelection = selectedSchemeID
            project = loaded
            selectedSchemeID = preserveSelection && loaded.schemes.contains(where: { $0.id == previousSelection })
                ? previousSelection
                : loaded.schemes.first?.id
            detailSchemeID = nil
            footerMessage = successMessage ?? "项目已加载 · \(loaded.schemes.count) 个方案"
            hasError = false
            connectionErrors = connectionErrors.filter { key, _ in
                key.hasPrefix("\(loaded.manifest.projectId)::")
            }
            refreshConnections()
            lastProjectFingerprint = projectFingerprint(rootURL)
            startMonitoring(rootURL)
            startCodexMonitor(cwdURL: rootURL)
        } catch {
            projectWatcher?.stop()
            projectWatcher = nil
            project = nil
            selectedSchemeID = nil
            detailSchemeID = nil
            report(error)
            refreshConnections()
        }
    }

    private func report(_ error: Error) {
        footerMessage = error.localizedDescription
        hasError = true
    }

    /// Project projections live in the repository and remain valid when a client
    /// changes its authentication method or provider route. Move the switch state
    /// to the newly detected current profile instead of making it appear disabled.
    private func migrateBindingsToCurrentProfiles(_ profiles: [ConnectionProfile], project: LoadedProject) {
        var changed = false
        for profile in profiles {
            let newKey = BindingStore.key(projectID: project.manifest.projectId, profileID: profile.id)
            guard bindings[newKey] == nil, profile.client != .custom else { continue }
            let oldEntry = bindings.first { _, binding in
                binding.projectID == project.manifest.projectId && binding.client == profile.client
            }
            guard let oldEntry else { continue }
            let migratedError = connectionErrors.removeValue(forKey: oldEntry.key)
            bindings.removeValue(forKey: oldEntry.key)
            bindings[newKey] = BindingRecord(
                projectID: project.manifest.projectId,
                profileID: profile.id,
                client: profile.client,
                schemeID: oldEntry.value.schemeID,
                validatedCategories: oldEntry.value.validatedCategories,
                updatedAt: Date()
            )
            if let migratedError { connectionErrors[newKey] = migratedError }
            changed = true
        }
        if changed { try? bindingStore.save(bindings) }
    }

    private func startMonitoring(_ rootURL: URL) {
        projectWatcher?.stop()
        do {
            projectWatcher = try ProjectFileWatcher(rootURL: rootURL) { [weak self] event in
                Task { @MainActor in self?.checkForProjectChanges(force: event.mustRescan) }
            }
        } catch {
            projectWatcher = nil
            footerMessage = "项目已加载 · 文件监听不可用"
            hasError = true
        }
    }

    private func checkForProjectChanges(force: Bool = false) {
        guard let project else { return }
        let fingerprint = projectFingerprint(project.rootURL)
        guard let previous = lastProjectFingerprint else {
            lastProjectFingerprint = fingerprint
            return
        }
        guard force || fingerprint != previous else { return }
        lastProjectFingerprint = fingerprint
        repairEnabledBindings(projectRoot: project.rootURL)
    }

    private func repairEnabledBindings(projectRoot: URL) {
        do {
            let loaded = try loader.load(rootURL: projectRoot)
            project = loaded
            if !loaded.schemes.contains(where: { $0.id == selectedSchemeID }) {
                selectedSchemeID = loaded.schemes.first?.id
            }
            var repaired = 0
            var failed = 0
            let profiles = connections.map(\.profile)
            migrateBindingsToCurrentProfiles(profiles, project: loaded)
            for profile in profiles {
                let key = BindingStore.key(projectID: loaded.manifest.projectId, profileID: profile.id)
                guard let binding = bindings[key],
                      let scheme = loaded.schemes.first(where: { $0.id == binding.schemeID }) else { continue }
                do {
                    let validation = try projector.apply(project: loaded, scheme: scheme, profile: profile)
                    bindings[key]?.validatedCategories = validation.count
                    bindings[key]?.updatedAt = Date()
                    connectionErrors.removeValue(forKey: key)
                    repaired += 1
                } catch {
                    connectionErrors[key] = compactError(error)
                    failed += 1
                }
            }
            try bindingStore.save(bindings)
            lastProjectFingerprint = projectFingerprint(projectRoot)
            refreshConnections()
            if failed > 0 {
                footerMessage = "配置变化 · \(failed) 个接入需处理"
                hasError = true
            } else {
                footerMessage = repaired > 0 ? "配置变化 · 已自动重验" : "配置变化 · 已重新读取"
                hasError = false
            }
        } catch {
            report(error)
            refreshConnections()
        }
    }

    private func compactError(_ error: Error) -> String {
        let text = error.localizedDescription
            .replacingOccurrences(of: project?.rootURL.path ?? "", with: "项目")
        return text.count > 34 ? String(text.prefix(33)) + "…" : text
    }

    private func startCodexMonitor(cwdURL: URL?) {
        codexMonitor?.stop()
        codexMonitor = nil
        guard let executable = ConnectionDetector(preferBundledCodex: true).executableURL(for: .codex) else { return }
        do {
            codexMonitor = try CodexAppServerMonitor(
                executableURL: executable,
                cwdURL: cwdURL,
                codexHomeURL: codexConfigRoot
            ) { [weak self] snapshot in
                Task { @MainActor in
                    guard let self else { return }
                    self.codexSnapshot = snapshot
                    self.codexNeedsConfigurationAccess = snapshot == nil && self.codexConfigRoot == nil
                    if snapshot == nil, self.codexConfigRoot != nil {
                        self.footerMessage = "Codex App Server 连接失败"
                        self.hasError = true
                    }
                    self.refreshConnections()
                }
            }
        } catch {
            codexSnapshot = nil
            codexNeedsConfigurationAccess = codexConfigRoot == nil
        }
    }

    private func projectFingerprint(_ root: URL) -> String {
        let watched = [
            root.appendingPathComponent(".project-standard"),
            root.appendingPathComponent("AGENTS.md"),
            root.appendingPathComponent("CLAUDE.md"),
            root.appendingPathComponent(".codex/config.toml"),
            root.appendingPathComponent(".codex/rules/project-standard.rules"),
            root.appendingPathComponent(".agents/skills"),
            root.appendingPathComponent(".mcp.json"),
            root.appendingPathComponent(".claude/settings.json"),
            root.appendingPathComponent(".claude/skills")
        ] + customClients.flatMap { definition in
            [
                root.appendingPathComponent(definition.instructionFile),
                root.appendingPathComponent(definition.skillsDirectory)
            ]
        }
        var rows: [String] = []
        for url in watched {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                rows.append("\(url.path):missing")
                continue
            }
            if isDirectory.boolValue {
                guard let enumerator = FileManager.default.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }
                for case let item as URL in enumerator {
                    rows.append(fingerprintRow(item))
                }
            } else {
                rows.append(fingerprintRow(url))
            }
        }
        return rows.sorted().joined(separator: "|")
    }

    private func fingerprintRow(_ url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isSymbolicLinkKey])
        let link = values?.isSymbolicLink == true ? (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) ?? "" : ""
        return "\(url.path):\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0):\(values?.fileSize ?? 0):\(link)"
    }

    private static func projectArgumentURL() -> URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--project"), arguments.indices.contains(index + 1) else {
            return nil
        }
        return URL(fileURLWithPath: arguments[index + 1], isDirectory: true).standardizedFileURL
    }

    private static func userHomeURL() -> URL {
        if let entry = getpwuid(getuid()), let home = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: home), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

}
