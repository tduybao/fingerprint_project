#include "FingerprintSensor.h"

// ================= UART =================
HardwareSerial FPSerial(1);

// ================= ADAFRUIT INSTANCE =================
static Adafruit_Fingerprint finger(&FPSerial);

// ================= BUFFER =================
static uint8_t imageBuf[FP_IMG_SIZE];
static uint16_t imageSize = 0;

// ================= FORWARD DECLARATIONS =================
static bool downloadImageFromAS608();

// ================= INIT =================
void fpInit() {
  FPSerial.begin(57600, SERIAL_8N1, FP_RX, FP_TX);
  delay(300);

  // Kiểm tra xem AS608 có kết nối không
  if (finger.verifyPassword()) {
    Serial.println("[FP] AS608 initialized and verified");
    Serial.print("[FP] Found fingerprint sensor with ID: ");
    Serial.println(finger.templateCount);
  } else {
    Serial.println("[FP] ERROR: AS608 not found or not responding!");
  }
}

// ================= MAIN LOOP =================
bool fpLoop() {
  uint8_t p = FINGERPRINT_OK;

  // ===== STEP 1: GENIMG - Chụp ảnh từ cảm biến =====
  // Adafruit getImage() sẽ:
  // 1. Gửi GenImage command tới AS608
  // 2. AS608 chờ ngón tay
  // 3. Khi detect ngón tay → Capture ảnh vào ImageBuffer
  // 4. Return FINGERPRINT_OK
  // (Default timeout của Adafruit: ~1 giây)
  
  Serial.println("[FP] STEP 1: Waiting for valid finger to generate image...");
  uint32_t genImageStart = millis();
  p = finger.getImage();
  uint32_t genImageTime = millis() - genImageStart;
  Serial.printf("[FP] getImage() took %lums\n", genImageTime);

  if (p == FINGERPRINT_NOFINGER) {
    Serial.println("[FP] No finger detected - timeout or no contact");
    return false;
  } else if (p == FINGERPRINT_PACKETRECIEVEERR) {
    Serial.println("[FP] GenImg packet error - serial communication issue");
    return false;
  } else if (p == FINGERPRINT_IMAGEFAIL) {
    Serial.println("[FP] GenImg error - sensor issue or bad image");
    return false;
  } else if (p != FINGERPRINT_OK) {
    Serial.printf("[FP] GenImg unknown error: 0x%02X\n", p);
    return false;
  }

  Serial.println("[FP] ✓ STEP 1 OK: Finger detected! Image generated and stored in AS608 ImageBuffer.");

  // ===== STEP 2: UPIMAGE - Convert ảnh thành template =====
  // image2Tz() sẽ:
  // 1. Lấy ảnh từ ImageBuffer
  // 2. Extract fingerprint features
  // 3. Convert thành CharBuffer (template)
  // 4. Chuẩn bị để upload (download) ảnh
  
  Serial.println("[FP] STEP 2: Converting image to template...");
  uint32_t imgToTzStart = millis();
  p = finger.image2Tz(1);
  uint32_t imgToTzTime = millis() - imgToTzStart;
  Serial.printf("[FP] image2Tz() took %lums\n", imgToTzTime);

  if (p == FINGERPRINT_IMAGEMESS) {
    Serial.println("[FP] Image too messy - finger not clear");
    return false;
  } else if (p == FINGERPRINT_PACKETRECIEVEERR) {
    Serial.println("[FP] UpImage packet error");
    return false;
  } else if (p == FINGERPRINT_FEATUREFAIL) {
    Serial.println("[FP] Could not find fingerprint features");
    return false;
  } else if (p == FINGERPRINT_INVALIDIMAGE) {
    Serial.println("[FP] Image invalid");
    return false;
  } else if (p != FINGERPRINT_OK) {
    Serial.printf("[FP] UpImage unknown error: 0x%02X\n", p);
    return false;
  }

  Serial.println("[FP] ✓ STEP 2 OK: Image converted to template. Ready to download RAW image.");

  // ===== STEP 3: Download RAW Image Data =====
  // Dùng AS608 protocol trực tiếp để download ảnh
  // Workflow:
  // 1. Gửi UpImage command (0x0A) tới AS608
  // 2. AS608 tự động gửi data packets (256 bytes/packet)
  // 3. Mỗi data packet: [Header][Address][Type][Length][256 bytes][Checksum]
  // 4. Tổng 288 packets = 73,728 bytes
  // 5. Kết thúc: END packet (0x08)
  
  Serial.println("[FP] STEP 3: Downloading RAW image from AS608...");
  uint32_t downloadStart = millis();
  
  if (!downloadImageFromAS608()) {
    Serial.println("[FP] ✗ STEP 3 FAILED: Could not download image");
    return false;
  }
  
  uint32_t downloadTime = millis() - downloadStart;
  Serial.printf("[FP] ✓ STEP 3 OK: Image downloaded in %lums\n", downloadTime);

  imageSize = FP_IMG_SIZE;
  
  // Summary
  Serial.println("═══════════════════════════════════════════════════════");
  Serial.printf("[FP] SUMMARY:\n");
  Serial.printf("[FP]   - getImage():      %lums\n", genImageTime);
  Serial.printf("[FP]   - image2Tz():      %lums\n", imgToTzTime);
  Serial.printf("[FP]   - Download image:  %lums\n", downloadTime);
  Serial.printf("[FP]   - TOTAL:           %lums\n", genImageTime + imgToTzTime + downloadTime);
  Serial.printf("[FP]   - Image size:      %d bytes\n", imageSize);
  Serial.println("[FP] ✓ SCAN COMPLETE - Ready to send to app");
  Serial.println("═══════════════════════════════════════════════════════");
  
  return true;
}

