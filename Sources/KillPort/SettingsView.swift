import SwiftUI

/// 设置面板视图，作为独立 NSWindow 展示。
///
/// 提供以下设置项：
/// - 最近端口保存数量（Stepper，0-8）
/// - 开机自动启动（Toggle）
/// - 清空最近查询记录（Button）
struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 20) {
            // 最大保存条目数
            VStack(alignment: .leading, spacing: 8) {
                Text("最近端口保存数量")
                    .font(.headline)
                HStack {
                    Stepper(value: $settings.maxRecentPorts, in: 0...8) {
                        Text("\(settings.maxRecentPorts) 条")
                            .font(.body)
                    }
                    Spacer()
                }
                Text("设为 0 则不保存任何最近查询记录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // 开机启动
            Toggle("开机时自动启动", isOn: $settings.launchAtLogin)
                .font(.body)

            Divider()

            // 清空最近端口
            HStack {
                Text("最近查询记录")
                    .font(.headline)
                Spacer()
                Button("清空") {
                    settings.clearRecentPorts()
                }
                .buttonStyle(.bordered)
                .disabled(settings.recentPorts.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 340)
    }
}
