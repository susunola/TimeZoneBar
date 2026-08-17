import AppKit

// main.swift 顶层代码运行在主线程上，但不在 MainActor 隔离上下文中；
// NSApplication + AppDelegate 都是 MainActor 隔离的，用 assumeIsolated
// 进入 MainActor 再启动主循环。
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    NSApplication.shared.delegate = delegate
    NSApplication.shared.setActivationPolicy(.accessory)
    NSApplication.shared.run()
}