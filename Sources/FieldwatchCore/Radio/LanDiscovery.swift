//
//  LanDiscovery.swift
//  Fieldwatch
//
//  Stock-iOS legal LAN device discovery. Apple forbids passive 802.11
//  scans, but anything your own network freely advertises is fair game:
//  Bonjour/mDNS service adverts, SSDP (UPnP) NOTIFY/M-SEARCH answers,
//  and a polite TCP handshake sweep of the local /24.
//

import Foundation
import Network
#if canImport(Darwin)
import Darwin
#endif

public final class LanDiscovery: NSObject, @unchecked Sendable {
    public static let shared = LanDiscovery()

    public weak var delegate: WifiScannerDelegate?

    private let queue = DispatchQueue(label: "app.fieldwatch.lan", qos: .utility)
    private var running = false

    // Bonjour
    private var browsers: [NetServiceBrowser] = []
    private var pendingResolve: Set<NetService> = []
    private var seenServices: Set<String> = []

    // SSDP
    private var ssdpListener: NWListener?
    private var lastSsdpBurst: Date = .distantPast

    // Subnet sweep
    private var lastSweep: Date = .distantPast
    private var sweeping = false

    // Last seen gateway (subnet base .1) for the router-panel shortcut.
    public private(set) var lastGateway: String?

    private static let bonjourTypes = [
        "_hap._tcp.", "_airplay._tcp.", "_raop._tcp.",
        "_mediaremotetv._tcp.", "_companion-link._tcp.",
        "_device-info._tcp.", "_home-sharing._tcp.",
        "_printer._tcp.", "_ipp._tcp.", "_ipps._tcp.",
        "_http._tcp.", "_ssh._tcp.", "_smb._tcp.",
        "_googlecast._tcp.", "_spotify-connect._tcp.",
        "_sonos._tcp.", "_daap._tcp.", "_touch-remote._tcp.",
        "_sleep-proxy._udp.",
    ]

    private override init() { super.init() }

    // MARK: - Lifecycle (called from WifiScanner)

    public func start() {
        queue.async {
            guard !self.running else { return }
            self.running = true
            self.seenServices.removeAll()
            DispatchQueue.main.async { self.startBrowsers() }
            self.startSsdpListener()
        }
    }

    public func stop() {
        queue.async {
            guard self.running else { return }
            self.running = false
            DispatchQueue.main.async { self.stopBrowsers() }
            self.ssdpListener?.cancel()
            self.ssdpListener = nil
        }
    }

    /// Called on every Wi-Fi scan cycle; internally throttled.
    public func scanTick() {
        queue.async {
            guard self.running else { return }
            let now = Date()
            if now.timeIntervalSince(self.lastSsdpBurst) > 30 {
                self.lastSsdpBurst = now
                self.ssdpBurst()
            }
            if now.timeIntervalSince(self.lastSweep) > 90 {
                self.lastSweep = now
                self.sweepSubnetThrottled()
            }
        }
    }

    // MARK: - Bonjour

    private func startBrowsers() {
        stopBrowsers()
        for type in Self.bonjourTypes {
            let b = NetServiceBrowser()
            b.delegate = self
            browsers.append(b)
            b.searchForServices(ofType: type, inDomain: "local.")
        }
    }

    private func stopBrowsers() {
        for b in browsers { b.stop() }
        browsers.removeAll()
        for s in pendingResolve { s.stop() }
        pendingResolve.removeAll()
    }

    private func resolved(service: NetService) {
        let key = "\(service.type)\(service.name)"
        guard seenServices.insert(key).inserted else { return }
        let ip = service.addresses?.compactMap { sockaddrToIP($0) }.first
        let host = service.hostName
        let identifier = ip ?? host ?? service.name
        let kindFacts = RadioFacts()
        let obs = Observation(
            timestamp: Date(),
            kind: .wifi,
            identifier: identifier,
            name: "\(service.name) (\(bonjourLabel(service.type)))",
            rssi: -60,
            location: nil,
            facts: kindFacts
        )
        delegate?.wifiScannerDidObserve(obs)
    }

    private func bonjourLabel(_ type: String) -> String {
        switch type {
        case "_hap._tcp.": return "HomeKit"
        case "_airplay._tcp.": return "AirPlay"
        case "_raop._tcp.": return "AirPlay audio"
        case "_mediaremotetv._tcp.": return "Apple TV remote"
        case "_companion-link._tcp.": return "Apple Continuity"
        case "_device-info._tcp.": return "Apple device"
        case "_home-sharing._tcp.": return "Home Sharing"
        case "_printer._tcp.", "_ipp._tcp.", "_ipps._tcp.": return "Printer"
        case "_http._tcp.": return "Web service"
        case "_ssh._tcp.": return "SSH"
        case "_smb._tcp.": return "File share"
        case "_googlecast._tcp.": return "Chromecast"
        case "_spotify-connect._tcp.": return "Spotify"
        case "_sonos._tcp.": return "Sonos"
        case "_daap._tcp.", "_touch-remote._tcp.": return "Media"
        case "_sleep-proxy._udp.": return "Sleep proxy"
        default: return "LAN"
        }
    }

