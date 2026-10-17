# L’âge tendre

一个用电脑键盘演奏的节奏游戏，附带独立写谱器。灵感来自 VOEZ 和 Deemo。

音符沿轨道落下：在判定窗口内，按下轨道覆盖范围中的任意键即可击中；黄色音符可以用轨道内已经按住的任意键接住；长按按松手的累计时长分段判定，可以换键继续。空格负责舞台提示。

歌曲包可以携带插件，扩展谱面语法、纹理与规则。写谱器提供实时预览，并通过 MCP 向 agent 暴露谱面状态、选择、轨道、镜头、分析、编辑、撤销与模拟等工具。歌曲脚本需要用户信任；保存和版本提交有独立授权开关。

仓库初始只附带原创合成音频、生成的封面与纹理，以及插件示例，不包含商业歌曲。代码与初始随附原创资源使用 [MIT 许可证](LICENSE)；社区投稿按各目录的[许可说明](songs/fan-made/LICENSE.md)提供。程序使用系统字体。Godot 及其运行时组件保留各自的许可证，见 [Godot 版权说明](https://godotengine.org/license/)；导出包附带运行时第三方许可说明。

## 下载和运行

在本仓库 GitHub 页面的 Releases 下载 `LAgeTendre-win64.zip`（游戏）或 `LAgeTendreCharter-win64.zip`（写谱器），完整解压后启动同名 EXE。写谱器包也带游戏，可直接试玩。`songs/` 必须保留在 EXE 旁边。

首次公开发布前，Releases 可能还没有下载项，可以自行构建。普通歌曲索引初始为空，仍可进入内置教程和插件示例。

## 添加自己的歌曲

新建 `songs/<dir>/`，放入 `chart.json`、音频（WAV、OGG 或 MP3）和可选封面。音频文件名可通过谱面的 `audio` 字段指定。也可以在写谱器中“新建歌曲”或导入文件夹，再添加到游戏歌单。

在 `songs/index.json` 数组中登记，例如：

```json
[{"dir":"my_song","set":"my_song","title":"My Song","artist":"Your name","version":"NORMAL","level":3,"bpm":120,"length":60,"audio":"audio.wav","cover":"my_song/cover.png","preview":0,"notes":1}]
```

填写实际目录、音频、时长和音符数，封面可以省略。谱面格式见 [谱面语法](docs/CHART_SYNTAX.md)，插件接口见 [插件指南](game/PLUGINS_API.zh-CN.md)，编辑和 MCP 操作见 [写谱器说明](charter/README.md)。只添加有权使用和分享的歌曲资源。

## 社区谱面 / Fan-made charts

欢迎通过 Pull Request 投稿原创或已获授权的谱面。每个投稿独立放在 `songs/fan-made/<slug>/`，无需编辑共享索引；游戏和写谱器会显示「社区谱面 FAN-MADE」分组。投稿方法、模板、本地验证及音频/封面许可要求见 [社区谱面指南](songs/fan-made/README.md)。代码保持 MIT；社区谱面数据默认 CC BY-SA 4.0，音频和封面按各自标注的许可提供。

Submit your charts by pull request using one folder per submission, with licence evidence and original mapper permission for conversions. See the bilingual [fan-made chart guide](songs/fan-made/README.md). Chart data is contributed under CC BY-SA 4.0; media retains its stated licence.

## 从源码运行、测试和构建

需要 Python 3、Godot 4.7.2，构建 Windows 包还需要对应版本导出模板及 Windows .NET Framework C# 编译器。普通测试和构建只用 Python 标准库；图像比较和发布冒烟检查使用已安装的 Pillow。工具不会安装新依赖。

设置 `GODOT` 指向本机引擎。未设置时，Python 工具依次查找 `.tools/godot.exe`、`.tools/godot`、PATH 中的 `godot` 或 `godot4`。PowerShell 示例：

```powershell
$env:GODOT = (Get-Command godot).Source
python tools/sync_core.py
& $env:GODOT --path game
& $env:GODOT --path charter
python tools/run_tests.py
python tools/build_release.py
python tools/smoke_release.py
```

Linux 可使用 `bash tools/setup_godot.sh` 导入工程及 `bash tools/run_tests.sh` 测试；视觉检查在 xvfb 下运行。自动测试均静音且无头或离屏。构建输出是 `release/LAgeTendre-win64.zip` 和 `release/LAgeTendreCharter-win64.zip`，不会自动发布。

`game/` 是共享代码的来源。启动或导出写谱器前运行同步工具，不要编辑 `charter/` 中被忽略的共享副本。测试夹具不进入发布包。Windows 缺少符号链接权限时，两项插件路径断言会保留失败，详见 [工具说明](tools/README.md)。

## English

L’âge tendre is a keyboard rhythm game with a standalone chart editor, inspired by VOEZ and Deemo. Any key inside a track can hit a note; yellow notes accept keys already held in the track, and holds are graded by time spent released. Song packs can supply syntax, texture and rule plugins. The editor exposes chart state and tools to agents over MCP.

The initial bundle contains original synthesized audio and generated assets. Code and those initial assets are MIT licensed; fan-made submissions have per-folder licences. Download either Windows ZIP from this repository’s Releases, or use Godot 4.7.2 and Python 3 to run the commands above. Set `GODOT` to your installed engine. Add `songs/<dir>/chart.json` and audio, then register the song in `songs/index.json`, or create/import it in the editor.
