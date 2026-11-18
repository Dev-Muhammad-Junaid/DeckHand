//
//  USBNetworkProbe.swift
//  DeckHandMac
//
//  S13: is a network interface a USB cable to an iPad or iPhone? Walks the
//  IOKit service plane from the interface (found by its BSD name) up towards
//  the USB device and lets `WiredLinkPolicy` (PixelHandCore) decide from the
//  class names and USB properties on the way. Public IOKit only.
//

import Foundation
import IOKit

enum USBNetworkProbe {
    /// `true` for a USB CDC-NCM link to an Apple device, `false` for any
    /// other interface IOKit knows, `nil` when IOKit has no interface by
    /// that name (a tunnel, for example).
    static func isUSBTether(bsdName: String) -> Bool? {
        guard let chain = ancestry(ofInterface: bsdName) else { return nil }
        return WiredLinkPolicy.isUSBTether(ancestry: chain)
    }

    /// The interface's service-plane chain, from the interface towards the root.
    static func ancestry(ofInterface bsdName: String) -> [RegistryNode]? {
        guard let matching = IOBSDNameMatching(kIOMainPortDefault, 0, bsdName) else { return nil }
        // Consumes `matching`.
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != IO_OBJECT_NULL else { return nil }

        var chain: [RegistryNode] = []
        var current: io_registry_entry_t = service
        while current != IO_OBJECT_NULL {
            chain.append(node(for: current))
            guard chain.count < WiredLinkPolicy.maxDepth else {
                IOObjectRelease(current)
                break
            }
            var parent: io_registry_entry_t = IO_OBJECT_NULL
            let result = IORegistryEntryGetParentEntry(current, "IOService", &parent)
            IOObjectRelease(current)
            current = result == KERN_SUCCESS ? parent : IO_OBJECT_NULL
        }
        return chain
    }

    private static func node(for entry: io_registry_entry_t) -> RegistryNode {
        let className = (IOObjectCopyClass(entry)?.takeRetainedValue() as String?) ?? ""
        var properties: [String: Int] = [:]
        for key in WiredLinkPolicy.propertyKeys {
            guard let value = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? NSNumber
            else { continue }
            properties[key] = value.intValue
        }
        return RegistryNode(className: className, properties: properties)
    }
}
