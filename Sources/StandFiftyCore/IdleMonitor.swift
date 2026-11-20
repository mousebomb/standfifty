import CoreGraphics
import Foundation

/// 键鼠空闲时长采样（与屏保判定的 HID idle 同源），零轮询子进程开销。
public enum IdleMonitor {

    /// 距离最后一次任意键鼠输入的秒数
    public static var secondsSinceLastInput: TimeInterval {
        // 0xFFFFFFFF 是 kCGAnyInputEventType，表示任意输入事件
        var result = TimeInterval.greatestFiniteMagnitude
        if let anyInput = CGEventType(rawValue: ~0) {
            result = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        }

        // 部分系统版本对 anyInput 返回异常值，用常见类型兜底，取最小值
        let eventTypes: [CGEventType] = [.keyDown, .mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel]
        for type in eventTypes {
            let value = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: type)
            if value >= 0 { result = min(result, value) }
        }
        return max(result, 0)
    }
}
