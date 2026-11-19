//
//  InterfaceAddressTable.swift
//  PixelHandCore
//
//  Which interface owns each local address, read with `getifaddrs`. The
//  link judge uses it to find the interface carrying a connection from the
//  connection's local address, when the address has no `%zone`.
//

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum InterfaceAddressTable {
    /// Unscoped, lower-case numeric address → interface name, for every
    /// IPv4 and IPv6 address on this machine. Empty if `getifaddrs` fails.
    public static func current() -> [String: String] {
        var owners: [String: String] = [:]
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return owners }
        defer { freeifaddrs(head) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let address = entry.pointee.ifa_addr,
                  let host = numericHost(address)
            else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            // First owner wins: an address is on one interface.
            if owners[host] == nil { owners[host] = name }
        }
        return owners
    }

    private static func string(from buffer: [CChar]) -> String {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func numericHost(_ address: UnsafeMutablePointer<sockaddr>) -> String? {
        let family = Int32(address.pointee.sa_family)
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN) + 1)
        switch family {
        case AF_INET:
            return address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
                var addr = sin.pointee.sin_addr
                guard inet_ntop(AF_INET, &addr, &buffer, socklen_t(buffer.count)) != nil else { return nil }
                return LinkJudge.unscoped(string(from: buffer))
            }
        case AF_INET6:
            return address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { sin6 in
                var addr = sin6.pointee.sin6_addr
                guard inet_ntop(AF_INET6, &addr, &buffer, socklen_t(buffer.count)) != nil else { return nil }
                return LinkJudge.unscoped(string(from: buffer))
            }
        default:
            return nil
        }
    }
}
