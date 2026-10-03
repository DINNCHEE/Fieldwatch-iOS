// Fieldwatch ESP32 Companion Bridge (TEMPLATE - untested, adapt to your board)
// What it does: joins/creates a Wi-Fi network and pushes scan results as
// JSON UDP datagrams to the phone running Fieldwatch (Companion mode).
//
// Phone side: Fieldwatch > Settings > Wi-Fi Scanner Mode > Companion (ESP32),
// same UDP port (default 8888). Phone should join the ESP32 AP.
//
// Packet schema (one JSON object per datagram, <1400 bytes):
//   {"v":1,"type":"wifi","ssid":"Name","bssid":"AA:BB:CC:DD:EE:FF","rssi":-57,"channel":3,"seq":1234,"t":1710000000}
//   {"v":1,"type":"ble","name":"Flipper-AB12","mac":"AA:BB:CC:DD:EE:FF","rssi":-70,"seq":1235,"t":1710000000}
//   {"v":1,"type":"station","sta":"11:22:33:44:55:66","ap":"50:ff:20:84:d6:0f","rssi":-65,"channel":3,"seq":1236,"t":1710000000}
//   {"v":1,"type":"status","mode":"wifi","uptime_s":42,"seq":1237,"t":1710000000}
// Rules: increment seq per packet, epoch t, send deltas only
// (new/changed, RSSI hysteresis >= 3 dB), newline-terminate.
//
// Requires: ESP32 Arduino core, WiFi + WiFiUdp libraries.
// Fill in the scan hooks for your sniffer (Marauder serial parse or
// native esp_wifi scan) where marked TODO.

#include <WiFi.h>
#include <WiFiUdp.h>

const char* AP_SSID = "RF-Observer";
const char* AP_PASS = "fieldwatch";
const char* PHONE_IP = "192.168.4.2"; // phone's IP on the ESP32 AP
const uint16_t PHONE_PORT = 8888;

WiFiUDP udp;
uint32_t seq = 0;

void sendJson(const String& json) {
  udp.beginPacket(PHONE_IP, PHONE_PORT);
  udp.print(json);
  udp.print("\n");
  udp.endPacket();
}

String esc(const String& s) {
  String o;
  for (size_t i = 0; i < s.length(); i++) {
    char c = s[i];
    if (c == '"' || c == '\\') o += '\\';
    if (c >= 32) o += c;
  }
  return o;
}

void pushWifi(const String& ssid, const String& bssid, int rssi, int channel) {
  char t[32];
  snprintf(t, sizeof(t), "%lu", (unsigned long)(millis() / 1000));
  String j = "{\"v\":1,\"type\":\"wifi\",\"ssid\":\"" + esc(ssid) +
             "\",\"bssid\":\"" + bssid + "\",\"rssi\":" + String(rssi) +
             ",\"channel\":" + String(channel) + ",\"seq\":" + String(seq++) +
             ",\"t\":" + String(t) + "}";
  sendJson(j);
}

void setup() {
  Serial.begin(115200);
  WiFi.mode(WIFI_AP);
  WiFi.softAP(AP_SSID, AP_PASS);
  Serial.print("AP IP: ");
  Serial.println(WiFi.softAPIP());
  // TODO: start your sniffer here (esp_wifi_set_promiscuous, BLE scan, ...).
}

void loop() {
  // TODO: on new/changed AP or BLE sighting, call pushWifi(...) or
  // build the ble/station/status variants above, then sendJson(...).
  // Suggested cadence: deltas only, expire entries after 30 s.
  delay(1000);
}
