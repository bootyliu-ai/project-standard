import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: StatusPopoverController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        controller = StatusPopoverController(model: AppModel())
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stopProjectAccess()
    }
}

@MainActor
final class StatusPopoverController: NSObject {
    private let model: AppModel
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let hostingController: NSHostingController<MenuPopoverView>
    private var sizeObservation: AnyCancellable?

    init(model: AppModel) {
        self.model = model
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.hostingController = NSHostingController(rootView: MenuPopoverView(model: model))
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = hostingController
        popover.contentSize = NSSize(width: 320, height: 360)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "checkmark.shield", accessibilityDescription: "项目规范")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(handleStatusItemClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        sizeObservation = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.resizePopover() }
        }
    }

    @objc private func handleStatusItemClick(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            let quit = NSMenuItem(title: "退出 Project Standard", action: #selector(quitApplication), keyEquivalent: "q")
            quit.target = self
            menu.addItem(quit)
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 3), in: button)
            return
        }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            model.reloadProject()
            resizePopover()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            DispatchQueue.main.async { [weak self] in self?.resizePopover() }
        }
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }

    func stopProjectAccess() {
        model.stopProjectAccess()
    }

    private func resizePopover() {
        hostingController.view.frame.size.width = 320
        hostingController.view.layoutSubtreeIfNeeded()
        let fitting = hostingController.view.fittingSize
        let height = min(520, max(150, fitting.height))
        popover.contentSize = NSSize(width: 320, height: height)
    }
}

@main
enum ProjectStandardMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
        withExtendedLifetime(delegate) {}
    }
}
