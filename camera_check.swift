#!/usr/bin/swift

import CoreMediaIO
import Foundation

// Check if ANY camera device is currently streaming using CoreMediaIO
// Exit 0 and print "1" if streaming, exit 1 and print "0" if not

func isCameraStreaming() -> Bool {
    var propertyAddress = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
        mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
    )

    var dataSize: UInt32 = 0
    var result = CMIOObjectGetPropertyDataSize(
        CMIOObjectID(kCMIOObjectSystemObject),
        &propertyAddress,
        0, nil,
        &dataSize
    )

    guard result == kCMIOHardwareNoError else {
        return false
    }

    let deviceCount = Int(dataSize) / MemoryLayout<CMIODeviceID>.size
    guard deviceCount > 0 else {
        return false
    }

    var devices = [CMIODeviceID](repeating: 0, count: deviceCount)
    result = CMIOObjectGetPropertyData(
        CMIOObjectID(kCMIOObjectSystemObject),
        &propertyAddress,
        0, nil,
        dataSize,
        &dataSize,
        &devices
    )

    guard result == kCMIOHardwareNoError else {
        return false
    }

    // Check each device for "isRunningSomewhere" property
    for device in devices {
        var isRunningAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        var isRunning: UInt32 = 0
        var isRunningSize = UInt32(MemoryLayout<UInt32>.size)

        let runningResult = CMIOObjectGetPropertyData(
            device,
            &isRunningAddress,
            0, nil,
            isRunningSize,
            &isRunningSize,
            &isRunning
        )

        if runningResult == kCMIOHardwareNoError && isRunning != 0 {
            return true
        }
    }

    return false
}

if isCameraStreaming() {
    print("1")
    exit(0)
} else {
    print("0")
    exit(1)
}
