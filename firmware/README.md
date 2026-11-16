# NOMI01 第一版联调固件

基于用户提供的 `nomi_main.zip`（SHA256 `62f21e5abc248365aa3aa7aa58395bff0393b1c814a397bff7f4dd35ee8d39ca`）确认接线。只复用相机驱动和灯带配置；未复制密钥、云端上传、音频库和固定克数估算。原 ZIP 私有解压留在 ignored artifacts；代码的商业分发授权尚需权利方确认。

板卡：XIAO ESP32S3 Sense；本机查询 ESP32-S3 rev0.2，8MB Flash、8MB OPI PSRAM、OV3660。3 颗 WS2812：GPIO4，GRB/800kHz，亮度46。按钮GPIO1低电平、GPIO2蓝灯；其余外设不初始化。

## 离线构建

依赖 Arduino CLI 1.1.1，ESP32 core 3.1.3，ArduinoJson 7.4.2；0.4.1直接使用core自带RMT，无需Adafruit NeoPixel。安装对应版本后：

```sh
arduino-cli compile \
  --fqbn esp32:esp32:XIAO_ESP32S3:PSRAM=opi,USBMode=hwcdc,CDCOnBoot=default,FlashSize=8M,PartitionScheme=default_8MB \
  --build-path /tmp/nomi-build firmware/nomi_integration
```

本 Mac 的旧 ctags 为 Intel 架构，使用官方 arduino/ctags 源码在 `/tmp/zws-integration/ctags-source` 原生构建；通过 `--build-property runtime.tools.ctags.path=/tmp/zws-integration/ctags-native/bin` 覆盖路径，没有替换全局工具。此次实际 CLI 配置在 `/tmp/zws-integration/arduino.yaml`，库目录是 `/Applications/BeeCode.app/Contents/tools/Arduino/libraries`。构建输出和源文件 SHA256 在 ignored `artifacts/nomi-firmware/manifest-0.4.1.json`。

## 已执行烧录与回退

2026-11-15：原固件完整读取8MB，校验 SHA256；分区表 MD5、原应用镜像 checksum/SHA 校验通过。读取安全信息：Secure Boot 和 Flash Encryption 均关闭。OTA sequence=1，当前 app0 地址0x10000、容量0x330000。当前0.4.1应用1,592,688字节；只写 app0，esptool 写后 hash 验证通过；原引导、分区表、NVS、app1未改动。开机日志确认新版本、OV3660初始化与NOMI01广播。

```sh
# 仅适用于本次已确认的同一块板卡，执行前关闭串口监视器。
python -m esptool --chip esp32s3 --port /dev/cu.usbmodem2101 --baud 115200 \
  write-flash 0x10000 artifacts/nomi-firmware/nomi-0.4.1.bin

# 回退原 app0（该文件从完整备份原样提取）；不触及 NVS。
python -m esptool --chip esp32s3 --port /dev/cu.usbmodem2101 --baud 115200 \
  write-flash 0x10000 artifacts/hardware-backup/app0.bin
```

完整备份 `artifacts/hardware-backup/nomi-original-20261115.bin` 的 SHA256 为 `8a092564d4b53a5795a18d068bff93a0c1b1a243d2c424277cb3509ce1a8f157`。恢复前重新核对。完整备份可能含凭据，文件600、目录700，不提交 Git。未实测回退烧录，保留原样备份及命令。

## 协议

见 [Nomi BLE 扩展](../docs/nomi-protocol.md)。上电灯灭，收到有效目标命令后才显示颜色。已实现短按事件、NVS重放、长按深睡/唤醒；未实现称重、IMU、口腔接触或云端识别。没有短按不会自动记口。BLE为前台近距离评估通道，尚未实现绑定认证和固件升级服务，不作为生产安全方案。

## 灯带失败记录与台架工具

0.4.1应用SHA256：`0081f1efa6a4322e853848502a433de044f05c0adb2633e99f690e9ee8dbf523`。`VerifiedRing.h`以20MHz RMT发送3颗GRB灯数据：T0高0.4µs/低0.85µs，T1高0.8µs/低0.45µs，末尾低300µs，亮度46。检测初始化、写入和发送完成返回值。所有时序固定在源码确认的GPIO4，无引脚扫描。

`tools/nomi_led_bench.py`先检查已知USB VID/PID及固件信息，再发送已定义的单色命令；可保存JSON证据。0.4.1初始化及绿色发送均返回成功，但用户目视仍完全不亮。不能把tx=true解释为灯亮。原源码还将ledEnabled默认置false，并注释大电流可能拖垮3V3；这不是本版继续关闭灯的开关，本版已实际发送。

剩余实查需要万用表/示波器及接线访问：灯带VDD/GND实际电压、与主控共地、GPIO4到第一颗DIN的通断与方向、DIN波形/电平，以及首颗灯珠。没有这些测量不能区分供电、断线、接口电平或灯珠故障。不要为了试错改接未知引脚，也不要提高亮度掩盖供电问题。备份和恢复过程不依赖灯带。
