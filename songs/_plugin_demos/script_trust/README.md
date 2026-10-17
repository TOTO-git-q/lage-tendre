# A little permission / 脚本信任示例

The chart explicitly requires two independent plugins:

- `glow_ring@1.0.0`: declarative blue rings, always available without script trust
- `trust_spark@1.0.0`: trusted GDScript gold sparks and a SCRIPT ACTIVE label

First opening asks whether to trust the pack. Denial leaves blue rings visible
and clearly reports the missing script plugin. Allowing adds gold sparks and the
label. The unchanged content hash remembers either answer; changing any pack
file requires another decision. Allowed and denied combinations have separate
score keys even though this particular script changes only visuals.

首次打开询问信任。拒绝后蓝色声明式光环保留，界面说明脚本部分已禁用；允许后
出现金色星点与 SCRIPT ACTIVE。内容不变则记住选择，改动包内任何文件会重新询问。
成绩按真正启用的插件组合分别记录。两个选择下判定与满分都不变。

The script deliberately creates the temporary marker
`user://plugin_demos/trust_spark_loaded.txt` in `_static_init()` and removes it in
`teardown`. This demonstrates that denied code must never be loaded, even before
`install`. No personal information is stored. It owns one node through the
registry and clears its static reference on close. The palette is a relative
preload, exercised inside the fresh verified session snapshot.

Trusted GDScript is not sandboxed. This sample is short and reviewable, but trust
in an arbitrary third-party script allows arbitrary application/file/network
operations. The cooperative cleanup API cannot undo arbitrary script effects.

Audio and the shader canvas are exact existing-project copies, as documented in
the sibling glow_ring sample. No existing song, judgement constant or editor file
is changed. The original songs/index.json remains untouched.
