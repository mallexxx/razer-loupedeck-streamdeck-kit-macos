//
//  io_serviceExtension.swift
//  StreamDeckKit
//
//  Created by Alexey Martemyanov on 07.11.2024.
//

import IOKit

extension io_service_t {

    /// Retrieve the TTY path
    var ttyPath: String? {
        guard let ttyDevice = IORegistryEntrySearchCFProperty(self, kIOServicePlane, kIOTTYDeviceKey as CFString, kCFAllocatorDefault, IOOptionBits(kIORegistryIterateRecursively)) as? String else { return nil }
        return "/dev/tty." + ttyDevice
    }

}
