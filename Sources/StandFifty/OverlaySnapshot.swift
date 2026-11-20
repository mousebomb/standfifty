import AppKit
import Foundation

/// 调试用：把遮罩渲染成 PNG，方便在没有屏幕录制权限时检查排版
enum OverlaySnapshot {
    static func write(to path: String, size: NSSize = NSSize(width: 1600, height: 900)) -> Bool {
        let view = OverlayView(frame: NSRect(origin: .zero, size: size))
        view.configure(restSeconds: 60, anchorMinute: 50)
        view.update(accumulated: 27, restSeconds: 60)
        view.layoutSubtreeIfNeeded()

        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            return true
        } catch {
            return false
        }
    }
}
