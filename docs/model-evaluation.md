# 中餐模型评估与接入

## 实际产物与限制

- 来源：https://huggingface.co/Albertbeta123/resnet-50-chinese-food
- 固定提交：`1ce5801e5905f15de1c4e55c89ef2a8cd6d6a97c`，114 类。只下载 `model.safetensors`，不使用 `training_args.bin`，`trust_remote_code=False`，下载后本地加载。
- 实际导出文件：`artifacts/chinese-food/ChineseFood.mlpackage`（约 90 MB）。真实权重；已在本机通过 coremltools 转换和 CPU 推理。最低 iOS 18，FP32，RGB 图像输入，输出 `[1,114]` 概率。
- 类别按 `config.json` 的 **数值索引**，绝不按标签字母排序。源类别 6、7 同名，仍为两个类别。中文映射在 `tools/model-source/labels-zh.json`；部分英文标签含歧义，翻译是展示层映射，需要菜谱专家复核。
- 全部源文件 SHA256、环境和输出包各文件哈希：`docs/evidence/model-manifest.json`；全依赖锁：`tools/requirements-coreml.lock.txt`。
- 未接入百度：无已配置后端，不上传照片，不需要账号。没有密钥或默认联网路径。

## 预处理

按固定 `ConvNextImageProcessor`：EXIF 方向（含镜像）修正、RGB、短边缩放到 `floor(224/0.875)=256`（另一边向下取整）、双三次插值、中心裁剪 224。App 支持先选单道菜 ROI，再执行同样流程。`FoodImagePreprocessor.swift` 使用带下采样抗混叠的 a=-0.5 双三次核；合成彩色图与 Pillow 11.2.1 的逐像素比较已纳入 XCTest。

App 与 Python 均向 Core ML 传 **0–255 原始 RGB**，仅在导出模型内部执行 `(RGB/255 - mean)/std`。不在 Vision 或 Swift 再归一化。mean=[0.485,0.456,0.406]；std=[0.229,0.224,0.225]。

模型加载、编译、推理位于串行 actor。模型元数据内包含原始索引标签与中文名，加载校验固定提交和 114 类长度。输出保留类别 ID、原始标签、中文名、分数、来源、版本、关键帧 ID 和 ROI。本餐候选有另一个本地 UUID，因此同一类不同区域不会被合并。

