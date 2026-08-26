# 键盘调研对话摘录

导出日期：2026-07-30

这里只保存与键盘素材选择直接相关的用户可见问答，没有包含系统提示、内部推理或工具日志。

## 用户需求

> 桌宠是一只 Doro，粉色 Q 版可爱风格；使用常规键盘布局。代码不在本机，目前只查找优秀项目和视觉参考，只要能够拿来使用即可。

## 调研答复

暂时没有一个现成资源同时做到“Doro 粉色 Q 版、完整 104 键、逐键联动、鼠标左右键和滚轮联动”。但已经找到几组很接近的，可以组合使用。

### 最值得看的例子

| 候选 | 键盘细节与联动 | 鼠标 | 适合程度 |
|---|---|---|---|
| [Awesome-BongoCat 模型库](https://github.com/ayangweb/Awesome-BongoCat)里的“乃琳·键盘模式” | 解包检查后有 60 个独立按键素材，覆盖字母、数字、标点、方向键和修饰键；键帽字符清楚 | 无独立鼠标 | 最适合当 Doro 新键盘的结构模板 |
| 同库的“小熊猫昊昊·键盘模式” | 同样有 60 个逐键素材，完整主键区，Q 版轮廓干净 | 无独立鼠标 | 最符合“动物桌宠使用实体键盘”的感觉 |
| [Lita Live2D 动态键盘](https://booth.pm/ja/items/7126695) | 几乎所有能绑定的键都已配置，支持自定义键盘贴图和颜色 | 右手可切换到鼠标位置，但只有左键点击动画 | 联动设计完整，适合研究模型结构 |
| [Lita Mouse & Keyboard](https://www.etsy.com/listing/1695770982/vtuberassetsmouse-keyboard) | 商品说明写着每个画出来的键都有按下动画；允许编辑和商用 | 包含鼠标，可改变颜色 | 想买回来直接拆改时比较省事 |
| [粉色实时键鼠 Live2D](https://booth.pm/ja/items/6827261) | 键帽边界和字符清楚，但主要是游戏常用键 | 有匹配的粉色鼠标 | 画风贴近 Doro，适合参考配色与线条 |
| [R’s CustomMouse](https://booth.pm/en/items/6838663) | — | 粉色、白色等多色；左键、右键和滚轮分别有独立表达文件 | 鼠标动作结构值得参考 |
| [Orival 完整键盘](https://booth.pm/ja/items/8285781) | 完整功能区、方向区和数字区，结构接近常规全尺寸键盘 | 无 | 适合参考完整键盘如何在 Live2D 中保持清晰 |

“乃琳”和“小熊猫”模型可以从仓库下载：

- [乃琳·键盘模式 ZIP](https://github.com/ayangweb/Awesome-BongoCat/raw/master/models/Chinese/%E4%B9%83%E7%90%B3%20%C2%B7%20%E9%94%AE%E7%9B%98%E6%A8%A1%E5%BC%8F.zip)
- [小熊猫昊昊·键盘模式 ZIP](https://github.com/ayangweb/Awesome-BongoCat/raw/master/models/Chinese/%E5%B0%8F%E7%86%8A%E7%8C%AB%E6%98%8A%E6%98%8A%20%C2%B7%20%E9%94%AE%E7%9B%98%E6%A8%A1%E5%BC%8F.zip)

它们缺少 F1–F12、导航区和数字小键盘，但主键区的逐键素材比较完整。

### 可下载的建模参考

- [Mechanical Keyboard – Aesthetic](https://sketchfab.com/3d-assets/models/mechanical-keyboard-aesthetic-44bb12d306864e2cb4256a61d4168942)：免费的 CC BY 模型。淡紫外壳、奶白键帽、薄荷绿和粉色强调键，适合 Doro；属于紧凑布局。
- [Full QWERTY Keyboard](https://sketchfab.com/3d-assets/models/keyboard-4dba18a6157a49fbb22d26b22a9e6cbb)：完整全尺寸布局，按键几何体相互分离，适合制作逐键下沉动画；CC BY。
- [Mouse and Keyboard](https://sketchfab.com/3d-assets/models/mouse-and-keyboard-d91b625d38a64ed39c1dfaef28e588d7)：统一风格的键鼠组合，CC BY，可下载后改成粉色；键盘为 60% 布局。
- [Kenney Input Prompts](https://kenney.nl/knowledge-base/game-assets-2d/using-input-prompts)：CC0 的 PNG/SVG 键帽与鼠标输入图标，适合补齐字符或特殊键。

### 推荐组合

1. 使用“乃琳·键盘模式”作为逐键文件、左右手位置和命名模板。
2. 使用 Sketchfab 的淡紫粉色机械键盘作为造型与配色参考。
3. 鼠标保留左键、右键和滚轮三个清晰分区。
4. 把人类手换成 Doro 的短前肢；键帽采用粉、白、紫三色，空格键可以加入原创 Doro 风格装饰。

Awesome-BongoCat 模型仓库没有为所有美术素材统一标明开放许可证。个人本地使用风险较低；如果公开发行或商业销售，建议仅参考结构后重画，或向原作者确认。BOOTH、Etsy 商品也通常不允许把原始素材打包进可下载软件。

> **2026-08-26 后记：上面这条已经执行了。**
>
> 在此之前发布的版本里，`assets/images/input_reaction/nairin_keyboard.png` 其实是把
> Awesome-BongoCat 的 `resources/background.png` 桌面改了个色（#90c5e6 → #f6dce3），
> 其余 92.57% 的像素原样 —— 属于「改色」而不是「重画」，没做到这条建议。
>
> 现在键盘贴图改由 `tools/gen_keyboard.py` 纯几何生成：键位读代码里的 `_add_key`，
> 透视由字母数字四排拟合，键帽、字母、手绘抖动全部自己算。参考素材
> （`docs/source-assets/keyboard-mode-naier/`）连同那张原图一并删除。
>
> 键盘的几何和视角跟原来一致 —— 那是键位映射的硬约束，而且键盘本来就长那样；
> 刻意没做像素级复刻，那样得到的还是人家那张图。

