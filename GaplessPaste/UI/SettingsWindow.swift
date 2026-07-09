import AppKit
import SwiftUI
import GaplessPasteCore

// 设置窗口：GUI 编辑配置，取代手改 config.json。
// master-detail：左侧机器列表（+/−），右侧机器表单 + 目录列表。
// 编辑即校验：合法则防抖 0.5s 自动写回 config.json 并热重载（HIG：设置即时生效，无「保存」按钮）；
// 不合法暂缓保存并显示原因，窗口关闭时冲刷未保存的合法修改。

@MainActor
final class SettingsModel: ObservableObject {
    struct EditableDirectory: Identifiable, Equatable {
        let id: UUID
        var name: String
        var path: String
        var defaultOf: DirectoryRole?

        init(id: UUID = UUID(), name: String = "", path: String = "", defaultOf: DirectoryRole? = nil) {
            self.id = id
            self.name = name
            self.path = path
            self.defaultOf = defaultOf
        }
    }

    struct EditableMachine: Identifiable, Equatable {
        let id: UUID
        var name: String
        var sshAlias: String
        var directories: [EditableDirectory]

        init(id: UUID = UUID(), name: String = "", sshAlias: String = "", directories: [EditableDirectory] = []) {
            self.id = id
            self.name = name
            self.sshAlias = sshAlias
            self.directories = directories
        }
    }

    @Published var machines: [EditableMachine] = [] {
        didSet { if !isLoading { scheduleSave() } }
    }
    @Published var selectedMachineID: UUID?
    /// 校验失败原因（nil = 当前草稿合法）
    @Published private(set) var validationMessage: String?
    /// 最近一次落盘反馈（如「已保存」）
    @Published private(set) var saveFeedback: String?

    private let onSave: (Config) -> Void
    private var isLoading = false
    private var saveTask: Task<Void, Never>?
    /// 已落盘的内容快照，避免无变化时重复写盘
    private var savedSnapshot: [EditableMachine] = []

    init(onSave: @escaping (Config) -> Void) {
        self.onSave = onSave
    }

    func load(from config: Config) {
        isLoading = true
        machines = config.machines.map { machine in
            EditableMachine(
                name: machine.name,
                sshAlias: machine.sshAlias,
                directories: machine.directories.map { EditableDirectory(name: $0.name, path: $0.path, defaultOf: $0.defaultOf) }
            )
        }
        savedSnapshot = machines
        selectedMachineID = machines.first?.id
        validationMessage = nil
        saveFeedback = nil
        isLoading = false
    }

    // MARK: - 增删

    func addMachine() {
        let machine = EditableMachine(directories: [EditableDirectory(name: "inbox", path: "~/claude-inbox")])
        machines.append(machine)
        selectedMachineID = machine.id
    }

    func removeSelectedMachine() {
        guard let id = selectedMachineID, let index = machines.firstIndex(where: { $0.id == id }) else { return }
        machines.remove(at: index)
        selectedMachineID = machines.indices.contains(index) ? machines[index].id : machines.last?.id
    }

    func addDirectory(toMachine id: UUID) {
        guard let index = machines.firstIndex(where: { $0.id == id }) else { return }
        machines[index].directories.append(EditableDirectory())
    }

    func removeDirectory(_ directoryID: UUID, fromMachine id: UUID) {
        guard let index = machines.firstIndex(where: { $0.id == id }) else { return }
        machines[index].directories.removeAll { $0.id == directoryID }
    }

    // MARK: - 保存

    private func buildConfig() -> Config {
        Config(machines: machines.map { machine in
            Machine(
                name: machine.name,
                sshAlias: machine.sshAlias,
                directories: machine.directories.map { RemoteDirectory(name: $0.name, path: $0.path, defaultOf: $0.defaultOf) }
            )
        })
    }

