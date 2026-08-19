# 源素材 / 草稿

这里放的是**运行时不会加载**的东西：做图过程中的中间稿、参考模型、被新版取代的旧素材。
留着是因为将来改美术还用得上，但它们不该出现在项目的运行时目录里，也不该被打进安装包。

运行时真正加载的贴图一律在 `images/` 下。

## keyboard-mode-naier/

来自 [Awesome-BongoCat](https://github.com/ayangweb/Awesome-BongoCat) 的「乃琳 · 键盘模式」
Live2D 模型，当初用作打字模式的键盘结构参考（见 `../keyboard-research.md`）。

原先它以「乃琳 · 键盘模式」为名放在项目根目录，并且 `export_presets.cfg` 把其中
两个文件打进了安装包 —— 但代码里从来没有任何地方加载它，属于白打包。移到这里的同时
去掉了那两条导出项。

另一个动机是那个目录名带空格和 `·`，非 ASCII 路径穿过命令行构建链是自找麻烦。

## mouse-drafts/

早期的鼠标贴图草稿，项目里没有任何引用。实际使用的是
`images/input_reaction/pink_mouse_rounded_perspective_v2.png`。

## input-reaction-drafts/

打字/鼠标模式贴图的历代草稿：分开的左右爪（后来合成了一张连体图）、抠色用的
`_chroma` 版本、被 v2/v3 取代的旧版，以及 `generated_source/` 里的合成中间件。

`images/input_reaction/` 里原本混着 20 个文件，而代码只加载其中 5 个 —— 剩下 14 个
连同中间件一起被打进了每个用户下载的安装包。移到这里之后运行时目录只剩真正在用的。
