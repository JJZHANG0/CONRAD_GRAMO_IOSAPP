# 中餐图片采集与审核

目的：为后续模型迭代建立可追溯的候选图片库。采集完成不等于标签正确，也不等于可直接训练或已获完整商用授权。

## 首批范围

按川、粤、鲁、苏、浙、闽、湘、徽八个菜系建立 **25 个菜品 ID**，见 `tools/training/cuisine-catalog.json`。菜系是采集关联，不是排他的起源判断（例如叫花鸡关联苏、浙）。包括酸菜鱼、宫保鸡丁、干炒牛河、煲仔饭、德州扒鸡、扬州炒饭、东坡肉、佛跳墙、剁椒鱼头、臭鳜鱼等；不声称覆盖所有中国菜。

来源使用 Wikimedia Commons 的具体菜品分类，经省级菜系目录实际查询确认。目录元数据保存在本地 `artifacts/cuisine-dataset/discovery/`。不将餐厅、菜单、厨师、整省食品目录直接当作菜品标签，也不以模型预测代替真值。

现有模型固定 114 类。首批目录中仅 5 个菜品明确关联既有标签 ID（麻婆豆腐 0、宫保鸡丁 71、回锅肉 84、酸菜鱼 106、剁椒鱼头 111），其余进入“需核对分类体系或新增类别”队列；不把东坡肉、把子肉等细分菜名未经核实统一塞进“红烧肉”。

## 采集

```sh
python3 tools/training/collect_cuisine_images.py \
  --per-dish 10 --max-images 250 --metadata-limit 60 --minutes 20
```

只依赖 Python 和 Pillow；网络下载使用系统 curl。结果保存在忽略 Git 的 `artifacts/cuisine-dataset/`。可重复运行，元数据缓存和已下载图片会复用；需要更新网站快照时请使用另一个 `--output` 目录。默认每菜最多 10 张、总量最多 250 张、20 分钟预算，单次响应限制 15 MB。

- API 分页处理与 imageinfo 查询拆开，避免前次接口仅返回部分文件详情的问题。
- 单请求限速、明确 User-Agent、maxlag、限时和有限重试；不登录、不绕过访问限制，不使用付费 API。
- 按公开许可白名单筛选 CC0、公有领域、CC BY、CC BY-SA；保存作者、署名要求、许可链接、来源页面、来源版本信息及 SHA256。
- 缩略图请求宽度为 640 像素，服务端可能返回标准尺寸（实际尺寸记录在清单），保留原始来源 URL；EXIF 修正用于检查与指纹，不覆写下载文件。
- 小于 256 像素的短边、无法解码的文件或不支持的媒体跳过；优先不同作者。
- 同一页面落入多个菜品类别会隔离；SHA256 相同的重复文件不会默默算作独立样本。作者和差分感知哈希提供保守分组建议。
- 已在上一轮实验出现的页面记录原 split，后续导出拒绝把原验证／测试图作为训练图。