    private func scheduleSave() {
        // 立即反馈校验状态，落盘防抖
        let config = buildConfig()
        do {
            try config.validate()
            validationMessage = nil
        } catch {
            validationMessage = error.localizedDescription
            saveFeedback = nil
            saveTask?.cancel()
            return
        }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// 窗口关闭时冲刷；合法才写盘
    func flushSave() {
        saveTask?.cancel()
        saveNow()
    }

    private func saveNow() {
        guard machines != savedSnapshot else { return }
        let config = buildConfig()
        guard (try? config.validate()) != nil else { return }
        savedSnapshot = machines
        onSave(config)
        saveFeedback = "已保存，立即生效"
    }
}

// MARK: - 视图

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    var openConfigFile: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                machineList
                    .frame(minWidth: 150, idealWidth: 170, maxWidth: 240)
                detailPane
                    .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            footer
        }
        .frame(minWidth: 620, minHeight: 400)
    }

    private var machineList: some View {
        VStack(spacing: 0) {
            List(selection: $model.selectedMachineID) {
                ForEach(model.machines) { machine in
                    Label(
                        machine.name.isEmpty ? "未命名" : machine.name,
                        systemImage: "desktopcomputer"
                    )
                    .tag(machine.id)
                }
            }
            .listStyle(.sidebar)
            Divider()
            HStack(spacing: 0) {
                Button(action: { model.addMachine() }) {
                    Image(systemName: "plus").frame(width: 24, height: 20)
                }
                .accessibilityIdentifier("add-machine")
                .help("添加机器")
                Button(action: { model.removeSelectedMachine() }) {
                    Image(systemName: "minus").frame(width: 24, height: 20)
                }
                .accessibilityIdentifier("remove-machine")
                .disabled(model.selectedMachineID == nil)
                .help("移除选中的机器")
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(4)
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let index = model.machines.firstIndex(where: { $0.id == model.selectedMachineID }) {
            machineForm(machine: $model.machines[index])
        } else {
            VStack(spacing: 8) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 36))
                    .foregroundStyle(.tertiary)
                Text(model.machines.isEmpty ? "点左下角 + 添加一台机器" : "在左侧选择一台机器")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func machineForm(machine: Binding<SettingsModel.EditableMachine>) -> some View {
        Form {
            Section {
                TextField("名称", text: machine.name, prompt: Text("菜单里显示的名字"))
                    .accessibilityIdentifier("machine-name")
                TextField("SSH 别名", text: machine.sshAlias, prompt: Text("~/.ssh/config 的 Host"))
                    .accessibilityIdentifier("machine-ssh-alias")
            } footer: {
                Text("认证、端口、跳板全部由 ~/.ssh/config 里对应的 Host 条目负责。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("上传目录") {
                ForEach(machine.directories) { $directory in
                    HStack(spacing: 8) {
                        TextField("名称", text: $directory.name, prompt: Text("名称"))
                            .frame(width: 120)
                            .accessibilityIdentifier("directory-name")
                        TextField("路径", text: $directory.path, prompt: Text("远端路径，支持 ~/ 前缀"))
                            .accessibilityIdentifier("directory-path")
                        Picker("默认", selection: $directory.defaultOf) {
                            Text("普通").tag(DirectoryRole?.none)
                            Text("文件默认").tag(DirectoryRole?.some(.file))
                            Text("图像默认").tag(DirectoryRole?.some(.image))
                        }
                        .pickerStyle(.menu)
                        .frame(width: 112)
                        .accessibilityIdentifier("directory-default-of")
                        .help("「快速上传」时作为文件/图像的默认目录（每台机器每类至多一个）")
                        Button {
                            model.removeDirectory(directory.id, fromMachine: machine.wrappedValue.id)
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("移除该目录")
                    }
                    .labelsHidden()
                }
                Button {
                    model.addDirectory(toMachine: machine.wrappedValue.id)
                } label: {
                    Label("添加目录", systemImage: "plus")
                }
                .accessibilityIdentifier("add-directory")
                .buttonStyle(.borderless)
            }
        }
        .formStyle(.grouped)
    }

    private var footer: some View {
        HStack {
            if let message = model.validationMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else if let feedback = model.saveFeedback {
                Label(feedback, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("打开配置文件…", action: openConfigFile)
                .controlSize(.small)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - 窗口

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: SettingsModel
    private let openConfigFile: () -> Void
    private var window: NSWindow?

    init(onSave: @escaping (Config) -> Void, openConfigFile: @escaping () -> Void) {
        model = SettingsModel(onSave: onSave)
        self.openConfigFile = openConfigFile
    }

    /// 打开设置窗口。窗口已在前台编辑中时不重载草稿，避免覆盖未落盘输入
    func show(config: Config) {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(model: model, openConfigFile: openConfigFile))
            let window = NSWindow(contentViewController: hosting)
            window.title = "GaplessPaste 设置"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 680, height: 440))
            window.delegate = self
            window.center()
            self.window = window
        }
        if window?.isVisible != true {
            model.load(from: config)
        }
        // LSUIElement app 默认不抢焦点，必须显式激活
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model.flushSave()
    }
}
