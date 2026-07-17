import SwiftUI

/// 设置面板视图，作为独立 NSWindow 展示。
///
/// 采用与 popover 一致的液态玻璃风格，以分组卡片形式组织设置项：
/// - 最近端口保存数量（自定义步进器 + 视觉刻度条，0-8）
/// - 开机自动启动（Toggle + 图标说明）
/// - 清空最近查询记录（警告样式 + 破坏性操作按钮）
struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 16) {
            // Section: 最近端口保存数量
            settingsSection(
                icon: "number.circle.fill",
                title: "最近端口保存数量",
                accentColor: .blue
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    // 自定义步进器
                    HStack(spacing: 12) {
                        Text("保存数量")
                            .font(.body)
                            .foregroundStyle(.primary)

                        Spacer()

                        // 减号按钮
                        Button(action: {
                            if settings.maxRecentPorts > 0 {
                                settings.maxRecentPorts -= 1
                            }
                        }) {
                            Image(systemName: "minus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(settings.maxRecentPorts > 0 ? .secondary : .tertiary)
                        }
                        .buttonStyle(.plain)
                        .disabled(settings.maxRecentPorts <= 0)
                        .help("减少")

                        // 当前数值
                        Text(String(settings.maxRecentPorts))
                            .font(.title3)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .frame(width: 30)
                            .foregroundStyle(settings.maxRecentPorts == 0 ? .secondary : .primary)

                        // 加号按钮
                        Button(action: {
                            if settings.maxRecentPorts < 8 {
                                settings.maxRecentPorts += 1
                            }
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(settings.maxRecentPorts < 8 ? Color.accentColor : Color.secondary.opacity(0.35))
                        }
                        .buttonStyle(.plain)
                        .disabled(settings.maxRecentPorts >= 8)
                        .help("增加")

                        Text("条")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // 视觉刻度条 (0-8)
                    HStack(spacing: 3) {
                        ForEach(0..<9, id: \.self) { i in
                            Capsule()
                                .fill(
                                    i < settings.maxRecentPorts
                                        ? Color.accentColor
                                        : Color.secondary.opacity(0.15)
                                )
                                .frame(height: 6)
                                .animation(.easeInOut(duration: 0.15), value: settings.maxRecentPorts)
                        }
                    }

                    // 提示文字
                    Label {
                        Text("设为 0 则不保存任何最近查询记录")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "info.circle")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            // Section: 开机启动
            settingsSection(
                icon: "power.circle.fill",
                title: "开机启动",
                accentColor: .green
            ) {
                Toggle(isOn: $settings.launchAtLogin) {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.body)
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("登录时自动启动 KillPort")
                                .font(.body)
                            Text("打开 Mac 时自动在菜单栏运行")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.switch)
            }

            // Section: 清空最近查询记录
            settingsSection(
                icon: "trash.circle.fill",
                title: "最近查询记录",
                accentColor: .orange
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    // 警告提示
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.body)
                        Text("当前共有 " + String(settings.recentPorts.count) + " 条最近查询记录")
                            .font(.body)
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    // 破坏性操作按钮
                    Button(role: .destructive, action: {
                        settings.clearRecentPorts()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "trash.fill")
                            Text("清空所有记录")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.bordered)
                    .disabled(settings.recentPorts.isEmpty)
                }
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    // MARK: - Section Builder

    /// 构建一个带液态玻璃背景的设置分组卡片。
    ///
    /// - Parameters:
    ///   - icon: SF Symbol 图标名称。
    ///   - title: 分组标题。
    ///   - accentColor: 图标强调色。
    ///   - content: 分组内容视图。
    private func settingsSection<Content: View>(
        icon: String,
        title: String,
        accentColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // 分组标题行
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(accentColor)
                Text(title)
                    .font(.headline)
                Spacer()
            }

            // 分组内容
            content()
        }
        .padding(16)
        .glassBackground(in: RoundedRectangle(cornerRadius: 12))
    }
}
