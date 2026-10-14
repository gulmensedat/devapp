import Foundation
import Darwin

/// Yerel portların dinlenip dinlenmediğini ve hangi sürecin tuttuğunu bulur.
enum PortMonitor {

    /// 127.0.0.1 ya da ::1 üzerinde dinleyen var mı (Node 17+ "localhost"u sadece ::1'e bağlayabiliyor).
    static func isListening(_ port: Int) -> Bool {
        connectIPv4(port) || connectIPv6(port)
    }

    static func listening(_ ports: Set<Int>) async -> Set<Int> {
        await Task.detached(priority: .utility) {
            Set(ports.filter { isListening($0) })
        }.value
    }

    private static func connectIPv4(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(truncatingIfNeeded: port).bigEndian)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    private static func connectIPv6(_ port: Int) -> Bool {
        let fd = socket(AF_INET6, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_in6()
        addr.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        addr.sin6_family = sa_family_t(AF_INET6)
        addr.sin6_port = in_port_t(UInt16(truncatingIfNeeded: port).bigEndian)
        addr.sin6_addr = in6addr_loopback
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in6>.size))
            }
        }
        return result == 0
    }

    struct Owner {
        let pid: Int32
        let name: String
    }

    /// Portu dinleyen süreci lsof ile bulur.
    static func owner(of port: Int) async -> Owner? {
        await Task.detached(priority: .userInitiated) { () -> Owner? in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            p.arguments = ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-Fpc"]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            do { try p.run() } catch { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            var pid: Int32?
            var name = "?"
            for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                if line.hasPrefix("p"), pid == nil { pid = Int32(line.dropFirst()) }
                else if line.hasPrefix("c"), name == "?" { name = String(line.dropFirst()) }
            }
            return pid.map { Owner(pid: $0, name: name) }
        }.value
    }
}
