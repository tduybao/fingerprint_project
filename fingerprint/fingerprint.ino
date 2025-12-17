#include <Arduino.h>
#include "BleProvisioning.h"
#include "FingerprintSensor.h"
#include <WiFi.h>
#include <WebServer.h> 

WebServer server(80);
bool fp_scanning_enabled = false; // Trạng thái quét vân tay, quản lý qua Wi-Fi

void handleFpImageRequest() {
  if (!WiFi.isConnected()) {
    server.send(503, "text/plain", "WiFi not connected.");
    return;
  }
  
  uint16_t size = fpGetImageSize();
  
  if (size == 0) {
    // 204 No Content: Không có dữ liệu để gửi
    server.send(204); 
    return;
  }

  // Gửi dữ liệu ảnh RAW bytes qua HTTP
  server.send_P(200, "application/octet-stream", (const char*)fpGetImageData(), size);
  Serial.printf("[WEB] Sent %d bytes of RAW fingerprint image.\n", size);
}

void handleFpControl() {
  if (server.hasArg("cmd")) {
    String cmd = server.arg("cmd");
    if (cmd == "start") {
      fp_scanning_enabled = true;
      server.send(200, "text/plain", "START scanning enabled.");
      Serial.println("[WEB] Received START command.");
    } else if (cmd == "stop") {
      fp_scanning_enabled = false;
      server.send(200, "text/plain", "STOP scanning enabled.");
      Serial.println("[WEB] Received STOP command.");
    } else {
      server.send(400, "text/plain", "Invalid command. Use 'start' or 'stop'.");
    }
  } else {
    server.send(400, "text/plain", "Missing 'cmd' parameter.");
  }
}

void setup() {
  Serial.begin(115200);
  delay(1000);
  
  bleProvInit();
  fpInit();
  
  // Định nghĩa endpoint Web Server
  server.on("/fpimage", HTTP_GET, handleFpImageRequest); 
  server.on("/fpcontrol", HTTP_GET, handleFpControl); // Endpoint mới nhận lệnh Start/Stop
  server.on("/", HTTP_GET, [](){
    server.send(200, "text/plain", "ESP32-C6 FP Server. Status: " + String(fp_scanning_enabled ? "SCANNING" : "STOPPED") + " IP: " + WiFi.localIP().toString());
  });
}

void loop() {
  bleProvLoop();
  
  // Xử lý Web Server chỉ khi Wi-Fi đã kết nối
  if (WiFi.isConnected()) {
    static bool server_started = false;
    if (!server_started) {
      server.begin();
      server_started = true;
      Serial.println("[WEB] HTTP Server started.");
    }
    server.handleClient();
  }
  
  // === LOGIC ĐIỀU KHIỂN FINGERPRINT SCANNING ===
  static unsigned long last_scan_time = 0;
  const long scan_interval = 500; // Quét 2 lần/giây

  if (fp_scanning_enabled) {
    if (millis() - last_scan_time >= scan_interval) {
      // fpLoop() sẽ cố gắng chụp ảnh và lưu vào buffer nếu có ngón tay
      if (fpLoop()) {
        Serial.printf("[MAIN] New FP image captured: %d bytes.\n", fpGetImageSize());
      }
      last_scan_time = millis();
    }
  } 
  // Nếu fp_scanning_enabled = false, fpLoop() không được gọi,
  // ảnh cuối cùng được giữ lại.
}
// Giữ nguyên FingerprintSensor.h và FingerprintSensor.cpp từ câu trả lời trước.