参考：[Apple PyTorch 转换](https://apple.github.io/coremltools/docs-guides/source/convert-pytorch-workflow.html)、[Apple Vision 分类](https://developer.apple.com/documentation/coreml/classifying-images-with-vision-and-core-ml)、[Pillow 双三次实现说明](https://github.com/python-pillow/Pillow/blob/11.2.1/src/libImaging/Resample.c)。当前直接使用 Core ML 图像输入，避免 Vision 自动裁剪与手工裁剪叠加。

## 已跑的真实照片（非自有相机验收）

| 样本 | 来源 / 授权 | PyTorch Top 3 | Core ML 最大分数差 | 结果 |
|---|---|---|---|---|
| 麻婆豆腐 | MC10，[Mapo doufu.jpg](https://commons.wikimedia.org/wiki/File:Mapo_doufu.jpg)，[CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/)；2010-11-28，Canon EOS 40D | 麻婆豆腐 0.653209、平菇 0.053041、蒸蛋羹 0.017695 | 0.000002265 | Top 1 / Top 3 命中，类别顺序一致 |
| 餐厅环境（非食物） | Suicasmo，[Chen Mapo tofu 20260512.jpg](https://commons.wikimedia.org/wiki/File:Chen_Mapo_tofu_20260512.jpg)，CC0；人工看图确认是餐厅室内，不能凭文件名标为菜品 | 羊肉串 0.118274、烤鱼 0.102994、鱼香茄子 0.049780 | 0.000000261 | 闭集分类器会强行给出菜名，必须拒绝自动入账 |

下载原图未修改；`*-prepared.png` 是缩放裁剪的评估派生图，麻婆豆腐派生图遵循 CC BY-SA 3.0，保留本节署名。照片和大模型仅保存在本机 ignored `artifacts/`，不加入 App 发布包。完整原始分数在 `docs/evidence/model-parity.json`。

**勺载相机已有2张非食物负样本，iPhone 自摄有效样本仍为0**，结果见 `docs/evidence/camera-report.json`；没有自有真实菜品正样本集，因此两类相机的菜品Top1/Top3准确率仍不能报告。另有1张勺载屏幕翻拍红烧肉作为独立链路演示，不混入真实餐盘准确率。公开照片一正一负只证明转换路径可运行。尚无实测自动接受阈值；App 对所有 Top 3 都要求点选或手动输入，未设置虚构的拒识门槛。

## 复现

```sh
uv venv .venv-coreml --python 3.11
uv pip install --python .venv-coreml/bin/python -r tools/requirements-coreml.lock.txt
.venv-coreml/bin/python tools/export_chinese_food_coreml.py --images artifacts/evaluation/mapo-doufu.jpg artifacts/evaluation/restaurant-nonfood.jpg
.venv-coreml/bin/python tools/evaluate_food_model.py artifacts/evaluation/samples.csv
```

下载来源在上表；锁定提交已包含在脚本。`--download-only` 仅下载并生成哈希清单。没有图片时可导出模型，但 parity 必定标为未验证。已下载模型可在断网条件下加载运行。

为自有相机新建 CSV，列为 `image,camera,plate_group,split,expected_id`。camera=`phone`/`spoon`；split=`train`/`validation`/`test`；同一盘连续帧须共享 plate_group，脚本遇到跨集合泄漏直接失败。负样本的 expected_id 留空。分别采集标签内家常菜、空勺、非食物、逆光、运动模糊、库外菜，记录相机视角、勺头、光照与人工真值。用 validation 集选择阈值和 Top 1–2 分差，再一次性用独立 test 集报告；不能用本次两张公开照片定生产阈值。

## 授权分离

模型卡声明 Apache-2.0；导出工具依赖的代码各按其许可使用；仓库原 App 代码沿用项目原有授权。**模型卡许可不自动覆盖训练数据**。ChineseFoodNet [原站](https://sites.google.com/view/chinesefoodnet/) 表明学术研究用途免费、商业许可需另行请求，图片属于原作者。本次只做本地离线技术评估，没有下载训练集、发布权重或训练模型；商用/分发前需要核准模型权重与训练数据使用范围。未核准前只使用 Debug 外置评估包。

## Xcode / 真机放置

`GRAMO_APP` target 已包含 `FoodRecognizer.swift`，不需要生成 Core ML Swift 类。

当前评估方式：把整个 `ChineseFood.mlpackage` 复制进 **Debug App 的 `Documents/Models/ChineseFood.mlpackage`**，首次识别在后台编译。例：

```sh
xcrun devicectl device copy to --device YOUR_DEVICE_ID \
  --source artifacts/chinese-food/ChineseFood.mlpackage \
  --destination Documents/Models/ChineseFood.mlpackage \
  --domain-type appDataContainer --domain-identifier com.kanglaide.zhiweishao
```

本次已将评估包复制到所连接 iPhone。Release 不加载 Documents 外部评估模型。获授权分发后再把该 mlpackage 加入 `GRAMO_APP` target 的模型资源（Xcode 编译为 `ChineseFood.mlmodelc`），不要加入 Tests target；或继续通过已授权资源包提供，保持 revision 和标签元数据匹配。

## 移动端观察（不替代同输入数值对齐）

模拟器通过 PhotosPicker 选择公开麻婆豆腐图，App 显示 Top 3：麻婆豆腐约 64.0%、平菇约 5.6%、蒸蛋羹约 1.9%，排序与桌面一致。桌面 Top 1 为约 65.32%；相册传输/解码后的移动端像素尚未逐像素导出对齐，因此不能把该差异全部归因于 Core ML 数值误差。表中的微小差异仅指桌面同一预处理输入的 PyTorch/Core ML 对比。

2026-11-15，iPhone曾在Device Hub屏幕共享期间黑屏，停止共享后用户确认实体系统相机已恢复。未把未保存照片算为有效样本。勺载BLE拍摄电脑红烧肉图后，手机选区Core ML曾显示红烧肉约73.9%、莲藕约2.0%、花生约1.9%；仅验证图像与推理链路，不证明真实食物份量或泛化准确率。

消费端升级保留后台模型接口与预处理，候选页仅展示可确认的菜名。算法版本、原始分数及导出诊断放在Debug联调入口。模拟演示脚本只会把本机已有评估包放入Debug模拟器Documents/Models，不把权重加入Release。
