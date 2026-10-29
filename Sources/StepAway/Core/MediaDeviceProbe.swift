import CoreMediaIO

/// Reads CoreMediaIO's `DeviceIsRunningSomewhere` flag, which reports that some
/// process is using a camera or microphone. It needs no permission and never
/// opens the device.
enum MediaDeviceProbe {
    static func isAnyDeviceRunning() -> Bool {
        for device in devices() {
            var address = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
            )
            guard CMIOObjectHasProperty(device, &address) else { continue }

            var running: UInt32 = 0
            var used: UInt32 = 0
            let size = UInt32(MemoryLayout<UInt32>.size)
            if CMIOObjectGetPropertyData(device, &address, 0, nil, size, &used, &running) == noErr,
               running != 0 {
                return true
            }
        }
        return false
    }

    /// Zero means the host has no camera or microphone at all, so media-session
    /// detection can never fire there.
    static var deviceCount: Int { devices().count }

    private static func devices() -> [CMIOObjectID] {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        let systemObject = CMIOObjectID(kCMIOObjectSystemObject)

        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size) == noErr else { return [] }

        let count = Int(size) / MemoryLayout<CMIOObjectID>.size
        guard count > 0 else { return [] }

        var devices = [CMIOObjectID](repeating: 0, count: count)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(systemObject, &address, 0, nil, size, &used, &devices) == noErr else { return [] }
        return devices
    }
}
