// Nomi integration firmware: verified original camera/WS2812 wiring.
// No inferred grams, automatic bites, cloud uploads, sensor claims or stored-key access.
#include <Arduino.h>
#include <ArduinoJson.h>
#include "VerifiedRing.h"
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLE2902.h>
#include <Preferences.h>
#include <esp_sleep.h>
#include <driver/rtc_io.h>
#include "ButtonGesture.h"
#include "cam.h"

static const char *SERVICE = "6C2E0001-5B4A-4E3F-8D2C-1A0B9E8D7C6B";
static const char *CONTROL = "6C2E0005-5B4A-4E3F-8D2C-1A0B9E8D7C6B";
static const char *INFO = "6C2E0006-5B4A-4E3F-8D2C-1A0B9E8D7C6B";
static const char *IMAGE = "6C2E0007-5B4A-4E3F-8D2C-1A0B9E8D7C6B";
static const char *EVENTS = "6C2E0008-5B4A-4E3F-8D2C-1A0B9E8D7C6B";
static const char *VERSION = "0.4.2-integration";
Cam camera;
VerifiedRing ring;
BLEServer *server;
BLECharacteristic *controlChar, *imageChar, *infoChar;
BLE2902 *controlSubscription, *imageSubscription;
BLECharacteristic *eventChar;
BLE2902 *eventSubscription;
// Sampling has its own task: camera capture/BLE congestion cannot hide a short press.
struct Gesture { ButtonGesture::Event action; uint32_t at; };
QueueHandle_t gestures;
volatile uint32_t gestureOverflow = 0;
uint32_t shortPresses = 0, ignoredPresses = 0;
void sampleButton(void*) {
  ButtonGesture button;
  TickType_t last = xTaskGetTickCount();
  for (;;) {
    auto action = button.update(millis(), digitalRead(1) == LOW);
    if (action != ButtonGesture::None) {
      Gesture gesture{action, millis()};
      if (xQueueSend(gestures, &gesture, 0) != pdTRUE) ++gestureOverflow;
    }
    vTaskDelayUntil(&last, pdMS_TO_TICKS(5));
  }
}
Preferences eventStorage;
struct Bite { char event[28]; char meal[64]; int64_t at; };
Bite pendingBites[64] = {};
uint32_t eventSequence=0, bootA=0, bootB=0, lastEventSend=0;
String activeMeal;
int64_t clockEpoch=0;
uint32_t clockMillis=0, mealStartedMillis=0;
QueueHandle_t commands;
volatile bool linked = false;
volatile bool advertiseAgain = false;
uint32_t frameCounter = 0;
String lastCommandID, lastReply;
String currentColor = "off";
String deviceID;
camera_fb_t *activeFrame = nullptr;
size_t frameOffset = 0;
uint32_t frameStarted = 0, lastChunk = 0;
String activeCaptureID;
struct Command { char text[181]; };

