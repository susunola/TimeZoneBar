import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var store: TimeZoneStore
    @StateObject private var updater = Updater()
    @State private var addSelection = "Asia/Shanghai"
    @State private var launchAtLogin = false

    private var isBundled: Bool { Bundle.main.bundleIdentifier != nil }

    private var updateStatusText: String {
        switch updater.state {
        case .idle: return "检查 GitHub 上的新版本"
        case .checking: return "正在检查…"
        case .available(let v, _): return "发现新版本 v\(v)，点击右侧按钮原地升级"
        case .downloading: return "正在下载并安装，完成后自动重启…"
        case .upToDate: return "当前已是最新版本"
        case .error(let msg): return msg
        }
    }

    private var updateButtonTitle: String { updater.state.buttonTitle }

    static let commonZones: [(id: String, label: String, region: String)] = [
        ("Asia/Shanghai", "北京 / 上海", "中国"),
        ("Asia/Bangkok", "曼谷", "泰国"),
        ("Asia/Jakarta", "雅加达", "印度尼西亚"),
        ("Asia/Hong_Kong", "中国香港", "中国"),
        ("Asia/Taipei", "台北", "中国台湾"),
        ("Asia/Tokyo", "东京", "日本"),
        ("Asia/Seoul", "首尔", "韩国"),
        ("Asia/Singapore", "新加坡", "新加坡"),
        ("Asia/Dubai", "迪拜", "阿联酋"),
        ("Asia/Kolkata", "新德里", "印度"),
        ("Australia/Sydney", "悉尼", "澳大利亚"),
        ("Pacific/Auckland", "奥克兰", "新西兰"),
        ("Europe/London", "伦敦", "英国"),
        ("Europe/Paris", "巴黎", "法国"),
        ("Europe/Berlin", "柏林", "德国"),
        ("America/New_York", "纽约", "美国"),
        ("America/Los_Angeles", "洛杉矶", "美国"),
        ("America/Chicago", "芝加哥", "美国"),
        ("America/Sao_Paulo", "圣保罗", "巴西"),
        ("UTC", "协调世界时", "")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("TimeZoneBar 设置")
                .font(.title2)

            if #available(macOS 26, *) {
                Label("macOS 26：若菜单栏未显示图标，请到 系统设置 › 菜单栏 › 允许在菜单栏显示 中开启 TimeZoneBar",
                      systemImage: "info.circle")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            if isBundled {
                Toggle("登录时自动启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = !newValue
                        }
                    }
            }

            Divider()

            Text("菜单栏时区列表")
                .font(.headline)

            HStack(spacing: 8) {
                Picker("添加时区", selection: $addSelection) {
                    ForEach(Self.commonZones, id: \.id) { item in
                        Text(item.region.isEmpty ? item.label : "\(item.label) · \(item.region)")
                            .tag(item.id)
                    }
                }
                .labelsHidden()

                Button("添加") {
                    guard !store.zones.contains(where: { $0.id == addSelection }) else { return }
                    let item = Self.commonZones.first { $0.id == addSelection }
                    store.zones.append(ZoneEntry(id: addSelection,
                                                 label: item?.label ?? addSelection,
                                                 region: item?.region ?? "",
                                                 color: "#007AFF"))
                    store.save()
                }
                .disabled(store.zones.contains { $0.id == addSelection })
            }

            ForEach(store.zones) { zone in
                HStack {
                    Circle()
                        .fill(Color(hex: zone.color))
                        .frame(width: 8, height: 8)
                    Text("\(zone.label) (\(zone.id))")
                        .font(.system(size: 13))
                    Spacer()
                    if zone.id == store.currentZoneIdentifier {
                        Text("当前")
                            .font(.system(size: 11))
                            .foregroundColor(.blue)
                    }
                    Button("移除") {
                        store.zones.removeAll { $0.id == zone.id }
                        store.save()
                    }
                    .disabled(zone.id == store.currentZoneIdentifier)
                }
            }

            Button("恢复默认列表") {
                store.zones = TimeZoneStore.defaultZones
                store.save()
            }

            Divider()
                .padding(.top, 8)

            // 软件更新区
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 13))
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("软件更新")
                        .font(.system(size: 13, weight: .medium))
                    Text(updateStatusText)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(updateButtonTitle) {
                    switch updater.state {
                    case .available(_, let release):
                        Task { await updater.update(release: release) }
                    default:
                        Task { await updater.check() }
                    }
                }
                .disabled(updater.isBusy)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(0.06))
            )

            Divider()
                .padding(.top, 8)

            // 卸载区
            HStack(spacing: 10) {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundColor(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("卸载 TimeZoneBar")
                        .font(.system(size: 13, weight: .medium))
                    Text("删除 App 与全部本地数据（需管理员授权）")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("卸载…", role: .destructive) {
                    showUninstallConfirm = true
                }
                .disabled(isUninstalling)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.red.opacity(0.06))
            )
            .confirmationDialog("确定卸载 TimeZoneBar？",
                                isPresented: $showUninstallConfirm,
                                titleVisibility: .visible) {
                Button("卸载并删除所有数据", role: .destructive) {
                    uninstall()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("App 将被删除并立即退出。若 Launchpad 中仍显示图标，请重启 Dock（终端执行 killall Dock）或重新登录。")
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear {
            if isBundled {
                launchAtLogin = (SMAppService.mainApp.status == .enabled)
            }
        }
    }

    @State private var showUninstallConfirm = false
    @State private var isUninstalling = false

    /// 卸载流程：清本地数据 → 管理员权限删除自身 bundle → 退出
    private func uninstall() {
        guard !isUninstalling else { return }
        isUninstalling = true
        // 1. 清掉 App 自己的偏好与缓存数据
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("TimeZoneBar", isDirectory: true) {
            try? FileManager.default.removeItem(at: appSupport)
        }
        // 2. 关闭开机自启注册
        if isBundled {
            try? SMAppService.mainApp.unregister()
        }
        // 3. 删除自身 App bundle（管理员授权，quoted form 安全转义路径）
        let appPath = Bundle.main.bundlePath
        let script = "do shell script \"rm -rf \" & quoted form of \"\(appPath)\" with administrator privileges"
        Task {
            do {
                try await PrivilegedRunner.run(script: script)
                isUninstalling = false
                NSApp.terminate(nil)
            } catch {
                isUninstalling = false
                NSAlert(error: error).runModal()
            }
        }
    }
}