许可与访问规则依据：[Commons 文件复用说明](https://commons.wikimedia.org/wiki/Commons:Reusing_content_outside_Wikimedia)、[MediaWiki API 使用规范](https://www.mediawiki.org/wiki/API:Etiquette)。每张文件的具体授权仍须按来源页核对，不能把全站图片一概视为无条件可商用。

## 审核与导出

打开本地 `artifacts/cuisine-dataset/review.html` 查看图片和来源，`manifest.json` 记录可追溯元数据。默认 `review_status=pending`、`training_eligible=false`。

逐张核对：是否是目标单道菜；是否有包装、菜单、明显水印、遮挡或严重模糊；是否为相同照片、同一餐盘连续帧；菜名与菜系关联是否准确。多菜图需要先圈定区域、保留父图及裁剪来源，重新生成审核条目；不要把整张多菜图当作某一道菜。缩略图无法看清时回到原始来源核对。

人工审核文件采用 JSON，例如：

```json
[
  {
    "page_id": 123,
    "decision": "accept",
    "dish_id": "mapo_tofu",
    "reviewer": "实际审核者",
    "plate_group": "已确认的餐盘或来源组",
    "split": "train"
  }
]
```

上例 ID 仅为结构示例，不代表已通过审核。审核人不应凭菜名自动批量批准。拒绝项使用 `decision: reject`；没审核的图片不填接受记录。

```sh
python3 tools/training/export_reviewed_dataset.py \
  --manifest artifacts/cuisine-dataset/manifest.json \
  --reviews artifacts/cuisine-dataset/reviews.json \
  --output artifacts/cuisine-dataset/reviewed
```

导出会检查实际图片 SHA256，并阻止作者/近似图片建议组、明确餐盘组、相同文件跨 split。输出分为 `reviewed-existing-labels.json` 和 `reviewed-needs-new-labels.json`；后者不能直接传入固定 114 类训练脚本。训练入口还需按最终类别清单接入，不会让这批图自动触发 Colab 或替换 App。

## 进一步训练的条件

1. 清理弱标签、多菜和明显非食物，给新增菜名建立经核对的分类 ID；保留旧模型类别顺序。
2. 每类要有足够的独立餐盘，而不是对少量照片反复增强来凑数量。先按来源／餐盘分组再切分，增强只用于训练集合。
3. 加入自有勺载相机的真实食物、空勺、库外菜、逆光和运动模糊；网上的盘面照片不能替代勺内视角验收。
4. 固定基线、验证集和测试集；比较完整旧类别回归以及新增类别表现，再做 Core ML 转换一致性和 iPhone 耗时验证。

原模型的数据授权限制仍然存在；新图有许可不代表旧基座的训练来源问题自动消失。首轮采集和审核工具不修改 App、签名、固件、个人数据或已有模型。

## 测试

```sh
python3 -m unittest discover -s tools/training -p 'test_cuisine_dataset.py' -v
```

9 项元数据回归测试覆盖分页、跨标签隔离、未审核阻断、新类别不伪造旧标签 ID、跨集合组隔离、历史留出集保护及冲突重复文件。测试使用合成元数据，与实际采集图片分开。

明显不合格图片的视觉筛查保存在本地 `visual-screening.json`，运行 `python3 tools/training/apply_visual_screening.py artifacts/cuisine-dataset` 可刷新清单和审核页。此步骤只排除图片，不自动批准其余图片。重新采集后需重新应用已有筛查记录。

## 2026-11-19 首批实际结果

本轮限时采集得到 **345 个候选页面、181 张下载图片（约 31.3 MiB）**。25 个菜品均有下载样本；181 个页面 ID 和文件 SHA256 均唯一，所有图片解码与校验通过。两个跨菜名页面在下载前隔离；另有 2 个来源文件下载失败。15 分钟预算到达时停止，萧县面皮下载到 7 张；本次没有继续无限重试或启动付费计算。不是“全中国菜图片已经采全”。

按菜系关联统计（叫花鸡同时关联苏、浙，因此以下不能直接相加作为唯一图片总数）：

| 菜系方向 | 下载图片 |
|---|---:|
| 川菜 | 36 |
| 粤菜 | 27 |
| 鲁菜 | 16 |
| 苏菜 | 24 |
| 浙菜 | 28 |
| 闽菜 | 22 |
| 湘菜 | 20 |
| 徽菜 | 14 |

已浏览整批缩略图作明显问题筛查，**40 张整图排除、141 张仍待确认菜名和分组、0 张批准进入训练**。排除项含招牌、菜单、湖景、包装、未完成制作的场景及需要先裁剪的多菜图。排除只针对直接拿整图分类；原图及原因都保留，适合裁剪的照片仍可后续利用。缩略图筛查不等于菜品真值已完整审核。

剩余候选覆盖 24 个菜品；萧县面皮当前整图全部属于摊位/制作过程，本批没有可直接使用的成品图。臭鳜鱼只有 1 张，也不足以建立可靠训练/验证/测试划分。数据和结果在 `artifacts/cuisine-dataset/`：`review.html`、`manifest.json`、`visual-screening.json`、`summary.json`；仓库保留不含图片的汇总 `docs/evidence/cuisine-collection-summary.json`。`images/` 可能保留重跑缓存，以清单引用数量为准。

本轮未启动下一轮云训练、未替换 Core ML 模型。待类别与菜名审核、成品样本补足及同盘分组确认后，再安排训练。现有 App、硬件与历史数据未修改。
