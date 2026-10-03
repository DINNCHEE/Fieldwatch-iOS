//
//  RadioDb.swift
//  Fieldwatch
//
//  Offline assigned-number tables (IEEE MA-L/M/S/CID + Bluetooth SIG),
//  parsed from Resources/radiodb.bin. Direct port of the Android
//  RadioDb object: same SPLK v1 layout, same binary-search queries.
//

import Foundation

public final class RadioDb: @unchecked Sendable {
    public static let shared = RadioDb()

    private let lock = NSLock()
    private var ready = false

    private var malKeys: [UInt32] = []
    private var malIdx: [Int] = []
    private var cidKeys: [UInt32] = []
    private var cidIdx: [Int] = []
    private var longKeys: [UInt64] = []
    private var longIdx: [Int] = []
    private var btKeys: [UInt32] = []
    private var btIdx: [Int] = []
    private var appKeys: [UInt32] = []
    private var appIdx: [Int] = []
    private var uuidKeys: [UInt32] = []
    private var uuidIdx: [Int] = []
    private var nameOff: [Int] = []
    private var nameBlob = Data()

    public var builtYmd: Int = 0
    public var nameCount: Int = 0

    public init() {}

    public var isReady: Bool {
        lock.lock(); defer { lock.unlock() }
        return ready
    }

