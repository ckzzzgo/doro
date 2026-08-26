# 源素材 / 草稿

这里放的是**运行时不会加载**的东西：做图过程中的中间稿、参考模型、被新版取代的旧素材。
留着是因为将来改美术还用得上，但它们不该出现在项目的运行时目录里，也不该被打进安装包。

运行时真正加载的贴图一律在 `assets/images/` 下。

## 关于「乃琳 · 键盘模式」参考素材（已删除）

打字模式的键盘结构，当初参考的是 [Awesome-BongoCat](https://github.com/ayangweb/Awesome-BongoCat)
里的乃琳 Live2D 模型（88 个文件）。那个仓库没有任何许可证，`keyboard-research.md`
当时就写了「如果公开发行，建议仅参考结构后重画」。

2026-08-26 键盘贴图改由 `tools/gen_keyboard.py` 纯几何生成之后，这批参考素材没有
留存的理由了，连同被它改色而来的 `nairin_keyboard_original_blue_desk.png` 一并删除。

注意：**git 历史里还有**。真要彻底清掉得改写历史（git filter-repo），那是另一件事。

## mouse-drafts/

早期的鼠标贴图草稿，项目里没有任何引用。实际使用的是
`assets/images/input_reaction/pink_mouse_rounded_perspective_v2.png`。

## input-reaction-drafts/

打字/鼠标模式贴图的历代草稿：分开的左右爪（后来合成了一张连体图）、抠色用的
`_chroma` 版本、被 v2/v3 取代的旧版，以及 `generated_source/` 里的合成中间件。

`assets/images/input_reaction/` 里原本混着 20 个文件，而代码只加载其中 5 个 —— 剩下 14 个
连同中间件一起被打进了每个用户下载的安装包。移到这里之后运行时目录只剩真正在用的。
