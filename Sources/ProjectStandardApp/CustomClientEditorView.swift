import SwiftUI

struct CustomClientEditorView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            fields
            actions
            status
        }
    }

    private var header: some View {
        HStack {
            Button(action: model.closeCustomClientEditor) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            Text(model.customClientEditor?.id == nil ? "添加端" : "编辑端")
                .font(.system(size: 11.5, weight: .semibold))
            Spacer()
            Color.clear.frame(width: 28, height: 28)
        }
        .padding(.horizontal, 8)
        .frame(height: 45)
        .overlay(Divider(), alignment: .bottom)
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 12) {
            editorField(title: "名称", placeholder: "例如 My Agent", value: nameBinding)
            editorField(title: "项目指令文件", placeholder: "AGENTS.md", value: instructionBinding)
            editorField(title: "Skills 目录", placeholder: ".agents/skills", value: skillsBinding)
        }
        .padding(14)
    }

    private var actions: some View {
        HStack {
            if model.customClientEditor?.id != nil {
                Button("删除端", role: .destructive, action: model.deleteCustomClient)
                    .controlSize(.small)
            }
            Spacer()
            Button("取消", action: model.closeCustomClientEditor)
                .controlSize(.small)
            Button("保存", action: model.saveCustomClient)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    private var status: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.hasError ? Color.orange : Color.green)
                .frame(width: 7, height: 7)
            Text(model.footerMessage)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 11)
        .frame(height: 34)
        .overlay(Divider(), alignment: .top)
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { model.customClientEditor?.name ?? "" },
            set: { value in model.updateCustomClientName(value) }
        )
    }

    private var instructionBinding: Binding<String> {
        Binding(
            get: { model.customClientEditor?.instructionFile ?? "" },
            set: { value in model.updateCustomInstructionFile(value) }
        )
    }

    private var skillsBinding: Binding<String> {
        Binding(
            get: { model.customClientEditor?.skillsDirectory ?? "" },
            set: { value in model.updateCustomSkillsDirectory(value) }
        )
    }

    private func editorField(title: String, placeholder: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: value)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 10.5))
        }
    }
}
