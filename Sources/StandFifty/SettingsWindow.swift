import AppKit
import StandFiftyCore
import SwiftUI

/// SwiftUI 设置面板
struct SettingsView: View {

    @State private var config: AppConfig
    private let onApply: (AppConfig) -> Void
    private let onTest: () -> Void

    init(config: AppConfig, onApply: @escaping (AppConfig) -> Void, onTest: @escaping () -> Void) {
        _config = State(initialValue: config)
        self.onApply = onApply
        self.onTest = onTest
    }

    var body: some View {
        Form {
            Section("提醒节奏") {
                Stepper(value: $config.anchorMinute, in: 0...59) {
                    Text("每小时第 \(config.anchorMinute) 分钟提醒")
                }
                Stepper(value: $config.catchUpMinutes, in: 0...60, step: 5) {
                    Text("唤醒后补提醒窗口：\(config.catchUpMinutes) 分钟")
                }
                Text("距离锚点超过该窗口就跳过本次，避免一开机就被遮罩怼脸。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("活动判定") {
                Stepper(value: $config.awayThresholdSeconds, in: 10...600, step: 10) {
                    Text("本小时累计离开 \(config.awayThresholdSeconds) 秒即视为已活动")
                }
                Text("屏保、锁屏、显示器睡眠都算离开。达到门槛后，本小时的第 \(config.anchorMinute) 分钟不再弹遮罩。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("遮罩") {
                Stepper(value: $config.restSeconds, in: 10...600, step: 10) {
                    Text("连续离开键盘 \(config.restSeconds) 秒后自动关闭")
                }
                Stepper(value: $config.snoozeSeconds, in: 30...600, step: 30) {
                    Text("点「延后」后 \(config.snoozeSeconds) 秒再提醒")
                }
            }

            Section("工作时段") {
                Stepper(value: $config.activeStartHour, in: 0...23) {
                    Text("开始：\(String(format: "%02d", config.activeStartHour)):00")
                }
                Stepper(value: $config.activeEndHour, in: 0...24) {
                    Text("结束：\(String(format: "%02d", config.activeEndHour)):00")
                }
                Text("时段外完全不提醒。起止相同表示全天生效。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("立即测试提醒", action: onTest)
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 560)
        .onChange(of: config) { _, newValue in
            onApply(newValue)
        }
    }
}

/// 设置窗口的宿主
final class SettingsWindowController {

    private var window: NSWindow?
    private var onApply: ((AppConfig) -> Void)?
    private var onTest: (() -> Void)?

    func show(config: AppConfig, onApply: @escaping (AppConfig) -> Void, onTest: @escaping () -> Void) {
        self.onApply = onApply
        self.onTest = onTest

        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView(
            config: config,
            onApply: { [weak self] newValue in self?.onApply?(newValue) },
            onTest: { [weak self] in self?.onTest?() }
        )
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.title = "StandFifty 设置"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
