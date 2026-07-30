# 鼠标 Live2D 拆层建议

## 推荐基础图层

```text
Mouse
├─ Body_Back
├─ Body_Lower
├─ Button_Left
├─ Button_Right
├─ Wheel
├─ DPI_Button
├─ Side_Button_Forward
├─ Side_Button_Back
├─ RGB_Strip
├─ Detail_Light
└─ Shadow_Internal
```

## 动作建议

- 左键：`Button_Left` 下移 2～4 px，并轻微压缩 Y 轴。
- 右键：`Button_Right` 使用相同逻辑。
- 中键：滚轮整体下移 1～2 px。
- 滚轮滚动：准备 3～4 个纹理位置，或让滚轮纹理循环移动。
- 侧键：按钮向壳体内侧移动 1～2 px，同时降低高光。
- 鼠标移动：整个鼠标跟随输入位置，外壳增加少量滞后与回弹。
- 灯带：点击时提高亮度，空闲时做低幅度呼吸效果。

## 建议参数

```text
ParamMouseX
ParamMouseY
ParamClickLeft
ParamClickRight
ParamClickMiddle
ParamWheel
ParamSideForward
ParamSideBack
ParamRGB
```

如果现有程序已经完成输入映射，可以沿用原参数名称，只把这些建议对应到已有参数。

## 制作注意

当前 PNG 是扁平合成图。拆层时需要补画被按钮或滚轮遮挡的壳体区域，否则按键移动后会出现空洞。建议在高分辨率下完成补画与分层，再统一缩放到桌宠实际尺寸。

