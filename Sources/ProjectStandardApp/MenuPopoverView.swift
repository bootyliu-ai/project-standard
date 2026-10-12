import AppKit
import ProjectStandardCore
import SwiftUI

struct MenuPopoverView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            if model.customClientEditor != nil {
                CustomClientEditorView(model: model)
            } else if let detail = model.detailScheme {
                detailView(detail)
            } else {
                mainView
            }
        }
        .frame(width: 320)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { model.refreshConnections() }
    }

    private var mainView: some View {
        VStack(spacing: 0) {
            header
            if let project = model.project {
                schemeList(project)
                connectionsList
            } else {
                emptyProject
            }
            footer
        }
    }

    private var header: some View {
        Button(action: model.chooseProject) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("项目规范")
                        .font(.system(size: 12, weight: .semibold))
                    Text(model.project?.displayName ?? "选择项目")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Circle()
                    .fill(model.project == nil ? Color.secondary.opacity(0.5) : Color.green)
                    .frame(width: 8, height: 8)
            }
            .padding(.horizontal, 12)
            .frame(height: 45)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("切换项目")
    }

    private func schemeList(_ project: LoadedProject) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Text("方案").font(.system(size: 10.5, weight: .semibold))
                Spacer()
                Text("\(project.schemes.count) 个").font(.system(size: 9.5)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 27)

            VStack(spacing: 1) {
                ForEach(project.schemes) { scheme in
                    schemeRow(scheme)
                }
            }
            .padding(.horizontal, 7)
            .padding(.bottom, 7)
        }
    }

    private func schemeRow(_ scheme: Scheme) -> some View {
        let isSelected = model.selectedSchemeID == scheme.id
        return HStack(spacing: 0) {
            Button { model.selectScheme(scheme.id) } label: {
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.55), lineWidth: 1)
                    if isSelected {
                        Circle().fill(Color.accentColor)
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 16, height: 16)
                .frame(width: 31, height: 42)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("设为当前方案")

            Button { model.showScheme(scheme.id) } label: {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(scheme.name)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                        Text("Prompt · Rules · 记忆 · 项目 · Skills · MCP · 权限")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 2)
                    Text("\(scheme.itemCount) 项")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.trailing, 7)
                .frame(height: 42)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(isSelected ? Color.accentColor.opacity(0.10) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private var connectionsList: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Text("本机接入").font(.system(size: 10.5, weight: .semibold))
                Spacer()
                Text("发现 \(model.connections.count) 个 · 开启 \(model.connections.filter(\.enabled).count)")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                Button(action: model.beginAddingCustomClient) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("添加自定义端")
            }
            .padding(.horizontal, 12)
            .frame(height: 29)

            if model.connections.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "terminal").foregroundStyle(.secondary)
                    Text("未发现 Codex、Claude Code、DCC 或 Smart Work")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .frame(height: 45)
                .background(Color(nsColor: .controlBackgroundColor))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.connections.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { Divider().padding(.leading, 48) }
                        connectionRow(row)
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor))
            }
        }
    }

    private func connectionRow(_ row: ConnectionRowState) -> some View {
        HStack(spacing: 8) {
            Group {
                if row.profile.client == .custom {
                    Button { model.editCustomClient(row.profile) } label: { connectionIdentity(row) }
                        .buttonStyle(.plain)
                        .help(row.enabled ? "关闭后可编辑" : "编辑自定义端")
                } else {
                    connectionIdentity(row)
                }
            }
            Spacer(minLength: 4)
            Toggle("", isOn: Binding(
                get: { row.enabled },
                set: { _ in model.toggleConnection(row.id) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .padding(.horizontal, 11)
        .frame(height: 47)
    }

    private func connectionIdentity(_ row: ConnectionRowState) -> some View {
        HStack(spacing: 8) {
            Text(row.profile.client.iconText)
                .font(.system(size: 7.5, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 27, height: 27)
                .background(clientColor(row.profile.client))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 1) {
                Text(row.profile.title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .lineLimit(1)
                Text(row.status)
                    .font(.system(size: 9))
                    .foregroundStyle(row.hasIssue ? Color.orange : (row.validatedCategories > 0 ? Color.green : Color.secondary))
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
    }

    private func clientColor(_ client: ClientKind) -> Color {
        switch client {
        case .codex: Color(nsColor: .darkGray)
        case .claudeCode: Color.orange.opacity(0.85)
        case .smartWork: Color.blue.opacity(0.85)
        case .dcc: Color.purple.opacity(0.85)
        case .custom: Color.teal.opacity(0.85)
        }
    }

    private var emptyProject: some View {
        VStack(spacing: 8) {
            Text("选择一个项目目录")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            Button("选择项目…", action: model.chooseProject)
                .controlSize(.small)
            Text("首次选择会创建默认项目规范")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 105)
        .overlay(Divider(), alignment: .top)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.hasError ? Color.orange : Color.green)
                .frame(width: 7, height: 7)
            Text(model.footerMessage)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if model.codexNeedsConfigurationAccess {
                Button(action: model.chooseCodexConfiguration) {
                    Label("授权 Codex", systemImage: "lock.open")
                        .font(.system(size: 9, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("选择 .codex 配置目录")
            }
            if model.project != nil {
                Button(action: model.reloadProject) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("重新读取项目")
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 34)
        .overlay(Divider(), alignment: .top)
    }

    private func detailView(_ scheme: Scheme) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: model.closeScheme) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                Text("方案内容").font(.system(size: 11.5, weight: .semibold))
                Spacer()
                Color.clear.frame(width: 28, height: 28)
            }
            .padding(.horizontal, 8)
            .frame(height: 45)
            .overlay(Divider(), alignment: .bottom)

            VStack(alignment: .leading, spacing: 2) {
                Text(scheme.name).font(.system(size: 12, weight: .semibold))
                Text("7 类 · \(scheme.itemCount) 项").font(.system(size: 9.5)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .frame(height: 47)
            .overlay(Divider(), alignment: .bottom)

            ForEach(Array(scheme.categories.enumerated()), id: \.element.id) { index, source in
                if index > 0 { Divider().padding(.leading, 12) }
                Button { model.openCategory(source) } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.category.displayName)
                                .font(.system(size: 10.5, weight: .medium))
                            Text(source.relativePath)
                                .font(.system(size: 8.5, design: .monospaced))
                                .foregroundStyle(source.exists ? .secondary : Color.orange)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 4)
                        Text(source.exists ? "\(source.itemCount) 项" : "缺失")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Image(systemName: "arrow.up.forward")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 46)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            footer
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
