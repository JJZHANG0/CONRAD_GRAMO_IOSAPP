# NOMI01 BLE 扩展 v1

此协议由本仓库新固件实现，UUID不是对未知设备的猜测。原同事固件只有串口/Wi-Fi，本次没有假称复用其 BLE 协议。保留 App 原 SpoonLink v1 分支；新协议用独立特征，互不混解。

服务：`6C2E0001-5B4A-4E3F-8D2C-1A0B9E8D7C6B`。广播名 NOMI01。

| 特征后缀（相同 UUID 基尾） | 属性 | 内容 |
|---|---|---|
| `0005` | write with response / read / notify | JSON 命令和应用回执 |
| `0006` | read | 版本、设备ID及能力 JSON；可能分多次 ATT read 由 Core Bluetooth 组装 |
| `0007` | notify | JPEG 分块 |
| `0008` | read / notify | 实体短按事件 JSON |

信息：`{"v":1,"protocol":"nomi1","fw":"0.4.1-integration","name":"NOMI01","device":"…","camera":true,"led":true,"load":false,"imu":false,"contact":false,"button":true}`。相机初始化失败则 camera=false；不影响灯。0.4.1 灯驱动初始化或首个灭灯帧发送失败则 led=false；该能力仅代表输出控制器可用，不代表灯珠发光。App 匹配信息版本、订阅控制特征并 hello 成功后才就绪。

命令为 UTF-8 JSON、不含换行、≤180字节：`{"v":1,"id":"36字符UUID","op":"hello"}`。hello/ping 返回相同id、type=hello、fw和name；LED命令 op=led、color=green/red/off，0.4.1 在 GPIO4 的 RMT 发送完成后返回 type=led、color、applied=true、driver=rmt、tx=true；驱动失败返回 type=error、error=led_driver_tx_failed。0.4.0 使用 NeoPixel show，不能获知底层失败。两种回执都不是光学反馈；本机灯带在两版下均由用户确认完全不亮，实体灯验收失败，尚需电气测量。App按ID与目标颜色配对，8秒超时；写入成功不会被标为应用成功。

相机命令 op=capture；必须已订阅0007。控制通知返回 type=frame、id、frame(UInt32)、size(≤200000)、crc(IEEE CRC32 UInt32)、w、h。每块0007通知：

| 字节 | 意义 |
|---|---|
| 0 | 版本1 |
| 1 | 类型0x20 |
| 2…5 | frameID，LE UInt32 |
| 6…9 | offset，LE UInt32 |
| 10…13 | 总长度，LE UInt32 |
| 14… | JPEG字节 |

固件MTU185，通知总长≤182；每tick一块、至少8ms间隔，不阻塞LED命令队列。固件20秒发送期限，App30秒组帧期限，允许乱序/相同重复，冲突字节/坏长度/CRC或JPEG首尾错误拒收；旧frameID忽略；超时可重新拍摄。没有连续视频或无损重传承诺。照片不会自动入账；只有下述有效实体短按事件或明确人工补录才产生口次。

App仅在状态变化、重连或显式重同步时发灯命令。断线清理订阅/相机缓冲并有限重连。上电后保持灯灭直到目标同步；断线时保留最后灯色，App显示未同步，锁屏实时性不承诺。

USB控制台115200接受同样JSON加换行，可用于台架测试；`C`保留原序号hex JPEG导出。打开USB可复位该板，因此不要在活动进餐或BLE验收时同时打开串口。没有访问原NVS密钥、连接Wi-Fi或上传图片。

## 0.4 按钮与用餐会话

订阅0008后发送 `{"v":1,"id":"UUID","op":"session","meal":"meal-live-…","unixMs":1794750000000}`；meal最长32字节，空字符串停用记口。unixMs为App当前UTC毫秒。返回同id、type=session、active布尔值。连接/前台返回同步会话，App只有回执后提示短按已启用。

GPIO1低电平、30ms防抖；松手时小于1500ms为短按，每次独立释放生成一个事件，不合并双击。长按仅触发一次深睡，不生成bite。只有有效非空会话产生事件：

```json
{"v":1,"type":"bite","event":"0a9fbb523f4e88ef-00000001","device":"50F7FAC13DE8","meal":"meal-live-…","at":1794750302287}
```

事件ID是每次启动随机64位十六进制nonce加32位递增序号；device为稳定设备ID。at是同步时基后的UTC毫秒。App验证设备、餐次、开始/结束时间与未来时间容差；按device+event去重，先保存记录再发 `op=ack_event,event=原事件ID`。已删除记录保留墓碑，重发不能复活。App未关联的旧会话事件会明确忽略并ACK，不凭它新建餐次。

固件独立NVS命名空间nomi-events存最多64个未ACK事件，每500ms重发最早事件；收到ACK删除。队列满报告event_queue_full，不覆盖。App未开启用餐时短按不计口；缺图、重量、菜名的有效事件仍保留一条待确认记录。

长按约1.5秒松手：相机/BLE关闭、灯带及蓝灯关闭，进入GPIO1 EXT0深睡。按住约1.5秒可唤醒，释放动作被消耗；不足时重新睡眠。此为休眠唤醒，不是切断电源。2026-11-19现场用户确认蓝灯先灭后亮，唤醒后重新握手/相机出图，账本无额外口次；纯C++手势回放也通过。

## 0.4.2 按键可靠性（2026-11-19）

GPIO、GATT 和 bite 格式保持兼容。5ms 周期独立 FreeRTOS 任务采样 GPIO1，30ms 防抖、释放时区分短/长按；32项手势队列隔离相机阻塞，释放时间用于事件时戳。主循环把有效短按写入原64项 NVS 队列，再发送/等待 ACK。队列不覆盖，超限有诊断。开始餐次之前释放的手势不归入新餐次，唤醒手势不入账。

新增只读诊断 `op=button_status`，返回同id、type=button_status、down（当前电平）、active（餐次是否启用）、short（本次启动短按数）、ignored（未启用时短按数）、overflow（采样队列溢出数）、pending（未ACK事件数）。不生成模拟事件，不改变会话。`tools/nomi_button_monitor.py`只访问已确认USB VID/PID及0.4.2，先打开监视器再连接App，避免USB打开复位中断用餐。

App将待确认命令与已确认餐次分开，3/6/9/12秒退避重试，常规保存不覆盖待确认ID；仅接受匹配ID及active值的回执。每30秒及重连/前台回归重新同步会话，防止设备复位后保持未启用。消费者页面独立展示按键准备状态。记口先入账再补图片，预览无记录变化时不重复序列化整个账本。
