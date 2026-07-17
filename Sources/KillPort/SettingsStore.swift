import Foundation
import Combine

/// 持久化应用设置，使用 UserDefaults 存储。
///
/// 此类负责管理以下设置：
/// - 最近查询端口列表（受 `maxRecentPorts` 限制）
/// - 最大保存条目数（0-8，默认 5）
/// - 开机启动开关
///
/// 注意：此类不导入 ServiceManagement，可在测试中编译运行。
/// 开机启动的实际注册/注销通过 `NotificationCenter` 解耦，
/// 由 `StatusBarController` 监听并调用 `SMAppService`。
final class AppSettings: ObservableObject {

    // MARK: - Published Properties

    /// 最大保存的最近端口条目数（0-8）。
    /// 设为 0 时不保存任何最近端口。减少时自动裁剪已有条目。
    @Published var maxRecentPorts: Int {
        didSet {
            let clamped = max(0, min(8, maxRecentPorts))
            if clamped != maxRecentPorts {
                maxRecentPorts = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: "maxRecentPorts")
            // 如果最大条目数减少，裁剪已有的最近端口
            trimRecentPorts()
        }
    }

    /// 是否开机自动启动。
    /// 变化时通过 NotificationCenter 通知 StatusBarController 处理 SMAppService 注册/注销。
    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            NotificationCenter.default.post(
                name: .launchAtLoginChanged, object: nil, userInfo: ["enabled": launchAtLogin]
            )
        }
    }

    /// 最近查询过的端口列表，按最新查询在前排序。
    /// 外部只能通过 `addRecentPort`、`removeRecentPort`、`clearRecentPorts` 修改。
    @Published private(set) var recentPorts: [Int] {
        didSet {
            UserDefaults.standard.set(recentPorts, forKey: "recentPorts")
        }
    }

    // MARK: - Init

    init() {
        let defaults = UserDefaults.standard
        self.maxRecentPorts = defaults.object(forKey: "maxRecentPorts") as? Int ?? 5
        self.launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        self.recentPorts = defaults.array(forKey: "recentPorts") as? [Int] ?? []
        // 确保初始值在合法范围
        self.maxRecentPorts = max(0, min(8, self.maxRecentPorts))
    }

    // MARK: - Recent Ports Management

    /// 添加端口到最近查询列表。
    /// 如果端口已存在则先移除再插入到最前面。受 `maxRecentPorts` 限制。
    /// - Parameter port: 要添加的端口号。
    func addRecentPort(_ port: Int) {
        guard maxRecentPorts > 0 else { return }
        recentPorts.removeAll { $0 == port }
        recentPorts.insert(port, at: 0)
        trimRecentPorts()
    }

    /// 移除指定的最近端口。
    /// - Parameter port: 要移除的端口号。
    func removeRecentPort(_ port: Int) {
        recentPorts.removeAll { $0 == port }
    }

    /// 清空所有最近端口。
    func clearRecentPorts() {
        recentPorts = []
    }

    // MARK: - Private

    /// 裁剪最近端口列表到 `maxRecentPorts` 条。
    private func trimRecentPorts() {
        if recentPorts.count > maxRecentPorts {
            recentPorts = Array(recentPorts.prefix(maxRecentPorts))
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// popover 即将显示时发送此通知。
    static let popoverWillShow = Notification.Name("KillPortPopoverWillShow")
    /// 开机启动设置变化时发送此通知。
    static let launchAtLoginChanged = Notification.Name("KillPortLaunchAtLoginChanged")
    /// 请求打开设置面板时发送此通知。
    static let openSettings = Notification.Name("KillPortOpenSettings")
}
