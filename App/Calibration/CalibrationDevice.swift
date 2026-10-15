import Foundation
import UIKit
import Metal
import BlurCore
import BlurGPU

// OWNER: CALIBRATION. The DeviceStamp every Calibrate result carries (SPEC §12.2 item 5: device, OS build and date travel
// with MEASURED) and the display scale the measurements run at. The model names cover the identifiers this project
// meets; any other device shows its raw identifier (never a guessed name).
@MainActor
enum CalibrationDevice {
    static func stamp(gpu: GPUContext?) -> DeviceStamp {
        var system = utsname()
        uname(&system)
        let machine = withUnsafeBytes(of: &system.machine) { raw in String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self) }
        #if targetEnvironment(simulator)
        let simulator = true
        #else
        let simulator = false
        #endif
        let device = gpu?.device ?? MTLCreateSystemDefaultDevice()
        return DeviceStamp(deviceModel: modelName(machine), gpuName: device?.name ?? "", gpuFamily: device.map { GPUContext.familyName($0) } ?? "",
                           osVersion: "iOS " + UIDevice.current.systemVersion, osBuild: osBuild(), isSimulator: simulator, date: Date(),
                           thermal: thermal(ProcessInfo.processInfo.thermalState),
                           lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }

    static func modelName(_ machine: String) -> String {
        ["iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max", "iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max",
         "iPhone17,3": "iPhone 16", "iPhone17,4": "iPhone 16 Plus", "iPhone18,1": "iPhone 17 Pro", "iPhone18,2": "iPhone 17 Pro Max"][machine] ?? machine
    }

    /// `kern.osversion` ("24A5355p").
    static func osBuild() -> String {
        var size = 0
        sysctlbyname("kern.osversion", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: Swift.max(size, 1))
        sysctlbyname("kern.osversion", &buffer, &size, nil, 0)
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    static func thermal(_ state: ProcessInfo.ThermalState) -> ThermalLevel {
        switch state {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .unknown
        }
    }

    /// The display scale of the app's window scene (3 on the iPhone 15 Pro Max).
    static var displayScale: Double {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return Double(scene?.screen.scale ?? 3)
    }

    static var keyWindow: UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
    }
}
