#pragma once
#include <stdint.h>

// Hardware-independent debounce/release classifier. No double-click or cooldown.
class ButtonGesture {
 public:
  enum Event { None, Short, Long };
  Event update(uint32_t now, bool down) {
    if (down != raw) { raw=down; edge=now; }
    if (uint32_t(now-edge)<30 || down==stable) return None;
    stable=down;
    if (down) { pressed=now; return None; }
    return uint32_t(now-pressed)>=1500 ? Long : Short;
  }
 private:
  bool raw=false, stable=false;
  uint32_t edge=0, pressed=0;
};
