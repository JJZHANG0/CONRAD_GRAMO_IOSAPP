# NOMI 消费端体验与模拟器验收

更新：2026-11-16。此轮按用户最新要求只使用电脑端 iOS Simulator，不依赖或操作真实 iPhone、餐勺或蓝牙。原硬件联调结论仍见 [硬件记录](hardware-integration.md)，不可用本轮模拟通过替代实体灯验收。

## 信息架构与视觉

参考 [Tesla 官方 App 介绍](https://www.tesla.com/support/tesla-app) 中围绕产品与日常操作组织体验的方式，使用现有 NOMI 产品图片、暖灰背景、黑白卡片、克制的状态色、统一24/22pt间距、清晰的数字层级与原生导航；未使用 Tesla 商标或素材。

- 今天：餐勺主视觉、连接状态、今日口次、已计入估算、目标进度、开始/继续用餐与最近餐次。
- 记录：日期选择、餐次卡片、每一口时间/菜名/份量/状态、人工补录和修正。历史数据保留。
- 趋势：7/30天可计算摄入、记录天数/口次和近7日记录分布。没有记录的日期不参与日均分母；待完善项不填0。
- 我的：目标、健康档案、设备、配件、隐私和本机导出。没有账户、付费会员或后台管理的假入口。
- 用餐：先开启本餐，选择当前菜品；短按更新同一账本，用餐结束不重复累计。数值变化和“已记录 · 第 N 口”反馈；尊重减少动态效果。
- 设备：连接与独立相机画面。正常界面不展示GATT、UUID、RSSI、原始传感器、命令ACK、模型版本或调试参数。

## Debug 与普通用户边界

普通启动即消费者模式，包括Debug构建也不会直接显示开发菜单。Debug构建可以在「我的」底部长按 NOMI 字样3秒进入开发工具，或启动参数 `-developer-mode`。开启模拟设备使用 `-mock-device` 或开发工具开关。

`MockSpoonDevice`、`DeveloperToolsView`、旧硬件/模型联调界面均在 `#if DEBUG` 内，Release不编译模拟适配器和联调入口。开发模式与模拟模式分开，开启开发工具不会自动生成任何记录。

模拟模式顶部持续显示“模拟设备 · 独立演示数据”，控制台也明确显示模拟来源。开发工具内关闭模拟模式会恢复原用户数据；数据不合并。

## 事件与存储

真实路径：Core Bluetooth → NomiButtonEvent → AppStore.receiveButton → IntakeLedger.upsert → persist → 今日汇总与目标状态。

模拟路径：MockSpoonDevice.shortPress → 同样的 NomiButtonEvent → 同样的 receiveButton/账本/保存。没有直接增加页面数字。

- 短按释放产生唯一启动nonce+序号；重发沿用原ID。长按只切换模拟电源，不产生bite；关机短按无事件。未开启本餐不入账。
- 断线短按进入持久化队列；重启后仍保留。重新连接先同步会话，再向同一入口重放，接受后移出队列。模拟同步失败保留队列，恢复后可重试。
- 模拟测量是独立第二阶段证据更新，测试算术为10g×100kcal/100g=10kcal。来源明确为Debug夹具，不能当作米饭等菜品的营养参考。关闭模拟份量，仍保存一口待完善，克数和热量为nil。
- 重放不覆盖用户修正，删除后的墓碑不复活；等于目标红、低于目标绿。模拟灯只是软件状态，不控制真实灯。
- 真实数据仍在原 `UserDefaults.standard / zhiweishao.store.v1`；模拟在 `com.kanglaide.zhiweishao.simulation.v1` suite，图片在Documents/Simulation。现有版本1模型字段可兼容解码，保留原迁移备份。
- UI自动化另用 `.uitests` 模拟suite和 `com.kanglaide.zhiweishao.uitests.production` 普通测试suite，不清除真实数据或交付演示的数据。单元测试注入随机命名的UserDefaults沙箱。
- 模拟模式不会启动Core Bluetooth、连接真实外设或发送真实灯命令。切换模式取消已有连接与重试，清理内存画面和LED状态。

## 本机运行

打开原 `GRAMO_APP.xcodeproj`，scheme现为 `GRAMO_APP`。选择 iPhone 16 / iOS18.5 Simulator（已安装）；不需要开发证书和硬件。签名、bundle ID与Git历史未改动。

```sh
# 构建、安装并启动隔离模拟演示；保留已有模拟记录。
./tools/run_simulator_demo.sh

# 包括29项单元与5项产品交互UI测试；目标与日志路径可自行调整。
xcodebuild -project GRAMO_APP.xcodeproj -scheme GRAMO_APP \
  -destination 'platform=iOS Simulator,id=5890899D-CC64-42C8-BABF-C55BB06D3B87' test
```

Xcode Scheme → Run → Arguments 添加 `-mock-device` 启动模拟模式；去掉 `-mock-device` 则回普通模式。不要添加旧 `-reset-store`。仅明确需要重新开始演示时才加一次 `-reset-simulation`。

### 最短演示

脚本保留已有模拟记录，当前演示有2口/20kcal且当前菜品已选为麻婆豆腐。若要逐项复现下面从0开始的数字，可在模拟控制台点“清空隔离模拟记录”并确认，再开始；此操作只清空模拟环境。

1. 首页「开始用餐」→「模拟餐勺控制」。连接模拟设备，再「开始模拟用餐」。
2. 短按一次：1口/10kcal；重发上一事件：仍1口；再短按：2口/20kcal。
3. 长按关机，再短按：仍2口；再长按开机：仍2口。断开连接后短按，队列+1；重新连接，账本只增加1口。
4. 关闭「提供模拟份量」后再短按：增加一口待完善，热量保持原值。开启同步失败再连接：保留队列；关闭失败重试后补传。
5. 设置测试目标20kcal，累计小于20为模拟绿、等于20为模拟红。回到记录修正同一口克数，累计降到目标以下时恢复模拟绿。
6. 关闭控制台查看本餐，再到首页/记录/趋势/我的；结束本餐后记录仍在。退出并重新启动，口次不丢失；重发最后事件仍不会重复。
7. 在「我的」打开开发者工具，关闭模拟模式；恢复真实数据，模拟记录不会混入。

### 识别与真实功能保留

普通用餐页的选菜支持手动菜名、相册、iPhone拍照（模拟器无相机时提示选择相册）、真实餐勺抓帧与单区域候选确认。保留方向修正、ROI及后台Core ML推理；缺少模型时可手动选择，没有假模型或假识别。

既有 `artifacts/chinese-food/ChineseFood.mlpackage` 仅作为已核查来源的本地Debug评估资源，未加入Release。目标为主App `GRAMO_APP`，不是Tests；授权限制和固定哈希见[模型记录](model-evaluation.md)。相机画面仍与蓝牙连接独立判断；模拟模式不伪装勺载实拍。

## 验收证据

- 升级前基线：23单元+4UI全部通过，`/tmp/zws-integration/final-all-tests.log`。
- 业务扩展：29项单元已通过，包括新增6项Mock适配器的短按/重发/长按、离线重启补传、缺失证据、阈值修正、删除墓碑、隔离存储。
- 已在Device Hub中操作 iPhone16 / iOS18.5 Simulator，观察1口→重发仍1口→2口、长按关机不计口、关机短按不计口。
- 本轮最终UI与Release结果以文件末尾更新和xcresult为准。实体相机、按钮、LED不属于本轮验收；此前灯带不亮的问题仍未通过。

### 最终验证（产品版）

- 29项单元：通过，`artifacts/product-verification/unit-tests.log`，包括模拟/普通两套账本及目标往返恢复。
- 5项产品UI：通过，`artifacts/product-verification/acceptance.log`；普通界面隐藏开发信息、目标与手动选菜、缺失份量和阈值、按键重发/长按/补传/历史及重启，以及修正/删除/重放不复活。完整结果包：`artifacts/product-verification/Acceptance.xcresult`。
- Debug模拟器构建与脚本启动：通过，`artifacts/simulator-evidence/build.log`；正式模拟数据没有被测试重置。
- Release模拟器构建：通过，`artifacts/product-verification/release-build.log`；硬件/模型诊断页与Mock适配器不编译进Release。
- XCTest截图导出：`artifacts/product-ui-final/manifest.json`；便于预览的副本在`artifacts/product-preview/`。这些都是运行中的模拟器截图，不是设计稿。

最后补充了照片载入后的自动滚动，并重新通过Debug/Release构建及下述实际照片操作；这项页面滚动调整之后没有重复运行整套34项测试。

模拟器真实照片操作已通过：从相册选入`artifacts/evaluation/mapo-doufu.jpg`，本地Core ML返回“麻婆豆腐 / 平菇 / 蒸蛋羹”三个备选名称；点选麻婆豆腐后成为当前菜品，原有2口/20kcal保持不变。截图`artifacts/product-preview/product-photo-candidates.png`与`product-photo-confirmed.png`。这证明照片→推理→人工确认的流程，没有把一个样本当作模型准确率评估，也没有当作勺载实拍。

模拟模式可使用真实照片验证本地Core ML，但没有伪装的蓝牙、相机实拍或实体LED验收。原工程签名与历史继续保留；工作区修改未擅自提交。

## 本轮主要修改文件

- 视觉与页面：`Theme.swift`，`Views/TodayView.swift`、`RecordsView.swift`、`InsightsView.swift`、`ProfileView.swift`、`ProductComponents.swift`、`RootView.swift`。
- 消费者流程：`Views/ConsumerFlows.swift`、`DishPickerView.swift`、`FlowViews.swift`；共享补录/修正与照片圈选在`IntegrationView.swift`。修正入口可保存原事件或确认删除；不会生成替代的新口次。
- 数据与模式：`Model/Store.swift`、`MockSpoonDevice.swift`、`SpoonRadio.swift`；保留原协议解析与硬件能力，阻止模拟模式启动扫描或接收真实扫描结果。
- 识别：`Model/FoodRecognizer.swift`仅调整Debug诊断输出目录；保留真实模型、预处理、推理与候选顺序。圈选改为明确启用，避免抢占页面滚动；载入照片后定位识别按钮，识别完成自动滚到候选区域。
- 测试：`GRAMO_APPTests/MockDeviceTests.swift`、`ButtonIntegrationTests.swift`、`IntegrationTests.swift`、`GRAMO_APPUITests/ScreenshotTests.swift`；启动脚本`tools/run_simulator_demo.sh`。
- 交付与证据：本文件、`README.md`、`docs/integration-test-plan.md`及原硬件/模型记录的状态澄清。本轮没有修改固件实现、烧录或改动签名。

以上路径相对于`GRAMO_APP/`，测试、tools与docs除外。工作区还包含此前硬件联调的未提交文件，均继续保留。

## 中英文（2026-11-16）

- 首次启用双语版默认为English，与系统语言无关。在 **Profile → Language → 简体中文** 切换中文；中文路径为 **我的 → 语言 → English**。选择立即生效并在重启后保留。
- 新增`zhiweishao.language.preference.v2`只保存明确的用户选择。旧版本曾无条件写入中文默认值，不能据此判断用户选择；因此双语版首次默认英语。原记录和v1语言字段均保留，不迁移或清空账本。
- 语言偏好对普通/模拟模式共用；两套用餐数据仍隔离。自动化测试使用独立suite，不改用户语言。
- 复用`Model/L10n.swift`，新增`Model/ProductL10n.swift`集中维护消费者文案、动态数字提示和中英文副标题。所有消费者页面、共用组件与模拟控制按钮接入翻译；日期控件使用所选locale，日期分组和热量计算仍按本地时区。
- 识别结果在英文界面使用可用的英文标签，中文界面使用中文名；手工输入的菜名保留原文。存储字段、协议字符串、模型标签顺序不随界面语言改变。
- `tools/run_simulator_demo.sh`不再强制中文。调试时仍可显式传`-language en`或`-language zh`，它只覆盖该次启动。
- 新增语言单元测试与模拟器界面测试：默认英语（即使系统语言为中文）、切中文、重启持久化、切回英语、英文页面记录与重发去重。截图和运行日志位于`artifacts/bilingual-verification/`。

双语最终验证：31项单元+6项UI全套通过（`all-tests.log`）；随后单复数与模型/手工菜名显示补充通过31项单元及语言UI复验（`final-unit-and-language-tests.log`）。模拟标记避让页眉后，语言切换/重启/英文记录界面再次通过（`final-layout-tests.log`），Release再次构建成功（`release.log`）。上述日志在`artifacts/bilingual-verification/`。运行截图为该目录下`bilingual-*.png`。

最终模拟标记采用独立顶部留白，重建并启动后实看`artifacts/bilingual-verification/final-home-en.png`，已确认与日期和标题不重叠。模拟器留在英文首页，原演示记录继续保留。
