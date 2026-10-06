# 应用图标

使用内置 `imagegen` 工具生成。图案为蓝绿色圆角底板、奶白与珊瑚橙色对话气泡，以及“文”和“A”，表达朋友之间的语言交流。

- 图像源文件：[Config/AppIcon.png](../Config/AppIcon.png)（1024 × 1024，保留透明通道）。
- macOS 图标：[Config/AppIcon.icns](../Config/AppIcon.icns)，包含 16、32、64、128、256、512、1024 像素表示。
- `Config/Info.plist` 的 `CFBundleIconFile` 指向 `AppIcon`；Xcode Resources 阶段将 ICNS 放入应用包。
- 尺寸转换使用 macOS `sips`，封装使用 `iconutil`，不改变生成图案。

## 生成提示词

```text
Create a finished professional macOS application icon for a friendly speech translation app named FriendTranslator (朋友之间语言翻译器). Square 1024x1024 image. A single beautifully crafted macOS rounded-square app tile occupying about 86% of canvas with transparent corners around it, straight-on orthographic view. Deep teal to gentle turquoise gradient tile, subtle luminous glass and soft tactile depth. Two large overlapping friendly speech bubbles at center, one warm ivory on upper left with a bold simple Chinese character 文, the other soft coral-orange on lower right with a bold simple Latin A. Bubbles face each other as equals, with a small clean exchange curve subtly joining them. Warm, approachable, distinctive, extremely legible at 32 pixels, restrained premium Apple desktop icon quality, excellent optical balance, rounded friendly forms, crisp edges, no thin detail. Only the two characters 文 and A within the bubbles, no app name, no extra text, no microphone, no flags, no WeChat logo, no surrounding scene, no mockup, no multiple variations. Transparent canvas outside the rounded-square tile; tile itself is opaque.
```
