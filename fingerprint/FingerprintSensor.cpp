#include "FingerprintSensor.h"

// ================= UART =================
HardwareSerial FPSerial(1);
#define FP_RX 6
#define FP_TX 7
#define FP_BAUD 57600

// ================= BUFFER =================
static uint8_t imageBuf[FP_IMG_SIZE];
static uint16_t imageSize = 0;

// ================= PROTOCOL =================
#define FP_HEADER_H 0xEF
#define FP_HEADER_L 0x01

#define FP_CMD_PACKET  0x01
#define FP_ACK_PACKET  0x07
#define FP_DATA_PACKET 0x02
#define FP_END_PACKET  0x08

#define CMD_GENIMG   0x01
#define CMD_UPIMAGE  0x0A

// ================= UTILS =================
static void flushFP() {
  while (FPSerial.available()) FPSerial.read();
}

// Gửi command packet
static void sendCommand(uint8_t cmd) {
  uint8_t packet[12];
  uint16_t checksum = 0;

  packet[0] = FP_HEADER_H;
  packet[1] = FP_HEADER_L;

  // address (default)
  packet[2] = packet[3] = packet[4] = packet[5] = 0xFF;

  packet[6] = FP_CMD_PACKET;
  packet[7] = 0x00;
  packet[8] = 0x03;     // length = 3
  packet[9] = cmd;

  checksum = packet[6] + packet[7] + packet[8] + packet[9];
  packet[10] = checksum >> 8;
  packet[11] = checksum & 0xFF;

  FPSerial.write(packet, 12);
}

// Đọc ACK packet (chuẩn)
static bool readAck(uint8_t &confirmCode, uint16_t timeout = 1000) {
  uint32_t start = millis();

  // chờ header
  while (FPSerial.available() < 9) {
    if (millis() - start > timeout) return false;
  }

  // tìm header EF 01
  if (FPSerial.read() != FP_HEADER_H) return false;
  if (FPSerial.read() != FP_HEADER_L) return false;

  // bỏ address
  for (int i = 0; i < 4; i++) FPSerial.read();

  uint8_t packetType = FPSerial.read();
  uint16_t length = (FPSerial.read() << 8) | FPSerial.read();

  if (packetType != FP_ACK_PACKET || length < 3) return false;

  confirmCode = FPSerial.read();   // confirmation code

  // bỏ checksum
  FPSerial.read();
  FPSerial.read();

  return true;
}

// ================= INIT =================
void fpInit() {
  FPSerial.begin(FP_BAUD, SERIAL_8N1, FP_RX, FP_TX);
  delay(300);
  Serial.println("[FP] AS608 initialized (protocol mode)");
}

// ================= MAIN LOOP =================
bool fpLoop() {
  uint8_t code;

  // ===== GENIMG =====
  flushFP();
  sendCommand(CMD_GENIMG);

  if (!readAck(code)) {
    Serial.println("[FP] GenImg timeout");
    return false;
  }

  if (code == 0x02) {
    // no finger
    return false;
  }

  if (code != 0x00) {
    Serial.printf("[FP] GenImg error: 0x%02X\n", code);
    return false;
  }

  Serial.println("[FP] Finger detected!");

  // ===== UPIMAGE =====
  flushFP();
  sendCommand(CMD_UPIMAGE);

  if (!readAck(code)) {
    Serial.println("[FP] UpImage ACK timeout");
    return false;
  }

  if (code != 0x00) {
    Serial.printf("[FP] UpImage error: 0x%02X\n", code);
    return false;
  }

  // ===== RECEIVE IMAGE DATA =====
  uint32_t received = 0;
  uint32_t last = millis();

  while (received < FP_IMG_SIZE) {
    if (FPSerial.available()) {
      imageBuf[received++] = FPSerial.read();
      last = millis();
    } else {
      if (millis() - last > 2000) {
        Serial.println("[FP] Image receive timeout");
        return false;
      }
    }
  }

  imageSize = FP_IMG_SIZE;
  Serial.printf("[FP] Image OK: %d bytes\n", imageSize);
  return true;
}

// ================= GETTERS =================
uint16_t fpGetImageSize() {
  return imageSize;
}

uint8_t* fpGetImageData() {
  return imageBuf;
}
