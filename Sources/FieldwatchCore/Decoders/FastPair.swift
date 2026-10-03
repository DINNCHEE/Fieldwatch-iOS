//
//  FastPair.swift
//  Fieldwatch
//
//  Google Fast Pair (UUID FE2C) shapes. Port of the original:
//  3-byte model ID = pairing mode; longer = account key.
//

import Foundation

public struct FastPair: Sendable {
    public static let fleetId = "fleet-fast-pair"

    public static func pairingAdvertised(serviceData: [ServiceDataRecord]) -> Bool {
        serviceData.contains {
            isFastPairUuid($0.uuid) && hexLen($0.dataHex) == 6
        }
    }

    public static func liveLabel(pairing: Bool) -> String {
        pairing ? "Fast Pair pairing" : "Fast Pair"
    }

    public static func isFastPairUuid(_ uuid: String) -> Bool {
        let hex = uuid.filter { $0.isLetter || $0.isNumber }.uppercased()
        if hex == "FE2C" { return true }
        if hex.count >= 8 {
            return hex.dropFirst(4).prefix(4) == "FE2C"
        }
        return false
    }

    public static func modelId24(dataHex: String) -> Int? {
        let clean = dataHex.filter { $0.isLetter || $0.isNumber }
        guard clean.count >= 6,
              let b0 = UInt8(clean.prefix(2), radix: 16),
              let b1 = UInt8(clean.dropFirst(2).prefix(2), radix: 16),
              let b2 = UInt8(clean.dropFirst(4).prefix(2), radix: 16) else { return nil }
        return (Int(b0) << 16) | (Int(b1) << 8) | Int(b2)
    }

    public static func modelName(dataHex: String) -> String? {
        guard let id = modelId24(dataHex: dataHex) else { return nil }
        return FastPairModels.name(modelId: id)
    }

    private static func hexLen(_ raw: String) -> Int {
        raw.filter { $0.isLetter || $0.isNumber }.count
    }
}
