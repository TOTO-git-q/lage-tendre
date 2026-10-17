# Halo study / 声明式光环示例

This 72-note chart requires only the declarative `glow_ring@1.0.0` plugin.
Blue halos follow ordinary note geometry, including big notes, holds and yellow
notes. The extra radius is visual only. No script-trust dialog is needed.

本谱展示声明式光环：只包含 JSON、已有项目贴图和参数着色器，没有 GDScript。
`notes[].ring` 的单位是键宽，默认 0（隐藏），范围 0–4，步长 0.25。
半径和透明度公式只使用受限标量输入；判定轨道和分数规则完全不变。

`audio.wav` is an exact copy of the original `_demo/audio.wav` (70 seconds).
`plugins/glow_ring/canvas.png` is the original project `receptor.png`, used only
as the procedural shader's UV canvas. No third-party code or assets were added.
The chart's authored notes finish before the reused audio ends.

The separate `_plugin_demos/index.json` is the P6 menu supplement. The original
songs/index.json is unchanged. See the parent `_plugin_demos/README.md` for
complete isolated HOME/XDG commands. The headless test is
`res://tests/plugin_demo_test.gd -- --isolated-test-user`; the real Xvfb capture
driver uses `res://tests/capture_plugin_demo.gd -- --isolated-test-user
--song=glow_ring --out=<absolute PNG>`. All engine runs use Dummy audio.
