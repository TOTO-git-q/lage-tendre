# Plugin demonstrations / 插件示例

This is the separate menu supplement for opt-in plugin songs. The original
`songs/index.json` and original song folders are unchanged. The integrating game
reads this directory's `index.json` in addition to the original index.

| Folder | Purpose / 用途 |
|---|---|
| shapes | Star and heart tracks; actual filled cross-sections / 星形、心形截面 |
| motion | An outward chord; visual motion only / 向外展开的视觉和弦 |
| speed | Parallel speeds and a slow SV section / 并排快慢光与全局减速段 |
| glow_ring | Pure declarative blue shader rings / 无脚本的蓝色着色器光环 |
| script_trust | Independent rings plus optional trusted gold decoration / 拒绝保留蓝环、允许增加金色装饰 |

The first three folders are supplied by their optional built-in packages. The
last two are self-contained song-local plugin examples. Each uses identical
bytes from the existing `_demo/audio.wav`; no third-party resource is added.
Both local examples have 72 notes and 84 total judgements, including hold ticks.
Their authored notes finish before the reused 70-second audio ends.

For the script example, review the short `plugins/trust_spark/entry.gd` and its
relative palette preload before allowing it. Full GDScript is not sandboxed.
The demo creates one temporary marker in `user://plugin_demos/` when the Script
is loaded and deletes it on teardown. Denial must prevent even this static
initializer from executing. It also owns a node cooperatively through the registry.

脚本示例第一次询问信任；拒绝后仍显示声明式蓝环，并在游戏中提示禁用插件；允许后
多出金色星点与 SCRIPT ACTIVE。包内容不变时记住允许或拒绝；任何包内文件变化都会
重新询问。两种启用组合的成绩键不同，但示例只改变画面，判定统计不变。

## Isolated tests / 隔离测试

Run from repository root with a dedicated writable HOME/XDG. These tests write
their own trust and score fixtures, so never point them at a player's real user
directory. `G` must point to the already available official Godot binary.

```sh
T="$PWD/.plugin-demo-user"
mkdir -p "$T/home" "$T/data" "$T/config" "$T/cache"
export HOME="$T/home" XDG_DATA_HOME="$T/data"
export XDG_CONFIG_HOME="$T/config" XDG_CACHE_HOME="$T/cache"
G="$PWD/.tools/godot"
"$G" --headless --audio-driver Dummy --path spotlight-godot \
  -s res://tests/plugin_demo_test.gd -- --isolated-test-user
```

The screenshot driver requires real Xvfb/OpenGL rendering. Its explicit
`--trust` choice is a test-only action in the isolated user directory; it is not
a replacement for the application's player-facing trust dialog.

```sh
xvfb-run -a "$G" --audio-driver Dummy --rendering-driver opengl3 \
  --resolution 1600x900 --path spotlight-godot \
  -s res://tests/capture_plugin_demo.gd -- --isolated-test-user \
  --song=script_trust --trust=deny --time=9.25 --out="$PWD/denied.png"
```

Use `--trust=allow` for the gold decoration, or `--song=glow_ring` for the pure
declarative example. Capture metadata records actual callback counts, enabled
identity, disable notices and teardown state. The driver exercises the real
GameCore/Renderer; main-menu selection and dialog evidence are separate tests.

The script decoration uses `renderer.visual_progress(id,time)` when provided
by the optional speed-capable renderer, with the original fall formula as a
backward-compatible fallback. Core declarative progress composition is owned
by the speed integration; these two sample charts do not require that package.

For source projects, keep the two project directories adjacent. For an exported
template, place the complete `songs/` directory beside the executable, including
this index, all selected demo folders, plugin files and audio. Audio is external
to the game PCK. See the bilingual `PLUGINS_API` guide for full path/trust/default
saving contracts.