void saveBite(size_t index) {
  char key[8]; snprintf(key,sizeof(key),"b%02u",unsigned(index));
  if (pendingBites[index].event[0]) {
    if (eventStorage.putBytes(key,&pendingBites[index],sizeof(Bite))!=sizeof(Bite)) Serial.println("[button] persistence failed; event remains queued in RAM");
  } else eventStorage.remove(key);
}
void sleepNow() {
  // This is deep sleep with GPIO1 wake, not a physical power disconnect.
  ring.clear(); ring.show(); digitalWrite(2,LOW);
  if (activeFrame) { esp_camera_fb_return(activeFrame); activeFrame=nullptr; }
  if (camera.ok) esp_camera_deinit();
  if (server) BLEDevice::deinit(false);
  rtc_gpio_init(GPIO_NUM_1); rtc_gpio_set_direction(GPIO_NUM_1,RTC_GPIO_MODE_INPUT_ONLY);
  rtc_gpio_pullup_en(GPIO_NUM_1); rtc_gpio_pulldown_dis(GPIO_NUM_1);
  esp_sleep_enable_ext0_wakeup(GPIO_NUM_1,0);
  esp_deep_sleep_start();
}
void buttonTick() {
  Gesture gesture;
  if (xQueueReceive(gestures,&gesture,0)!=pdTRUE) return;
  auto action=gesture.action;
  if (action==ButtonGesture::Long) { sleepNow(); return; }
  if (action!=ButtonGesture::Short) return;
  ++shortPresses;
  if (activeMeal.isEmpty() || clockEpoch==0 || int32_t(gesture.at-mealStartedMillis)<0) {
    ++ignoredPresses; Serial.println("[button] short ignored: no armed meal at release"); return;
  }
  for (auto &bite:pendingBites) if (bite.event[0]==0) {
    snprintf(bite.event,sizeof(bite.event),"%08lx%08lx-%08lx",(unsigned long)bootA,(unsigned long)bootB,(unsigned long)++eventSequence);
    activeMeal.toCharArray(bite.meal,sizeof(bite.meal));
    bite.at=clockEpoch+int32_t(gesture.at-clockMillis);
    saveBite(&bite-pendingBites); lastEventSend=0;
    Serial.printf("[button] queued %s at %lld\n",bite.event,(long long)bite.at); return;
  }
  errorReply("","event_queue_full"); // explicit failure, never overwrite an unacknowledged bite
}
void eventTick() {
  if (!linked || !eventSubscription->getNotifications() || millis()-lastEventSend<500) return;
  for (auto &bite:pendingBites) if (bite.event[0]) {
    JsonDocument event; event["v"]=1; event["type"]="bite"; event["event"]=bite.event;
    event["device"]=deviceID; event["meal"]=bite.meal; event["at"]=bite.at;
    String text; serializeJson(event,text);
    if (text.length()<=server->getPeerMTU(server->getConnId())-3) { eventChar->setValue(text.c_str()); eventChar->notify(); }
    lastEventSend=millis(); return;
  }
}

