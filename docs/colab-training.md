# 免费 Colab 小规模微调

本实验验证训练与评估链路，不自动替换 GRAMO_APP 的 Core ML 模型。App 已有离线模型；微调同一网络不会减少其推理计算量。

## 运行

在 Google Colab 上传 `tools/training/GRAMO_Food_Finetune_Evaluation.ipynb`，选择 **T4 GPU**，全部运行。无需云盘挂载、HF Token、Kaggle 密钥或付费服务。免费 GPU 不保证随时可用；分配失败就停止，不切换付费实例。

笔记本包含固定的公开样本清单及完整训练代码。结束时下载 `gramo-pilot-results.zip`，然后断开运行时。独立脚本为 `tools/training/colab_pilot.py`；`prepare_commons_manifest.py` 仅用于另建一次新样本清单，不保证 Commons 日后内容不变。

- 基座：`Albertbeta123/resnet-50-chinese-food`，提交 `1ce5801e5905f15de1c4e55c89ef2a8cd6d6a97c`，保留 114 个原始标签索引。
- 只读取 safetensors；禁用远程自定义代码，核对已有工程中的基座文件 SHA256。
- 使用原始 ConvNextImageProcessor；EXIF 修正、RGB、原始缩放裁剪与归一化，归一化只发生一次。
- 微调分类层的 0 / 71 / 77 行（麻婆豆腐、宫保鸡丁、红烧肉）；特征提取器冻结，其余分类行每一步恢复基座值。其他类别的概率仍可能变化，不能视为全类别无回归。
- 最大每类 45 张，12 轮，固定随机种子；数据下载有 15 分钟预算。超时、独立样本不足等情况明确失败，不伪造结果。
- 作者分组和感知哈希聚类先于拆分；近似重复及同作者图片保持在同一集合。验证集选轮次，测试集不参与训练或选择。
- 输出包含真实指标、逐图预测、划分、授权、文件校验值、实际依赖版本及 safetensors 候选权重。

## 数据及解释边界

数据来自 Wikimedia Commons 三个明确类别：[Mapo doufu](https://commons.wikimedia.org/wiki/Category:Mapo_doufu)、[Kung Pao chicken](https://commons.wikimedia.org/wiki/Category:Kung_Pao_chicken)、[Red braised pork belly](https://commons.wikimedia.org/wiki/Category:Red_braised_pork_belly)。原始候选清单 118 张，仅保留有明确 CC0、公有领域、CC BY 或 CC BY-SA 标识的图片，逐图署名、许可链接及原始页面保存在 `commons-manifest.json`。公开类别属于弱标签，可能含多菜餐盘、包装或错标，尚未经逐张人工审定。哈希/作者分组也不等于已证明同盘完全隔离。

这不是训练 114 类的新完整数据集，也不是勺载相机准确率验收。基座是否已见过这些公开图片无法确认，因此不能宣称这些成绩是独立、无污染的泛化指标。没有非食物集，不能据此设拒识门槛。

基座权重卡标示 Apache-2.0，不代表原训练数据全部可商用；[ChineseFoodNet 原始条款](https://sites.google.com/view/chinesefoodnet/)限制非商业研究/教育使用。候选权重继续仅作本地研究评估，不自动加入发布包或上传公共仓库。照片和权重留在 ignored `artifacts/`，不上传用户相机照片、个人记录或健康数据。

## 接入门槛

只有补充经过人工确认、按餐盘分组的勺载相机测试集，并检查完整类别回归、空勺/非食物拒识及资源授权后，才能决定是否替换。换模型时还必须使用新的模型版本元数据，在同一输入上比较 PyTorch/Core ML Top 3 与分数误差，并在 iPhone 测量冷启动和热推理耗时。不能把微调权重冒充原基座版本。

训练没有调用聊天模型 API；GPU 运算不产生聊天 token。准备代码、排错和查看结果仍会产生对话用量。

## 2026-11-19 实际运行结果

在免费 Tesla T4 上实际完成 12 轮分类层微调。108 条样本（归档审计确认 107 张不同图片）：麻婆豆腐 45、宫保鸡丁 45、红烧肉 18；按分组拆为训练 60、验证 31、测试 17。验证集选择第 12 轮。

| 留出测试集（17 张） | 原模型 | 微调候选 |
|---|---:|---:|
| Top 1 | 8/17（47.1%） | 11/17（64.7%） |
| Top 3 | 10/17（58.8%） | 11/17（64.7%） |

验证集 Top 1 从 35.5% 到 45.2%。这些仅是三类弱标签小样本的探索性结果，不能据此宣称 App 准确率达到 64.7%。结果摘要见 `docs/evidence/colab-pilot-summary.json`。保持现有 App 模型和全部硬件代码不变。

云端实际环境：Python 3.13.16、PyTorch 2.14.1+cu130、Tesla T4、Transformers 4.51.3。固定的训练库与 Colab 预装但本实验不用的 Gradio/Diffusers 有依赖冲突提示；本次完整训练、评估、safetensors 保存及基座校验均实际完成。请使用独立临时运行时，不复用承载其他工作的会话。完整环境清单随结果包保存。

## 归档审计

结果包已下载并归档到 `artifacts/colab-pilot/results/`，完整原始报告副本在 `docs/evidence/colab-pilot-report.json`。实际训练流程用时 146.4 秒。已独立核对 ZIP 完整性、候选三文件 SHA256、输入清单哈希、逐图预测重算指标及集合间分组/文件哈希隔离；逐张量比较确认特征提取器未变化、其余 111 行分类权重保持原值。免费 GPU 会话已结束。候选 safetensors 尚未转换或接入 App。

**发现的数据问题：** 108 条样本实际对应 107 张不同图片。Commons 页面 138634132（多菜便当）同时属于两个菜品类别，在训练集中出现两次且标签不同；没有跨集合泄漏，但会干扰训练。保存原始报告，不事后修改实验成绩。更新后的脚本和笔记本会在抽样前排除跨类别页面并按页面 ID 去重；未为这个修复再次启动云训练。因此当前权重是有此问题的探索性候选，不是“清洗后训练完成”的模型。源清单保留原貌以便复核，实际执行的旧脚本保存在结果包 `executed-training.py`。
