#pragma once
#include <Arduino.h>
#include <esp32-hal-rmt.h>

// Original hardware: GPIO4, three GRB WS2812. Explicit driver results replace
// the void NeoPixel::show() API, which cannot tell the caller about a TX failure.
class VerifiedRing {
 public:
  bool begin() {
    ready=rmtInit(4,RMT_TX_MODE,RMT_MEM_NUM_BLOCKS_2,20000000) && rmtSetEOT(4,0);
    return ready;
  }
  void setBrightness(uint8_t value) { brightness=value; }
  static uint32_t Color(uint8_t r,uint8_t g,uint8_t b) { return (uint32_t(r)<<16)|(uint32_t(g)<<8)|b; }
  void fill(uint32_t value) { color=value; }
  void clear() { color=0; }
  bool show() {
    if (!ready) return false;
    rmt_data_t symbols[73] = {};
    const uint8_t grb[3]={uint8_t(color>>8),uint8_t(color>>16),uint8_t(color)};
    size_t i=0;
    for (int led=0;led<3;++led) for (auto channel:grb) {
      uint8_t value=uint16_t(channel)*(uint16_t(brightness)+1)/256;
      for (int bit=7;bit>=0;--bit) {
        bool one=value&(1<<bit);
        symbols[i].level0=1; symbols[i].duration0=one?16:8;
        symbols[i].level1=0; symbols[i].duration1=one?9:17; ++i; // 1.25us bit period
      }
    }
    symbols[72].level0=0; symbols[72].duration0=6000; // 300us reset/latch
    symbols[72].level1=0; symbols[72].duration1=1;
    return rmtWrite(4,symbols,73,100) && rmtTransmitCompleted(4);
  }
 private:
  bool ready=false;
  uint8_t brightness=46;
  uint32_t color=0;
};
