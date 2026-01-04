#include <Arduino.h>
#include <WiFi.h>
#include <WebServer.h>

#include "BleProvisioning.h"
#include "FingerprintSensor.h"

// ================= WEB SERVER =================
WebServer server(80);

// ================= FP STATE =================
enum FPState {
  FP_IDLE,
  FP_SCANNING,
  FP_DONE
};

volatile FPState fpState = FP_IDLE;
volatile bool fpImageReady = false;

// ================= SETUP =================
void setup() {
  Serial.begin(115200);
  delay(300);

  Serial.println("\n=== ESP32-C6 AS608 FINGERPRINT SERVER ===");

  // BLE dùng để nhận WiFi SSID / PASS
  bleProvInit();

  // Fingerprint
  fpInit();

  // HTTP API
  server.on("/fpcontrol", handleFpControl);
  server.on("/fpstatus", handleFpStatus);
  server.on("/fpimage", handleFpImage);

  Serial.println("[SYS] Setup done");
}

// ================= LOOP =================
void loop() {
  // BLE provisioning loop
  bleProvLoop();

  // Start web server sau khi có WiFi
  static bool webStarted = false;
  if (WiFi.isConnected() && !webStarted) {
    server.begin();
    webStarted = true;
    Serial.println("[WEB] HTTP server started");
  }

  if (webStarted) {
    server.handleClient();
  }

  // ================= SINGLE SHOT SCAN =================
  if (fpState == FP_SCANNING) {
    Serial.println("[FP] Scan session started");

    bool ok = fpLoop();   // GenImg + UpImage (1 lần)

    if (ok) {
      fpImageReady = true;
      Serial.println("[FP] Fingerprint image ready");
    } else {
      Serial.println("[FP] Scan failed or no finger");
    }

    fpState = FP_DONE;   // kết thúc phiên
  }
}

// ================= HTTP HANDLERS =================

// ---- START SCAN ----
void handleFpControl() {
  if (!server.hasArg("cmd")) {
    server.send(400, "text/plain", "Missing cmd");
    return;
  }

  if (server.arg("cmd") == "start") {
    if (fpState == FP_IDLE) {
      fpState = FP_SCANNING;
      fpImageReady = false;

      Serial.println("[WEB] FP START command");
      server.send(200, "text/plain", "FP scan started");
    } else {
      server.send(409, "text/plain", "FP busy");
    }
  } else {
    server.send(400, "text/plain", "Invalid cmd");
  }
}

// ---- GET STATUS ----
void handleFpStatus() {
  String stateStr;
  if (fpState == FP_IDLE) {
    stateStr = "IDLE";
  } else if (fpState == FP_SCANNING) {
    stateStr = "SCANNING";
  } else {
    stateStr = fpImageReady ? "DONE" : "FAILED";
  }

  server.send(200, "application/json", "{\"state\":\"" + stateStr + "\"}");
}

// ---- GET IMAGE ----
void handleFpImage() {
  if (!fpImageReady) {
    server.send(404, "text/plain", "Image not ready");
    return;
  }

  uint8_t* img = fpGetImageData();
  uint16_t size = fpGetImageSize();

  server.sendHeader("Content-Type", "application/octet-stream");
  server.sendHeader("Content-Length", String(size));
  server.send(200);

  WiFiClient client = server.client();
  client.write(img, size);

  Serial.printf("[WEB] Image sent (%d bytes)\n", size);

  // Reset state cho lần quét tiếp theo
  fpImageReady = false;
  fpState = FP_IDLE;
}