    @discardableResult
    public func load() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if ready { return true }
        #if SWIFT_PACKAGE
        let urls = [Bundle.module.url(forResource: "radiodb", withExtension: "bin"),
                    Bundle.main.url(forResource: "radiodb", withExtension: "bin")].compactMap { $0 }
        #else
        let urls = [Bundle.main.url(forResource: "radiodb", withExtension: "bin")].compactMap { $0 }
        #endif
        guard let url = urls.first,
              let bytes = try? Data(contentsOf: url) else { return false }
        guard parse(bytes) else { return false }
        ready = true
        return true
    }

    // MARK: - Queries (mirror Android API)

    public func vendorForMac(_ mac: String) -> String? {
        ensureLoaded()
        let hex = mac.filter { $0.isLetter || $0.isNumber }.uppercased()
        guard !hex.isEmpty else { return nil }
        if isRandomized(mac) {
            guard let univ = wifiOui24Universal(mac),
                  let name = vendorForOui24(univ),
                  !isPhoneHouseVendor(name) else { return nil }
            return name
        }
        if hex.count >= 9, let key = UInt64(hex.prefix(9), radix: 16) {
            if let n = longName(bits: 36, prefix: key) { return n }
        }
        if hex.count >= 7, let key = UInt64(hex.prefix(7), radix: 16) {
            if let n = longName(bits: 28, prefix: key) { return n }
        }
        if hex.count >= 6, let key = UInt32(hex.prefix(6), radix: 16) {
            return u32Name(malKeys, malIdx, key)
        }
        return nil
    }

    public func vendorForOui24(_ oui: String) -> String? {
        ensureLoaded()
        let hex = oui.filter { $0.isLetter || $0.isNumber }.uppercased()
        guard hex.count >= 6, let key = UInt32(hex.prefix(6), radix: 16) else { return nil }
        return u32Name(malKeys, malIdx, key) ?? u32Name(cidKeys, cidIdx, key)
    }

    public func company(_ id: Int) -> String? {
        ensureLoaded()
        return u16Name(btKeys, btIdx, UInt32(id & 0xFFFF))
    }

    public func appearance(_ value: Int) -> String? {
        ensureLoaded()
        let v = UInt32(value & 0xFFFF)
        if let n = u16Name(appKeys, appIdx, v) { return n }
        let category = v & 0xFFC0
        if category != v, let n = u16Name(appKeys, appIdx, category) { return n }
        return nil
    }

    public func serviceUuid(_ uuid: String) -> String? {
        ensureLoaded()
        let hex = uuid.filter { $0.isLetter || $0.isNumber }.uppercased()
        let short: UInt32?
        if hex.count == 4 {
            short = UInt32(hex, radix: 16)
        } else if hex.count == 8 {
            short = UInt32(hex.suffix(4), radix: 16)
        } else if hex.count == 32 && hex.hasPrefix("0000") && hex.hasSuffix("00001000800000805F9B34FB") {
            short = UInt32(hex.dropFirst(4).prefix(4), radix: 16)
        } else {
            short = nil
        }
        guard let s = short else { return nil }
        return u16Name(uuidKeys, uuidIdx, s)
    }

    // MARK: - MAC helpers (MacUtil port)

    public func isRandomized(_ mac: String) -> Bool {
        let norm = normalizeMac(mac)
        let firstHex = norm.split(separator: ":").first.map(String.init) ?? ""
        guard let first = UInt8(firstHex, radix: 16) else { return false }
        return (first & 0x02) != 0 && (first & 0x01) == 0
    }

    public func wifiOui24Universal(_ mac: String) -> String? {
        let hex = normalizeMac(mac).replacingOccurrences(of: ":", with: "")
        guard hex.count >= 6,
              let first = UInt8(hex.prefix(2), radix: 16),
              (first & 0x02) != 0, (first & 0x01) == 0 else { return nil }
        return String(format: "%02X", first & 0xFD) + String(hex.dropFirst(2).prefix(4))
    }

    public func normalizeMac(_ raw: String) -> String {
        let hex = raw.filter { $0.isLetter || $0.isNumber }.uppercased()
        guard hex.count >= 2 else { return raw.uppercased() }
        var out = ""
        var i = hex.startIndex
        while i < hex.endIndex {
            if !out.isEmpty { out.append(":") }
            let j = hex.index(i, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            out += hex[i..<j]
            i = j
        }
        return out
    }

    // MARK: - Private search

    private func ensureLoaded() {
        if !isReady { _ = load() }
    }

    private func longName(bits: Int, prefix: UInt64) -> String? {
        let key = (UInt64(bits) << 56) | prefix
        var lo = 0, hi = longKeys.count - 1
        while lo <= hi {
            let mid = (lo + hi) >> 1
            let v = longKeys[mid]
            if v < key { lo = mid + 1 }
            else if v > key { hi = mid - 1 }
            else { return nameAt(longIdx[mid]) }
        }
        return nil
    }

    private func u32Name(_ keys: [UInt32], _ idx: [Int], _ target: UInt32) -> String? {
        var lo = 0, hi = keys.count - 1
        while lo <= hi {
            let mid = (lo + hi) >> 1
            let v = keys[mid]
            if v < target { lo = mid + 1 }
            else if v > target { hi = mid - 1 }
            else { return nameAt(idx[mid]) }
        }
        return nil
    }

    private func u16Name(_ keys: [UInt32], _ idx: [Int], _ target: UInt32) -> String? {
        u32Name(keys, idx, target)
    }

    private func nameAt(_ index: Int) -> String? {
        guard index >= 0, index + 1 < nameOff.count else { return nil }
        let start = nameOff[index], end = nameOff[index + 1]
        guard start >= 0, end <= nameBlob.count, end >= start else { return nil }
        return String(data: nameBlob.subdata(in: start..<end), encoding: .utf8)
    }

    private func isPhoneHouseVendor(_ vendor: String) -> Bool {
        let v = vendor.lowercased()
        return ["apple", "google", "samsung electronics", "microsoft"].contains { v.contains($0) }
    }

    // MARK: - Binary parse (SPLK v1, little-endian)

    private struct Cursor {
        let data: Data
        var off: Int = 0
        /// Bytes left from current position. Every section checks this
        /// before looping so a corrupt file returns false, never traps.
        func require(_ n: Int) -> Bool { n >= 0 && off + n <= data.count }
        mutating func u8() -> UInt8 { defer { off += 1 }; return data[off] }
        mutating func u16() -> UInt16 {
            let v = UInt16(data[off]) | (UInt16(data[off + 1]) << 8); off += 2; return v
        }
        mutating func i16() -> Int16 { Int16(bitPattern: u16()) }
        mutating func u32() -> UInt32 {
            let v = UInt32(data[off]) | (UInt32(data[off+1]) << 8) | (UInt32(data[off+2]) << 16) | (UInt32(data[off+3]) << 24)
            off += 4; return v
        }
        mutating func i32() -> Int32 { Int32(bitPattern: u32()) }
        mutating func u64() -> UInt64 {
            var v: UInt64 = 0
            for i in 0..<8 { v |= UInt64(data[off + i]) << (8 * i) }
            off += 8; return v
        }
        mutating func bytes(_ n: Int) -> Data { defer { off += n }; return data.subdata(in: off..<(off + n)) }
    }

    private func parse(_ bytes: Data) -> Bool {
        guard bytes.count > 16 else { return false }
        var c = Cursor(data: bytes)
        let magic = c.bytes(4)
        guard magic == Data([0x53, 0x50, 0x4C, 0x4B]) else { return false } // "SPLK"
        let version = c.u16()
        _ = c.u16()
        guard version == 1 else { return false }
        builtYmd = Int(c.i32())
        let nsec = Int(c.i32())
        guard nsec > 0, nsec < 64 else { return false }
        var sections: [String: Int] = [:]
        for _ in 0..<nsec {
            let tag = String(data: c.bytes(4), encoding: .ascii)?.trimmingCharacters(in: .controlCharacters) ?? ""
            sections[tag] = Int(c.i32())
        }
        func slice(_ tag: String) -> Cursor? {
            guard let off = sections[tag], off >= 0, off < bytes.count else { return nil }
            var s = Cursor(data: bytes); s.off = off; return s
        }
        guard var b = slice("mal") else { return false }
        malKeys = []; malIdx = []
        // NOTE: packer writes ALL keys first, then ALL indices (not interleaved).
        var n = Int(b.i32())
        guard n >= 0, n < 100000, b.require(n * 6) else { return false }
        for _ in 0..<n { malKeys.append(b.u32()) }
        for _ in 0..<n { malIdx.append(Int(b.i16())) }
        guard var q = slice("cid") else { return false }
        n = Int(q.i32())
        guard n >= 0, n < 100000, q.require(n * 6) else { return false }
        for _ in 0..<n { cidKeys.append(q.u32()) }
        for _ in 0..<n { cidIdx.append(Int(q.i16())) }
        guard var l = slice("long") else { return false }
        n = Int(l.i32())
        guard n >= 0, n < 100000, l.require(n * 10) else { return false }
        for _ in 0..<n { longKeys.append(l.u64()) }
        for _ in 0..<n { longIdx.append(Int(l.i16())) }
        guard var t = slice("btc") else { return false }
        n = Int(t.i32())
        guard n >= 0, n < 100000, t.require(n * 4) else { return false }
        for _ in 0..<n { btKeys.append(UInt32(t.u16())) }
        for _ in 0..<n { btIdx.append(Int(t.i16())) }
        guard var a = slice("app") else { return false }
        n = Int(a.i32())
        guard n >= 0, n < 100000, a.require(n * 4) else { return false }
        for _ in 0..<n { appKeys.append(UInt32(a.u16())) }
        for _ in 0..<n { appIdx.append(Int(a.i16())) }
        guard var u = slice("uuid") else { return false }
        n = Int(u.i32())
        guard n >= 0, n < 100000, u.require(n * 4) else { return false }
        for _ in 0..<n { uuidKeys.append(UInt32(u.u16())) }
        for _ in 0..<n { uuidIdx.append(Int(u.i16())) }
        guard var f = slice("noff") else { return false }
        n = Int(f.i32())
        guard n >= 0, n < 200000, f.require((n + 1) * 4) else { return false }
        nameCount = n
        nameOff = []
        for _ in 0...n { nameOff.append(Int(f.i32())) }
        guard let nstrAt = sections["nstr"], let last = nameOff.last,
              nstrAt >= 0, nstrAt + last <= bytes.count else { return false }
        nameBlob = bytes[nstrAt..<(nstrAt + last)]
        return true
    }
}
