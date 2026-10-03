//
//  ObdView.swift
//  Fieldwatch
//
//  Read-only OBD-II dongle reader for YOUR OWN car.
//  AT + Mode 01/09 only. No clear codes, no control commands.
//

import SwiftUI
import Network
#if SWIFT_PACKAGE
import FieldwatchCore
#endif

public struct ObdView: View {
    @State private var host: String = "192.168.0.10"
    @State private var port: String = "35000"
    @State private var output: String = ""
    @State private var busy: Bool = false

    public init() {}

    public var body: some View {
        List {
            Section {
                Text("Kendi aracındaki açık WiFi OBD dongle'a salt-okunur bağlanır (bilgi: ATI, VIN, devir). Silme/kontrol komutu YOKTUR. Başkasının aracında kullanma.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Bağlantı") {
                HStack {
                    Text("IP")
                    Spacer()
                    TextField("192.168.0.10", text: $host)
                        .multilineTextAlignment(.trailing)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                HStack {
                    Text("Port")
                    Spacer()
                    TextField("35000", text: $port)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section("Salt-okunur komutlar") {
                Button("ATI (adaptör bilgisi)") { send("ATI") }.disabled(busy)
                Button("0902 (şasi no / VIN)") { send("0902") }.disabled(busy)
                Button("0100 (desteklenen PID'ler)") { send("0100") }.disabled(busy)
                Button("010C (motor devri)") { send("010C") }.disabled(busy)
            }

            Section("Yanıt") {
                if busy {
                    Text("Bekleniyor…")
                        .foregroundColor(.secondary)
                } else if output.isEmpty {
                    Text("Henüz yok.")
                        .foregroundColor(.secondary)
                } else {
                    Text(output)
                        .font(.system(.caption, design: .monospaced))
                }
            }
        }
        .navigationTitle("OBD Okuma")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func send(_ command: String) {
        guard let nwPort = UInt16(port).flatMap({ NWEndpoint.Port(rawValue: $0) }) else { return }
        busy = true
        output = ""
        let conn = NWConnection(host: .name(host, nil), port: nwPort, using: .tcp)
        var collected = Data()
        conn.stateUpdateHandler = { state in
            if case .ready = state {
                let payload = (command + "\r").data(using: .utf8)!
                conn.send(content: payload, completion: .contentProcessed({ _ in
                    conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
                        if let data = data { collected.append(data) }
                        finish(collected, conn)
                    }
                    DispatchQueue.global().asyncAfter(deadline: .now() + 3.0) {
                        finish(collected, conn)
                    }
                }))
            } else if case .failed = state {
                finish(collected, conn)
            }
        }
        conn.start(queue: .global(qos: .utility))
    }

    private func finish(_ data: Data, _ conn: NWConnection) {
        conn.cancel()
        var text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) ?? ""
        text = text.replacingOccurrences(of: ">", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        DispatchQueue.main.async {
            guard busy else { return } // First answer wins.
            output = text.isEmpty ? "(yanıt yok)" : text
            busy = false
        }
    }
}
