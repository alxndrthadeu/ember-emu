import Foundation
import SwiftUI
import UIKit

/// What a running game costs, sampled from the system and the engine.
/// Memory is the footprint iOS judges apps by (the figure that decides
/// which app it closes); CPU is the sum over all threads, 100% = one
/// core.
enum ResourceMonitor {
    struct Sample: Equatable {
        var memoryMB: Double
        var cpuPercent: Double
        var fps: Double
        var targetFPS: Int
        var thermal: ProcessInfo.ThermalState

        var thermalText: String {
            switch thermal {
            case .nominal: "normal"
            case .fair: "morno"
            case .serious: "quente"
            case .critical: "muito quente"
            @unknown default: "?"
            }
        }

        /// Below 90% of the game's own frame rate.
        var isSlow: Bool {
            targetFPS > 0 && fps < Double(targetFPS) * 0.9
        }

        var line: String {
            String(format: "%.0f fps · CPU %.0f%% · %.0f MB · %@", fps, cpuPercent, memoryMB, thermalText)
        }
    }

    static func sample() -> Sample {
        Sample(memoryMB: footprintMB(), cpuPercent: cpuPercent(),
               fps: mkxp_getAverageFPS(), targetFPS: Int(mkxp_getTargetFPS()),
               thermal: ProcessInfo.processInfo.thermalState)
    }

    #if DEBUG
    private static var timer: Timer?

    /// Development aid (EMBER_METRICS=1): logs a sample every 5 seconds.
    static func startIfRequested() {
        guard ProcessInfo.processInfo.environment["EMBER_METRICS"] != nil, timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            print("[ember-metrics] \(sample().line)")
        }
    }
    #else
    static func startIfRequested() {}
    #endif

    private static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    private static func cpuPercent() -> Double {
        var threads: thread_act_array_t?
        var threadCount = mach_msg_type_number_t(0)
        guard task_threads(mach_task_self_, &threads, &threadCount) == KERN_SUCCESS, let threads else { return 0 }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads),
                          vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.stride))
        }
        var total = 0.0
        for index in 0..<Int(threadCount) {
            var info = thread_basic_info()
            var count = mach_msg_type_number_t(THREAD_INFO_MAX)
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    thread_info(threads[index], thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
                }
            }
            if result == KERN_SUCCESS, info.flags & TH_FLAGS_IDLE == 0 {
                total += Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100
            }
        }
        return total
    }
}

/// Samples once a second while the HUD shows.
@MainActor
final class PerformanceModel: ObservableObject {
    static let shared = PerformanceModel()

    @Published var enabled = AppSettings.showPerformance {
        didSet {
            AppSettings.showPerformance = enabled
            enabled ? start() : stop()
        }
    }
    @Published private(set) var sample: ResourceMonitor.Sample?

    private var timer: Timer?

    private init() {}

    func start() {
        guard enabled, timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { PerformanceModel.shared.sample = ResourceMonitor.sample() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        sample = nil
    }
}

/// The on-screen readout, PC-game style: small, in a corner, monospaced.
struct PerformanceHUD: View {
    @ObservedObject private var model = PerformanceModel.shared

    var body: some View {
        if model.enabled, let sample = model.sample {
            HStack(spacing: 8) {
                Text(String(format: "%.0f", sample.fps))
                    .foregroundStyle(sample.isSlow ? Theme.highlight : Color(hex: 0x4DB3A8))
                    + Text(" fps").foregroundStyle(.white.opacity(0.7))
                Text(String(format: "CPU %.0f%%", sample.cpuPercent))
                Text(String(format: "%.0f MB", sample.memoryMB))
                if sample.thermal != .nominal {
                    Image(systemName: "thermometer.medium")
                        .foregroundStyle(sample.thermal == .fair ? Theme.highlight : Color.red)
                }
            }
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(.black.opacity(0.55)))
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Desempenho: \(sample.line)")
        }
    }
}
