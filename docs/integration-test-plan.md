# 构建与验收入口

当前产品化升级的完整步骤见 [product-experience.md](product-experience.md)。本轮开发、运行和验收完全在 iOS Simulator 完成。

- 工程：`GRAMO_APP.xcodeproj`；scheme / 主target：`GRAMO_APP`；最低iOS18。保留原签名、bundle ID及历史数据。
- 模拟器演示：`./tools/run_simulator_demo.sh`。Debug独立模拟数据，不向真实设备发命令。
- 真实硬件：见 [hardware-integration.md](hardware-integration.md) 与 [nomi-protocol.md](nomi-protocol.md)。固件0.4.1、相机和按钮链路的现场证据保留；实体灯带仍不亮，不算验收通过。
- 固件备份、编译、仅app0烧录及回退命令：见 [firmware/README.md](../firmware/README.md)。本轮UI升级未再烧录。
- 模型来源、固定版本、预处理、授权、评估包位置：见 [model-evaluation.md](model-evaluation.md)。Debug外置 `ChineseFood.mlpackage`；Release暂不打包未经授权的评估资源。

## 真实硬件后续复验（不属于本轮模拟器验收）

1. 实体样机开机，设备页选择NOMI01；等待连接及真实相机画面分别可用。
2. 开始用餐，用勺载图或手动选菜确认当前菜品；吃完离口后短按，检查只产生一条记录。
3. 没有可靠称重/视觉标定时保留待完善；使用实际称量和有来源的营养密度补充同一条记录。
4. 当日可计入值K>0时，把测试目标设K+1，应为绿色；目标设K应为红色；修正累计到目标以下应恢复绿色。必须目视实体灯，命令回执不能替代。
5. 结束本餐不重复累计；断线重连、跨日、历史编辑/删除后重新同步。长按1.5秒的深睡唤醒仍需实体验证，不等于彻底断电。

目前阻塞实体灯验收的是GPIO4至灯带的实际供电、共地、DIN波形/方向及灯珠状态，需要电气测量。模拟器中的红绿状态仅验证目标算法，不证明实体灯已经修好。