    private func sockaddrToIP(_ data: Data) -> String? {
        guard data.count >= MemoryLayout<sockaddr>.size else { return nil }
        return data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> String? in
            guard let base = ptr.baseAddress else { return nil }
            let sa = base.assumingMemoryBound(to: sockaddr.self).pointee
            if sa.sa_family == sa_family_t(AF_INET) {
                guard data.count >= MemoryLayout<sockaddr_in>.size else { return nil }
                var addr = base.assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr
                var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                guard inet_ntop(AF_INET, &addr, &buf, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
                return String(cString: buf)
            } else if sa.sa_family == sa_family_t(AF_INET6) {
                guard data.count >= MemoryLayout<sockaddr_in6>.size else { return nil }
                var addr = base.assumingMemoryBound(to: sockaddr_in6.self).pointee.sin6_addr
                var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                guard inet_ntop(AF_INET6, &addr, &buf, socklen_t(INET6_ADDRSTRLEN)) != nil else { return nil }
                return String(cString: buf)
            }
            return nil
        }
    }
}

// MARK: - NetService delegates (main thread)
extension LanDiscovery: NetServiceBrowserDelegate, NetServiceDelegate {
    public func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        pendingResolve.insert(service)
        service.resolve(withTimeout: 4.0)
        if !moreComing {
            // Trim stale pending resolves so one bad host can't pin memory.
            if pendingResolve.count > 64 {
                for s in pendingResolve.prefix(16) { s.stop() }
            }
        }
    }

    public func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
    }

    public func netServiceDidResolveAddress(_ sender: NetService) {
        pendingResolve.remove(sender)
        sender.stop()
        resolved(service: sender)
    }

    public func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        pendingResolve.remove(sender)
    }
}

