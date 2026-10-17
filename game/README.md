# L’âge tendre — Godot 4 版

（原名 SPOTLIGHT；名字暗暗致敬 Deemo。exe / 文件夹 / 存档目录用 ASCII 名 `LAgeTendre`。）

Godot 4.7.2，GL Compatibility 渲染。此目录是独立游戏工程；独立写谱器位于 `../charter/`。

- 运行（开发）：`$env:GODOT --path .`，歌曲直接读 `../songs/`。
- 打包：从仓库根目录运行 `python tools/build_release.py`，同时构建游戏和写谱器。游戏包为 `../release/LAgeTendre-win64.zip`，内含 EXE、KeyGuard 和歌曲。
- 存档：`%APPDATA%\LAgeTendre\`（settings.json / calib.json / best.json）。

## 结构
| 文件 | 内容（对应网页版模块） |
|---|---|
| scripts/kb.gd | 键盘模型 ANSI/ISO/JIS、Godot 物理键码 → 键名（[1] KEYBOARD） |
| scripts/chart_lib.gd | 谱面校验、光的时间线、踩脚 cue、DEMO 谱（[2] CHART） |
| scripts/stage_fx.gd | 演出引擎（[4b] STAGE v2） |
| scripts/game_core.gd | 判定、长条、踩脚、自动演奏、计分（[4] GAME） |
| scripts/audio_engine.gd | 音乐/击键音/主时钟（播放位置 + 距上次混音 − 输出延迟，线性模型）（[3] AUDIO） |
| scripts/renderer.gd | 透视 "( )" 轨道、判定线、音符、上飘短横、踩脚光球、HUD（[5] RENDERER） |
| scripts/main.gd | 状态机、输入、标题/选歌/设置/暂停/结算/延迟校准/判定线对齐（[6] UI） |

## 自检（静音、窗口在屏幕外、不接收真实键盘）
```
Godot_v4.7.2-stable_win64_console.exe --path . --windowed --resolution 1920x1080 --position -5000,-5000 -- --mute --song=demo --autoplay --shot=out.png --shot-at=12
Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tests/autoplay_test.gd     # 所有谱面模拟时间自动演奏必须全 PERFECT
```
参数：`--song=<dir|demo>` `--from=<秒>` `--autoplay` `--screen=songs|settings|title` `--debug`（打印非 PERFECT 判定与时钟跳变）。
