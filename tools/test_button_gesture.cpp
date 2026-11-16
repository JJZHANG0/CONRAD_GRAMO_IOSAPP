#include "../firmware/nomi_integration/ButtonGesture.h"
#include <cassert>
#include <iostream>
int main() {
  using B=ButtonGesture;
  B b;
  assert(b.update(0,true)==B::None);
  assert(b.update(10,false)==B::None); // contact bounce is not a press
  assert(b.update(45,false)==B::None);
  assert(b.update(100,true)==B::None); assert(b.update(130,true)==B::None);
  assert(b.update(200,false)==B::None); assert(b.update(230,false)==B::Short);
  assert(b.update(260,true)==B::None); assert(b.update(290,true)==B::None);
  assert(b.update(350,false)==B::None); assert(b.update(380,false)==B::Short); // two quick independent bites
  assert(b.update(400,true)==B::None); assert(b.update(430,true)==B::None);
  assert(b.update(1930,true)==B::None); assert(b.update(2600,true)==B::None);
  assert(b.update(2700,false)==B::None); assert(b.update(2730,false)==B::Long);
  assert(b.update(4000,false)==B::None); // held/released long gesture fires once, no trailing short
  B wrap;
  wrap.update(0xfffffff0,true); wrap.update(0x10,true);
  wrap.update(0x20,false); assert(wrap.update(0x40,false)==B::Short); // millis rollover
  std::cout << "PASS: bounce, two short presses, long-only release, idle, uint32 rollover\n";
}
