import GameController
import SwiftUI

// MARK: - Physical controllers

/// The game controllers and keyboards connected, by Bluetooth or USB.
@MainActor
final class ControllerMonitor: ObservableObject {
    static let shared = ControllerMonitor()

    struct Device: Identifiable, Hashable {
        let id: String
        let name: String
        let symbol: String
        let battery: String?
    }

    @Published private(set) var connected = !GCController.controllers().isEmpty
    @Published private(set) var devices: [Device] = []
    /// The name of the controller that just connected, for a notice.
    @Published var justConnected: String?

    private init() {
        refresh()
        let center = NotificationCenter.default
        let names: [Notification.Name] = [.GCControllerDidConnect, .GCControllerDidDisconnect,
                                          .GCKeyboardDidConnect, .GCKeyboardDidDisconnect]
        for name in names {
            center.addObserver(forName: name, object: nil, queue: .main) { note in
                MainActor.assumeIsolated {
                    let monitor = ControllerMonitor.shared
                    monitor.refresh()
                    if note.name == .GCControllerDidConnect, let controller = note.object as? GCController {
                        monitor.justConnected = controller.vendorName ?? "Controle"
                    }
                }
            }
        }
    }

    func refresh() {
        let pads = GCController.controllers().filter { $0.extendedGamepad != nil || $0.microGamepad != nil }
        connected = !pads.isEmpty
        var list = pads.enumerated().map { index, controller in
            Device(id: "pad\(index)\(controller.vendorName ?? "")",
                   name: controller.vendorName ?? "Controle",
                   symbol: Self.symbol(for: controller),
                   battery: Self.battery(controller.battery))
        }
        if GCKeyboard.coalesced != nil {
            list.append(Device(id: "keyboard", name: String(localized: "Teclado"), symbol: "keyboard", battery: nil))
        }
        devices = list
    }

    private static func symbol(for controller: GCController) -> String {
        let category = controller.productCategory.lowercased()
        if category.contains("dualsense") || category.contains("dualshock") || category.contains("playstation") {
            return "logo.playstation"
        }
        if category.contains("xbox") { return "logo.xbox" }
        return "gamecontroller.fill"
    }

    private static func battery(_ battery: GCDeviceBattery?) -> String? {
        guard let battery, battery.batteryState != .unknown else { return nil }
        let level = "\(Int(battery.batteryLevel * 100))%"
        return battery.batteryState == .charging ? "\(level) · carregando" : level
    }
}