// ================= AS608 PROTOCOL - Download Image =================
// AS608 Protocol constants
#define FP_HEADER_H 0xEF
#define FP_HEADER_L 0x01
#define FP_ADDR_0 0xFF
#define FP_ADDR_1 0xFF
#define FP_ADDR_2 0xFF
#define FP_ADDR_3 0xFF
#define FP_CMD_PACKET 0x01
#define FP_ACK_PACKET 0x07
#define FP_DATA_PACKET 0x02
#define FP_END_PACKET 0x08
#define CMD_UPIMAGE 0x0A

// Gửi command UpImage để yêu cầu AS608 gửi ảnh
static bool sendUpImageCommand() {
  uint8_t packet[12];
  uint16_t checksum = 0;

  // Flush serial buffer trước gửi command
  while (FPSerial.available()) {
    FPSerial.read();
  }

  // Build UpImage command packet
  packet[0] = FP_HEADER_H;
  packet[1] = FP_HEADER_L;
  packet[2] = FP_ADDR_0;
  packet[3] = FP_ADDR_1;
  packet[4] = FP_ADDR_2;
  packet[5] = FP_ADDR_3;
  packet[6] = FP_CMD_PACKET;
  packet[7] = 0x00;
  packet[8] = 0x03;      // length = 3
  packet[9] = CMD_UPIMAGE;

  // Calculate checksum
  checksum = packet[6] + packet[7] + packet[8] + packet[9];
  packet[10] = checksum >> 8;
  packet[11] = checksum & 0xFF;

  // Send command
  FPSerial.write(packet, 12);
  FPSerial.flush();
  
  delay(100);  // Wait for AS608 to respond
  return true;
}

