//
//  VendorLookup.swift
//  Fieldwatch
//
//  Offline vendor / company / service identification.
//  radiodb.bin is a legacy blob and is NOT parsed; this curated table
//  covers the devices users actually encounter.
//

import Foundation

public struct VendorLookup: Sendable {

    // MARK: - Bluetooth SIG Company IDs (subset, high-confidence)
    private static let companies: [Int: String] = [
        0x0000: "Ericsson",
        0x0006: "Microsoft",
        0x0008: "Motorola",
        0x000D: "Texas Instruments",
        0x000F: "Broadcom",
        0x001D: "Qualcomm",
        0x0032: "Vefa",
        0x004C: "Apple",
        0x0059: "Nordic Semiconductor",
        0x005D: "Realtek",
        0x0065: "Cypress / Infineon",
        0x0075: "Samsung",
        0x0078: "Parrot",
        0x0087: "Garmin",
        0x008E: "CSR",
        0x009E: "Bose",
        0x00A7: "Meta / Oculus",
        0x00E0: "Google",
        0x011B: "Sony",
        0x0131: "Huawei",
        0x0157: "Radius Networks (AltBeacon)",
        0x0171: "Amazon (Lab126)",
        0x018C: "Espressif (ESP32)",
        0x01A9: "Anker",
        0x02A1: "Xiaomi",
        0x038F: "JBL / Harman",
        0x03E0: "OPPO",
        0x0471: "Tile",
        0x0499: "Ruuvi",
        0x0550: "Nuki (Smart Lock)",
        0x0578: "SwitchBot",
        0x05A7: "Tesla",
        0x06D5: "Flipper Devices",
        0x0B05: "Ledger",
        0x0C5B: "Withings",
        0x0D50: "DJI (Drone)",
        0x0E48: "Polar",
        0x0F63: "Decathlon",
        0x10A3: "Logitech",
        0x1233: "Nothing",
        0xFFFF: "Test / Reserved"
    ]

    public static func companyName(for id: Int) -> String? {
        if let db = RadioDb.shared.company(id) { return db }
        return companies[id]
    }

    // MARK: - Common Wi-Fi OUIs (AA:BB:CC -> vendor)
    private static let ouis: [String: String] = [
        "00:1B:63": "Apple", "00:1E:C2": "Apple", "00:21:E9": "Apple",
        "00:23:12": "Apple", "00:25:00": "Apple", "3C:06:30": "Apple",
        "40:CB:C0": "Apple", "48:60:BC": "Apple", "4C:57:CA": "Apple",
        "64:B9:E8": "Apple", "78:31:C1": "Apple", "8C:29:37": "Apple",
        "F0:18:98": "Apple", "F4:F1:5A": "Apple",
        "00:0D:93": "Apple",
        "28:11:A5": "Samsung", "5C:31:3E": "Samsung", "78:59:5E": "Samsung",
        "8C:F5:A3": "Samsung", "E4:9A:DC": "Samsung",
        "38:AA:3C": "Xiaomi", "64:CC:2E": "Xiaomi", "7C:2F:80": "Xiaomi",
        "14:F6:5A": "Huawei", "24:4B:FE": "Huawei", "48:62:76": "Huawei",
        "00:1A:11": "Google", "3C:5A:37": "Google", "54:60:09": "Google",
        "00:1A:79": "Sony", "30:10:B3": "Sony",
        "00:50:C2": "Intel", "34:E6:AD": "Intel", "40:A8:F0": "Intel",
        "00:0F:B3": "Actiontec", "00:15:05": "Actiontec",
        "00:1F:90": "Actiontec", "18:1E:78": "Actiontec",
        "C0:05:C2": "Actiontec", "E4:22:A5": "Actiontec",
        "14:91:82": "Arcadyan",
        "5C:E0:CA": "TP-Link", "60:A4:B7": "TP-Link", "B0:95:8E": "TP-Link",
        "00:23:69": "Cisco", "00:62:EC": "Cisco", "58:AC:78": "Cisco",
        "00:01:36": "CyberTAN", "00:0E:58": "Netgear",
        "20:E5:2A": "Netgear", "28:C6:8E": "Netgear", "2C:30:33": "Netgear",
        "00:14:BF": "D-Link", "1C:7E:E5": "D-Link", "90:94:E4": "D-Link",
        "00:18:39": "Ubiquiti", "24:A4:3C": "Ubiquiti", "68:D7:9A": "Ubiquiti",
        "04:18:D6": "Ubiquiti", "74:83:C2": "Ubiquiti",
        "00:0C:43": "Raspberry Pi", "B8:27:EB": "Raspberry Pi", "D8:3A:DD": "Raspberry Pi",
        "DC:A6:32": "Raspberry Pi", "E4:5F:01": "Raspberry Pi",
        "24:0A:C4": "Espressif", "30:AE:A4": "Espressif", "3C:61:05": "Espressif",
        "7D:DF:A1": "Espressif", "A4:CF:12": "Espressif",
        "FC:F5:C4": "Espressif", "24:6F:28": "Espressif",
        "00:1E:06": "Wistron", "AC:37:43": "HTC",
        "D8:50:E6": "ASUSTek", "04:D9:F5": "ASUSTek",
        "18:C5:01": "Hon Hai (Foxconn)", "F8:0D:AC": "Hon Hai",
        "A4:17:31": "Hon Hai", "0C:8B:FD": "Hon Hai"
    ]

    public static func ouiVendor(for oui: String) -> String? {
        if let db = RadioDb.shared.vendorForOui24(oui) { return db }
        let key = oui.uppercased()
        if let hit = ouis[key] { return hit }
        let compact = key.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "")
        if compact.count >= 6 {
            let a = compact.prefix(2); let b = compact.dropFirst(2).prefix(2); let c = compact.dropFirst(4).prefix(2)
            return ouis["\(a):\(b):\(c)"]
        }
        return nil
    }

    // MARK: - GATT / Service UUIDs (16-bit + common 128-bit markers)
    private static let services: [String: String] = [
        "1800": "Generic Access", "1801": "Generic Attribute",
        "180A": "Device Information", "180D": "Heart Rate",
        "180F": "Battery Service", "181A": "Environmental Sensing",
        "181B": "Body Composition", "181C": "User Data",
        "181D": "Weight Scale", "1826": "Fitness Machine",
        "FEAA": "Eddystone Beacon", "FE2C": "Google Fast Pair",
        "FD6F": "Exposure Notification", "FEE7": "Tuya",
        "FEED": "Tile Tracker", "FEE0": "Joan Board",
        "FE9F": "Google Nearby", "FDCD": "Qualcomm",
        "FFFA": "OpenDroneID / Remote ID",
        "1802": "Immediate Alert", "1803": "Link Loss",
        "1804": "Tx Power", "1805": "Current Time",
        "180E": "Blood Pressure", "1812": "HID",
        "1822": "Pulse Oximeter", "183E": "Bond Management"
    ]

    public static func serviceName(for uuid: String) -> String? {
        if let db = RadioDb.shared.serviceUuid(uuid) { return db }
        let u = uuid.uppercased().replacingOccurrences(of: "-", with: "")
        for (short, name) in services where u.contains(short) {
            return name
        }
        return nil
    }
}
