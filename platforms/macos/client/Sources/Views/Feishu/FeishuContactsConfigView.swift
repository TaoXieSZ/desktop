import SwiftUI
import VoiceAgent

struct FeishuContactsConfigView: View {
    @State private var contacts: [FeishuContact] = []
    @State private var editing: ContactDraft?
    @State private var statusMessage: String?
    @State private var statusIsError: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if contacts.isEmpty {
                emptyState
            } else {
                contactList
            }

            HStack(spacing: 8) {
                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(statusIsError ? Color.red : .secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                Button("重新加载") { reload() }
                    .controlSize(.small)
                Button("保存") { save() }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasUnsavedChanges)
            }
        }
        .onAppear { reload() }
        .sheet(item: $editing) { draft in
            ContactEditor(
                draft: draft,
                onSave: { newContact in
                    apply(newContact, replacing: draft.originalName)
                    editing = nil
                },
                onCancel: { editing = nil }
            )
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("联系人列表")
                .font(.callout.weight(.semibold))
            Text("\(contacts.count) 项")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                editing = ContactDraft()
            } label: {
                Label("添加", systemImage: "plus")
            }
            .controlSize(.small)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("还没有联系人")
                .font(.callout.weight(.semibold))
            Text("点右上角「添加」录入第一个群或用户")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 110)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var contactList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(Array(contacts.enumerated()), id: \.element.name) { idx, contact in
                    contactRow(contact, at: idx)
                }
            }
        }
        .frame(minHeight: 180, maxHeight: 280)
    }

    private func contactRow(_ contact: FeishuContact, at idx: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(contact.name)
                    .font(.callout.weight(.semibold))
                Text("\(contact.idType.rawValue): \(contact.id)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !contact.aliases.isEmpty {
                    Text("别名: \(contact.aliases.joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Button {
                editing = ContactDraft(original: contact)
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("编辑")

            Button {
                contacts.remove(at: idx)
                statusMessage = "已删除「\(contact.name)」(未保存)"
                statusIsError = false
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .help("删除")
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    // MARK: - State helpers

    @State private var lastLoaded: [FeishuContact] = []

    private var hasUnsavedChanges: Bool {
        contacts != lastLoaded
    }

    private func reload() {
        let loaded = FeishuContactStore.load()
        contacts = loaded
        lastLoaded = loaded
        if let url = FeishuContactStore.fileURL,
           !FileManager.default.fileExists(atPath: url.path) {
            statusMessage = "尚未保存到磁盘"
            statusIsError = false
        } else {
            statusMessage = nil
            statusIsError = false
        }
    }

    private func save() {
        if FeishuContactStore.save(contacts) {
            lastLoaded = contacts
            let path = FeishuContactStore.fileURL?.path ?? "?"
            statusMessage = "已保存到 \(path)"
            statusIsError = false
        } else {
            statusMessage = "保存失败,无法写入文件"
            statusIsError = true
        }
    }

    private func apply(_ newContact: FeishuContact, replacing originalName: String?) {
        if let originalName,
           let idx = contacts.firstIndex(where: { $0.name == originalName }) {
            contacts[idx] = newContact
        } else if let idx = contacts.firstIndex(where: { $0.name == newContact.name }) {
            contacts[idx] = newContact
        } else {
            contacts.append(newContact)
        }
        statusMessage = "已修改「\(newContact.name)」(未保存)"
        statusIsError = false
    }
}

// MARK: - Editor

private struct ContactDraft: Identifiable {
    let id = UUID()
    let originalName: String?
    var name: String
    var contactID: String
    var idType: FeishuContact.IDType
    var aliasesText: String

    init(original: FeishuContact? = nil) {
        self.originalName = original?.name
        self.name = original?.name ?? ""
        self.contactID = original?.id ?? ""
        self.idType = original?.idType ?? .chatID
        self.aliasesText = original?.aliases.joined(separator: ", ") ?? ""
    }

    func makeContact() -> FeishuContact {
        let aliases = aliasesText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return FeishuContact(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            id: contactID.trimmingCharacters(in: .whitespacesAndNewlines),
            idType: idType,
            aliases: aliases
        )
    }
}

private struct ContactEditor: View {
    @State var draft: ContactDraft
    var onSave: (FeishuContact) -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(draft.originalName == nil ? "添加飞书联系人" : "编辑飞书联系人")
                .font(.headline)

            Form {
                TextField("名称", text: $draft.name, prompt: Text("秘书会按这个名字找人,例如:小龙虾群"))
                Picker("ID 类型", selection: $draft.idType) {
                    Text("chat_id (群聊 ID)").tag(FeishuContact.IDType.chatID)
                    Text("open_id (用户 open_id)").tag(FeishuContact.IDType.openID)
                    Text("user_id (用户 user_id)").tag(FeishuContact.IDType.userID)
                    Text("email (邮箱)").tag(FeishuContact.IDType.email)
                }
                TextField("ID 值", text: $draft.contactID, prompt: Text(idPlaceholder))
                    .font(.callout.monospaced())
                TextField("别名(逗号分隔,可选)", text: $draft.aliasesText, prompt: Text("openclaw, 龙虾"))
            }

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("保存") {
                    onSave(draft.makeContact())
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || draft.contactID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private var idPlaceholder: String {
        switch draft.idType {
        case .chatID: "oc_xxxxxxxxxxxxxx"
        case .openID: "ou_xxxxxxxxxxxxxx"
        case .userID: "用户的 user_id"
        case .email: "user@example.com"
        }
    }
}