void reply(JsonDocument &doc) {
  doc["v"] = 1;
  String text; serializeJson(doc, text);
  controlChar->setValue(text.c_str());
  // iOS negotiates MTU before subscribing; don't silently truncate an ACK.
  if (linked && controlSubscription->getNotifications() && text.length() <= server->getPeerMTU(server->getConnId()) - 3)
    controlChar->notify();
  Serial.println(text);
  if (doc["id"].is<const char*>()) { lastCommandID = doc["id"].as<String>(); lastReply = text; }
}
void errorReply(const String &id, const char *code) {
  JsonDocument doc; doc["id"] = id; doc["type"] = "error"; doc["error"] = code; reply(doc);
}
uint32_t checksum(const uint8_t *data, size_t len) {
  uint32_t crc = 0xffffffff;
  while (len--) {
    crc ^= *data++;
    for (int i=0; i<8; ++i) crc = (crc>>1) ^ (0xedb88320u & (0u-(crc&1u)));
  }
  return ~crc;
}
void little32(uint8_t *data, uint32_t value) { for (int i=0; i<4; ++i) data[i] = value >> (8*i); }
void takeFrame(const String &id) {
  if (activeFrame) { errorReply(id,"camera_busy"); return; }
  if (!camera.ok) { errorReply(id,"camera_unavailable"); return; }
  if (!imageSubscription->getNotifications()) { errorReply(id,"image_not_subscribed"); return; }
  camera_fb_t *fb = esp_camera_fb_get();
  if (!fb) { errorReply(id,"capture_failed"); return; }
  if (fb->len > 200000) { esp_camera_fb_return(fb); errorReply(id,"image_too_large"); return; }
  const uint32_t frame = ++frameCounter;
  JsonDocument begin;
  begin["id"] = id; begin["type"] = "frame"; begin["frame"] = frame;
  begin["size"] = fb->len; begin["crc"] = checksum(fb->buf,fb->len);
  begin["w"] = fb->width; begin["h"] = fb->height;
  reply(begin);
  // 14-byte header: version,type,frameID,offset,total; each integer little endian.
  // Phone assembles out-of-order/repeated offsets and validates the complete CRC32.
  const size_t packetSize = min(size_t(182), size_t(server->getPeerMTU(server->getConnId()) - 3));
  if (packetSize <= 14) { esp_camera_fb_return(fb); errorReply(id,"mtu_too_small"); return; }
  activeFrame=fb; frameOffset=0; frameStarted=millis(); lastChunk=0; activeCaptureID=id;
}
// Send one chunk per tick, so LED commands remain responsive during a photo.
void frameTick() {
  if (!activeFrame) return;
  if (!linked || millis()-frameStarted>=20000) {
    esp_camera_fb_return(activeFrame); activeFrame=nullptr;
    if (linked) errorReply(activeCaptureID,"image_timeout");
    return;
  }
  if (millis()-lastChunk<8) return;
  lastChunk=millis();
  const size_t packetSize=min(size_t(182),size_t(server->getPeerMTU(server->getConnId())-3));
  if (packetSize<=14) return;
  uint8_t packet[182]; packet[0]=1; packet[1]=0x20;
  little32(packet+2,frameCounter); little32(packet+6,frameOffset); little32(packet+10,activeFrame->len);
  const size_t count=min(packetSize-14,activeFrame->len-frameOffset);
  memcpy(packet+14,activeFrame->buf+frameOffset,count);
  imageChar->setValue(packet,count+14); imageChar->notify(); frameOffset+=count;
  if (frameOffset==activeFrame->len) { esp_camera_fb_return(activeFrame); activeFrame=nullptr; }
}
void handle(const String &text) {
  JsonDocument doc;
  if (deserializeJson(doc,text) || doc["v"] != 1 || !doc["id"].is<const char*>() || !doc["op"].is<const char*>()) return;
  String id = doc["id"].as<String>(), op = doc["op"].as<String>();
  if (id.length()!=36) return;
  if (id==lastCommandID && op!="capture") {
    controlChar->setValue(lastReply.c_str());
    if (linked && controlSubscription->getNotifications()) controlChar->notify();
    return;
  }
  JsonDocument result; result["id"] = id;
  if (op=="hello" || op=="ping") {
    result["type"] = "hello"; result["fw"] = VERSION; result["name"] = "NOMI01"; reply(result);
  } else if (op=="button_status") {
    result["type"]="button_status"; result["down"]=(digitalRead(1)==LOW);
    result["active"]=!activeMeal.isEmpty(); result["short"]=shortPresses;
    result["ignored"]=ignoredPresses; result["overflow"]=gestureOverflow;
    unsigned count=0; for (auto &bite:pendingBites) if (bite.event[0]) ++count;
    result["pending"]=count; reply(result);
  } else if (op=="led") {
    String color = doc["color"] | "";
    if (color!="green" && color!="red" && color!="off") { errorReply(id,"invalid_color"); return; }
    ring.fill(color=="green" ? ring.Color(0,255,0) : color=="red" ? ring.Color(255,0,0) : 0);
    const bool transmitted=ring.show();
    if (!transmitted) { errorReply(id,"led_driver_tx_failed"); return; }
    currentColor = color;
    result["type"] = "led"; result["color"] = color; result["applied"] = true;
    result["driver"]="rmt"; result["tx"]=true; reply(result);
  } else if (op=="session") {
    String meal=doc["meal"] | "";
    int64_t epoch=doc["unixMs"] | int64_t(0);
    if (meal.length()>32 || epoch<1700000000000LL || epoch>4102444800000LL) { errorReply(id,"invalid_session"); return; }
    if (activeMeal!=meal) mealStartedMillis=millis();
    activeMeal=meal; clockEpoch=epoch; clockMillis=millis();
    result["type"]="session"; result["active"]=!activeMeal.isEmpty(); reply(result);
  } else if (op=="ack_event") {
    String event=doc["event"] | "";
    for (auto &bite:pendingBites) if (event==bite.event) { bite.event[0]=0; saveBite(&bite-pendingBites); break; }
    lastEventSend=0;
  } else if (op=="capture") takeFrame(id);
  else errorReply(id,"unsupported_command");
}
class ControlCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *c) override {
    String text = c->getValue();
    if (text.length()==0 || text.length()>180) return;
    Command item = {}; text.toCharArray(item.text,sizeof(item.text));
    xQueueSend(commands,&item,0); // bounded; timeout is reported by the phone if saturated
  }
};
class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer*) override { linked = true; }
  void onDisconnect(BLEServer*) override { linked = false; advertiseAgain = true; }
};
void setup() {
  Serial.begin(115200); delay(400);
  Serial.println("NOMI01 integration 0.4.2; physical button enabled; no audio/load/IMU/contact");
  rtc_gpio_deinit(GPIO_NUM_1); pinMode(1,INPUT_PULLUP); pinMode(2,OUTPUT);
  bool ledReady=ring.begin(); ring.setBrightness(46); ring.clear(); ledReady=ring.show()&&ledReady;
  Serial.printf("[led] GPIO4 RMT initialized and off frame transmitted: %s\n",ledReady?"OK":"FAILED");
  if (esp_sleep_get_wakeup_cause()==ESP_SLEEP_WAKEUP_EXT0) {
    uint32_t start=millis();
    while (digitalRead(1)==LOW && millis()-start<1500) delay(5);
    if (digitalRead(1)!=LOW) sleepNow();
    // Consume the wake gesture completely. It can never become a bite.
    digitalWrite(2,HIGH);
    while (digitalRead(1)==LOW) delay(5);
    delay(35);
  } else { while (digitalRead(1)==LOW) delay(5); }
  digitalWrite(2,HIGH);
  bootA=esp_random(); bootB=esp_random();
  eventStorage.begin("nomi-events",false);
  for (size_t i=0;i<64;++i) {
    char key[8]; snprintf(key,sizeof(key),"b%02u",unsigned(i));
    if (eventStorage.getBytesLength(key)==sizeof(Bite)) eventStorage.getBytes(key,&pendingBites[i],sizeof(Bite));
    pendingBites[i].event[27]=0; pendingBites[i].meal[63]=0;
  }
  camera.begin();
  char identity[17]; snprintf(identity,sizeof(identity),"%012llX",(unsigned long long)ESP.getEfuseMac()); deviceID = identity;
  commands = xQueueCreate(8,sizeof(Command));
  BLEDevice::init("NOMI01"); BLEDevice::setMTU(185);
  server = BLEDevice::createServer(); server->setCallbacks(new ServerCallbacks());
  BLEService *service = server->createService(SERVICE);
  controlChar = service->createCharacteristic(CONTROL,BLECharacteristic::PROPERTY_WRITE|BLECharacteristic::PROPERTY_NOTIFY|BLECharacteristic::PROPERTY_READ);
  controlSubscription = new BLE2902(); controlChar->addDescriptor(controlSubscription); controlChar->setCallbacks(new ControlCallbacks());
  imageChar = service->createCharacteristic(IMAGE,BLECharacteristic::PROPERTY_NOTIFY);
  imageSubscription = new BLE2902(); imageChar->addDescriptor(imageSubscription);
  infoChar = service->createCharacteristic(INFO,BLECharacteristic::PROPERTY_READ);
  eventChar = service->createCharacteristic(EVENTS,BLECharacteristic::PROPERTY_NOTIFY|BLECharacteristic::PROPERTY_READ);
  eventSubscription=new BLE2902(); eventChar->addDescriptor(eventSubscription);
  JsonDocument info;
  info["v"]=1; info["protocol"]="nomi1"; info["fw"]=VERSION; info["name"]="NOMI01"; info["device"]=deviceID;
  info["camera"]=camera.ok; info["led"]=ledReady; info["load"]=false; info["imu"]=false; info["contact"]=false;
  info["button"]=true;
  String infoText; serializeJson(info,infoText); infoChar->setValue(infoText.c_str());
  service->start();
  BLEAdvertising *advertising = BLEDevice::getAdvertising(); advertising->addServiceUUID(SERVICE); advertising->setScanResponse(true); advertising->start();
  gestures=xQueueCreate(32,sizeof(Gesture));
  if (!gestures || xTaskCreate(sampleButton,"nomi-button",3072,nullptr,2,nullptr)!=pdPASS) {
    Serial.println("[button] sampler failed; restarting"); ESP.restart();
  }
  Serial.println(infoText); Serial.println("[ble] advertising NOMI01");
}
void loop() {
  if (advertiseAgain) {
    if (activeFrame) { esp_camera_fb_return(activeFrame); activeFrame=nullptr; }
    xQueueReset(commands);
    advertiseAgain=false; delay(100); controlSubscription->setNotifications(false); imageSubscription->setNotifications(false);
    eventSubscription->setNotifications(false);
    lastCommandID=""; lastReply=""; BLEDevice::startAdvertising();
  }
  buttonTick(); eventTick();
  Command item;
  if (xQueueReceive(commands,&item,pdMS_TO_TICKS(5))==pdTRUE) handle(String(item.text));
  frameTick();
  buttonTick(); eventTick();
  // Same documented JSON protocol is available locally for bench verification.
  static String line;
  while (Serial.available()) {
    char c=Serial.read();
    if (c=='\n') { if (line=="C") camera.dump(); else handle(line); line=""; }
    else if (c!='\r') { if (line.length()<180) line+=c; else line=""; }
  }
}