// MARK: - SSDP + subnet sweep (background queue)
extension LanDiscovery {
    private func ssdpBurst() {
        let msg = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ns:discover\"\r\nMX: 2\r\nST: ssdp:all\r\n\r\n"
        guard let data = msg.data(using: .utf8) else { return }
        let conn = NWConnection(host: "239.255.255.250", port: 1900, using: .udp)
        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                conn.send(content: data, completion: .contentProcessed({ _ in
                    conn.cancel()
                }))
            case .failed, .cancelled:
                conn.cancel()
            default:
                break
            }
        }
        conn.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 3.0) { conn.cancel() }
    }

    private func startSsdpListener() {
        guard let port = NWEndpoint.Port(rawValue: 1900) else { return }
        do {
            let listener = try NWListener(using: .udp, on: port)
            listener.newConnectionHandler = { [weak self] conn in
                conn.start(queue: .global(qos: .utility))
                self?.receiveSsdp(conn)
            }
            listener.start(queue: queue)
            ssdpListener = listener
        } catch {
            ssdpListener = nil // No multicast receive on this profile; SSDP answers just won't arrive.
        }
    }

    private func receiveSsdp(_ conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, _, error in
            if let data = data, error == nil {
                self?.queue.async { self?.handleSsdp(data) }
            }
            if error == nil {
                self?.receiveSsdp(conn)
            }
        }
    }

    private func handleSsdp(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
        var headers: [String: String] = [:]
        for line in text.components(separatedBy: "\r\n").dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).uppercased()
            headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let location = headers["LOCATION"] ?? ""
        let server = headers["SERVER"] ?? ""
        let usn = headers["USN"] ?? headers["ST"] ?? ""
        guard !location.isEmpty || !usn.isEmpty else { return }
        let host: String
        var ip = ""
        if let url = URL(string: location), let h = url.host {
            host = h; ip = h
        } else {
            host = usn
        }
        let name: String
        if !server.isEmpty {
            name = "\(server) (UPnP)"
        } else if !usn.isEmpty {
            name = "\(usn.prefix(48)) (UPnP)"
        } else {
            name = "UPnP device"
        }
        _ = host
        let obs = Observation(
            timestamp: Date(), kind: .wifi,
            identifier: ip.isEmpty ? name : ip,
            name: name, rssi: -60, location: nil, facts: RadioFacts()
        )
        delegate?.wifiScannerDidObserve(obs)
        if let url = URL(string: location), !location.isEmpty {
            fetchSsdpDescription(url: url, fallbackIp: ip)
        }
    }

    private func fetchSsdpDescription(url: URL, fallbackIp: String) {
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let xml = String(data: data, encoding: .utf8) else { return }
            func tag(_ name: String) -> String? {
                guard let r = xml.range(of: "<\(name)>(.*?)</\(name)>", options: [.regularExpression, .caseInsensitive]) else { return nil }
                var v = String(xml[r])
                v = v.replacingOccurrences(of: "<\(name)>", with: "", options: .caseInsensitive)
                v = v.replacingOccurrences(of: "</\(name)>", with: "", options: .caseInsensitive)
                let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
                return t.isEmpty ? nil : t
            }
            let friendly = tag("friendlyName") ?? tag("modelName") ?? "UPnP device"
            let obs = Observation(
                timestamp: Date(), kind: .wifi,
                identifier: fallbackIp.isEmpty ? friendly : fallbackIp,
                name: friendly, rssi: -60, location: nil, facts: RadioFacts()
            )
            self?.delegate?.wifiScannerDidObserve(obs)
        }
        task.resume()
    }

    // MARK: Subnet sweep

    private func sweepSubnetThrottled() {
        guard !sweeping else { return }
        guard let hosts = lanHosts(), !hosts.isEmpty else { return }
        sweeping = true
        let ops = OperationQueue()
        ops.maxConcurrentOperationCount = 48
        for host in hosts {
            ops.addOperation { [weak self] in self?.probeHost(host) }
        }
        ops.waitUntilAllOperationsAreFinished()
        sweeping = false
    }

    private func lanHosts() -> [String]? {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return nil }
        defer { freeifaddrs(addrs) }
        var ip: UInt32 = 0
        var mask: UInt32 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let c = cursor {
            cursor = c.pointee.ifa_next
            guard String(cString: c.pointee.ifa_name) == "en0" else { continue }
            // NOTE: ifa_addr / ifa_netmask can be NULL (VPN, tunnels).
            // Dereferencing them blindly crashes the app the moment scan starts.
            guard let addrPtr = c.pointee.ifa_addr,
                  let maskPtr = c.pointee.ifa_netmask,
                  addrPtr.pointee.sa_family == sa_family_t(AF_INET),
                  maskPtr.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            ip = addrPtr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                UInt32(littleEndian: $0.pointee.sin_addr.s_addr)
            }
            mask = maskPtr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                UInt32(littleEndian: $0.pointee.sin_addr.s_addr)
            }
            break
        }
        guard mask != 0 else { return nil }
        let hostBits = 32 - mask.nonzeroBitCount
        guard hostBits >= 1 && hostBits <= 8 else { return nil } // /24 or smaller only
        let base = ip & mask
        let b0 = base & 0xFF, b1 = (base >> 8) & 0xFF, b2 = (base >> 16) & 0xFF, b3 = (base >> 24) & 0xFF
        lastGateway = "\(b0).\(b1).\(b2).\(b3 + 1)"
        let count = 1 << hostBits
        var out: [String] = []
        out.reserveCapacity(count)
        for i in 1..<(count - 1) {
            let h = base | UInt32(i)
            let b0 = h & 0xFF, b1 = (h >> 8) & 0xFF, b2 = (h >> 16) & 0xFF, b3 = (h >> 24) & 0xFF
            out.append("\(b0).\(b1).\(b2).\(b3)")
        }
        let selfIp = "\(ip & 0xFF).\((ip >> 8) & 0xFF).\((ip >> 16) & 0xFF).\((ip >> 24) & 0xFF)"
        return out.filter { $0 != selfIp }
    }

    private static let sweepPorts: [(UInt16, String)] = [
        (62078, "iPhone / iPad (sync)"),
        (7000, "AirPlay receiver"),
        (8009, "Chromecast"),
        (1400, "Sonos speaker"),
        (9100, "Printer (JetDirect)"),
        (631, "Printer (IPP)"),
        (80, "Web device"),
        (443, "Web device (TLS)"),
        (22, "SSH device"),
    ]

    private func probeHost(_ host: String) {
        for (port, label) in Self.sweepPorts {
            if tryTcp(host: host, port: port, timeout: 0.35) {
                let obs = Observation(
                    timestamp: Date(), kind: .wifi,
                    identifier: host, name: "\(label) @ \(host)",
                    rssi: -60, location: nil, facts: RadioFacts()
                )
                delegate?.wifiScannerDidObserve(obs)
                return
            }
        }
    }

    private func tryTcp(host: String, port: UInt16, timeout: TimeInterval) -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return false }
        let conn = NWConnection(host: .name(host, nil), port: nwPort, using: .tcp)
        let sema = DispatchSemaphore(value: 0)
        var ok = false
        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                ok = true
                sema.signal()
            case .failed, .cancelled:
                sema.signal()
            default:
                break
            }
        }
        conn.start(queue: .global(qos: .utility))
        _ = sema.wait(timeout: .now() + timeout)
        conn.cancel()
        return ok
    }
}