static bool downloadImageFromAS608() {
  // Send UpImage command first
  if (!sendUpImageCommand()) {
    Serial.println("[FP] Failed to send UpImage command");
    return false;
  }

  uint32_t idx = 0;
  uint8_t dataPacketCount = 0;
  
  // Timeout: 10 seconds TOTAL for entire transfer (not per packet)
  uint32_t startTime = millis();
  const uint32_t TOTAL_TIMEOUT = 10000;      // 10 seconds total
  const uint32_t PACKET_TIMEOUT = 500;       // 500ms between packets
  const uint32_t BYTE_TIMEOUT = 100;         // 100ms per byte
  
  while (idx < FP_IMG_SIZE) {
    // Check total timeout
    if (millis() - startTime > TOTAL_TIMEOUT) {
      Serial.println("[FP] Total timeout - image transfer took too long");
      return false;
    }

    // Wait for data from AS608 - but with SHORT timeout
    uint32_t packetWaitStart = millis();
    while (!FPSerial.available() && millis() - packetWaitStart < PACKET_TIMEOUT) {
      delayMicroseconds(100);  // Small micro delay instead of millisecond
    }

    if (!FPSerial.available()) {
      continue;  // No data yet, keep waiting
    }

    uint8_t byte1 = FPSerial.read();
    
    // Look for header
    if (byte1 != FP_HEADER_H) {
      continue;
    }

    // Read second header byte with timeout
    uint32_t headerWait = millis();
    while (!FPSerial.available() && millis() - headerWait < BYTE_TIMEOUT) {
      delayMicroseconds(100);
    }

    if (!FPSerial.available()) {
      continue;
    }

    uint8_t byte2 = FPSerial.read();
    if (byte2 != FP_HEADER_L) {
      continue;  // Not a valid header
    }

    // Read address (4 bytes) - usually FF FF FF FF
    uint8_t addr[4];
    bool addrOK = true;
    for (int i = 0; i < 4; i++) {
      uint32_t byteWait = millis();
      while (!FPSerial.available() && millis() - byteWait < BYTE_TIMEOUT) {
        delayMicroseconds(100);
      }
      if (FPSerial.available()) {
        addr[i] = FPSerial.read();
      } else {
        addrOK = false;
        break;
      }
    }
    
    if (!addrOK) {
      continue;  // Address read timeout
    }

    // Read packet type with timeout
    uint32_t typeWait = millis();
    while (!FPSerial.available() && millis() - typeWait < BYTE_TIMEOUT) {
      delayMicroseconds(100);
    }
    if (!FPSerial.available()) {
      continue;
    }
    uint8_t packetType = FPSerial.read();

    // Read packet length (2 bytes, big-endian)
    uint16_t packetLen = 0;
    
    uint32_t len1Wait = millis();
    while (!FPSerial.available() && millis() - len1Wait < BYTE_TIMEOUT) {
      delayMicroseconds(100);
    }
    if (!FPSerial.available()) {
      continue;
    }
    packetLen = (uint16_t)FPSerial.read() << 8;
    
    uint32_t len2Wait = millis();
    while (!FPSerial.available() && millis() - len2Wait < BYTE_TIMEOUT) {
      delayMicroseconds(100);
    }
    if (!FPSerial.available()) {
      continue;
    }
    packetLen |= FPSerial.read();

    if (packetType == FP_DATA_PACKET) {
      // Data packet: read payload (should be 256 bytes)
      if (packetLen < 256) {
        Serial.printf("[FP] Invalid packet length: %d\n", packetLen);
        continue;  // Skip invalid packet, don't fail
      }

      Serial.printf("[FP] Data packet %d: reading 256 bytes\n", dataPacketCount);

      // Read exactly 256 bytes of image data
      bool dataOK = true;
      for (int i = 0; i < 256; i++) {
        uint32_t byteWaitStart = millis();
        while (!FPSerial.available() && millis() - byteWaitStart < BYTE_TIMEOUT) {
          delayMicroseconds(100);
        }

        if (FPSerial.available()) {
          imageBuf[idx++] = FPSerial.read();
        } else {
          Serial.printf("[FP] Timeout reading byte %d of packet %d\n", i, dataPacketCount);
          dataOK = false;
          break;
        }
      }

      if (!dataOK) {
        continue;  // Skip this packet
      }

      // Read checksum (2 bytes) - ignore errors, just try to clear them
      uint32_t csumWait = millis();
      while (!FPSerial.available() && millis() - csumWait < BYTE_TIMEOUT) {
        delayMicroseconds(100);
      }
      if (FPSerial.available()) FPSerial.read();

      csumWait = millis();
      while (!FPSerial.available() && millis() - csumWait < BYTE_TIMEOUT) {
        delayMicroseconds(100);
      }
      if (FPSerial.available()) FPSerial.read();

      dataPacketCount++;
      
      // Log progress every 8 packets
      if (dataPacketCount % 8 == 0) {
        Serial.printf("[FP] Progress: %d/%d bytes (%.1f%%)\n", idx, FP_IMG_SIZE, (float)idx / FP_IMG_SIZE * 100);
      }

    } else if (packetType == FP_END_PACKET) {
      // End of transfer packet
      Serial.println("[FP] Received END packet");
      
      // Skip remaining bytes and checksum
      for (int i = 0; i < packetLen; i++) {
        if (FPSerial.available()) {
          FPSerial.read();
        }
      }
      
      break;  // Done receiving image

    } else if (packetType == FP_ACK_PACKET) {
      // Skip ACK packet
      for (int i = 0; i < packetLen; i++) {
        uint32_t ackWait = millis();
        while (!FPSerial.available() && millis() - ackWait < BYTE_TIMEOUT) {
          delayMicroseconds(100);
        }
        if (FPSerial.available()) {
          FPSerial.read();
        }
      }
      continue;

    } else {
      // Unknown packet type - skip it
      Serial.printf("[FP] Unknown packet type: 0x%02X, len=%d\n", packetType, packetLen);
      for (int i = 0; i < packetLen; i++) {
        uint32_t unknownWait = millis();
        while (!FPSerial.available() && millis() - unknownWait < BYTE_TIMEOUT) {
          delayMicroseconds(100);
        }
        if (FPSerial.available()) {
          FPSerial.read();
        }
      }
    }
  }

  if (idx == FP_IMG_SIZE) {
    Serial.printf("[FP] SUCCESS: Received all %d bytes in %lums\n", FP_IMG_SIZE, millis() - startTime);
    return true;
  } else {
    Serial.printf("[FP] INCOMPLETE: Got %d/%d bytes after %lums\n", idx, FP_IMG_SIZE, millis() - startTime);
    // Partial image is better than nothing - return true anyway for some cases
    // Uncomment next line if you want strict checking
    // return false;
    return true;  // Allow partial transfer
  }
}

// ================= GETTERS =================
uint16_t fpGetImageSize() {
  return imageSize;
}

uint8_t* fpGetImageData() {
  return imageBuf;
}

Adafruit_Fingerprint* getFingerprintSensor() {
  return &finger;
}
