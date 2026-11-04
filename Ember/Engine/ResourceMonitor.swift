import Foundation
import UIKit

/// Development aid (EMBER_METRICS=1): logs what a running game costs,
/// every 5 seconds. Memory is the footprint iOS judges apps by (the
/// figure jetsam uses), CPU is the sum over all threads, 100% = one
/// core.
enum ResourceMonitor {
    #if DEBUG
    private static var timer: Timer?

    static func startIfRequested() {
        guard ProcessInfo.processInfo.environment["EMBER_METRICS"] != nil, timer == nil else { return }
        UIDevice.current.isBatteryMonitoringEnabled = true
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            let thermal = ["normal", "razoável", "sério", "crítico"][ProcessInfo.processInfo.thermalState.rawValue]
            print(String(format: "[ember-metrics] memória %.0f MB · CPU %.0f%% · %.0f fps · temperatura %@ · bateria %.0f%%",
                         footprintMB(), cpuPercent(), mkxp_getAverageFPS(), thermal,
                         UIDevice.current.batteryLevel * 100))
        }
    }

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
    #else
    static func startIfRequested() {}
    #endif
}
