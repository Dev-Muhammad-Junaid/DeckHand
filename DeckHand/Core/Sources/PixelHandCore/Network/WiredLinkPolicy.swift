//
//  WiredLinkPolicy.swift
//  PixelHandCore
//
//  When an iPad or iPhone is plugged into a Mac with a USB cable, macOS
//  brings up a network interface for it ("iPad USB") over USB CDC-NCM. The
//  Mac walks the IOKit service plane from that interface up to the USB
//  device (`USBNetworkProbe`, public IOKit) and hands the chain here.
//
//  A chain is a USB tether when it contains
//  - a CDC-NCM function: a USB interface with class 0x02 (CDC) and subclass
//    0x0D (NCM), or a driver whose class name names NCM; and
//  - an Apple USB device (vendor 0x05AC) above it.
//
//  Requiring Apple's vendor ID keeps third-party USB Ethernet adapters,
//  several of which also speak NCM, from reading as a cable to the device.
//

import Foundation

/// One entry of an IOKit service-plane chain: its class and the numeric
/// USB properties the policy reads (`idVendor`, `bInterfaceClass`,
/// `bInterfaceSubClass`, `bDeviceClass`).
public struct RegistryNode: Sendable, Equatable {
    public var className: String
    public var properties: [String: Int]

    public init(className: String, properties: [String: Int] = [:]) {
        self.className = className
        self.properties = properties
    }
}

public enum WiredLinkPolicy {
    public static let appleVendorID = 0x05AC
    public static let cdcInterfaceClass = 0x02
    public static let ncmInterfaceSubclass = 0x0D
    /// How far up the service plane the probe walks. The chain from an
    /// NCM interface to its USB device is well under ten entries.
    public static let maxDepth = 16

    /// The property keys the probe should read for each node.
    public static let propertyKeys = ["idVendor", "bInterfaceClass", "bInterfaceSubClass", "bDeviceClass"]

    /// `ancestry` starts at the network interface and walks towards the root.
    public static func isUSBTether(ancestry: [RegistryNode]) -> Bool {
        let chain = ancestry.prefix(maxDepth)
        guard let ncmIndex = chain.firstIndex(where: isNCMFunction) else { return false }
        // The Apple device sits at or above the NCM function.
        return chain[ncmIndex...].contains { $0.properties["idVendor"] == appleVendorID }
    }

    static func isNCMFunction(_ node: RegistryNode) -> Bool {
        if node.properties["bInterfaceClass"] == cdcInterfaceClass,
           node.properties["bInterfaceSubClass"] == ncmInterfaceSubclass {
            return true
        }
        return node.className.range(of: "NCM", options: .caseInsensitive) != nil
    }
}
