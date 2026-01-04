#pragma once
#include <Arduino.h>
#include <Adafruit_Fingerprint.h>

#define FP_IMG_WIDTH   256
#define FP_IMG_HEIGHT  288
#define FP_IMG_SIZE    (FP_IMG_WIDTH * FP_IMG_HEIGHT)

// RX, TX pins for ESP32-C6
#define FP_RX 6
#define FP_TX 7

void fpInit();
bool fpLoop();                 // chụp ảnh nếu có ngón tay

uint16_t fpGetImageSize();
uint8_t* fpGetImageData();

// Lấy instance của Adafruit_Fingerprint
Adafruit_Fingerprint* getFingerprintSensor();
