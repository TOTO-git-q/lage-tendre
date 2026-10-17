# 社区谱面 / Fan-made charts

欢迎通过 Pull Request 投稿自己制作、且有权分享的谱面。每个投稿独占一个目录，**不修改 `songs/index.json`**，避免投稿之间的索引合并冲突。游戏和写谱器自动发现这些目录，在「社区谱面 FAN-MADE」分组中按歌名排序。以 `_` 或 `.` 开头的目录（包括 `_template`）不会显示，模板不进入发布包。

## 投稿步骤

1. Fork 仓库并创建分支。把 `_template` 复制到 `songs/fan-made/<slug>/`，或在写谱器的「⋯ → 新建社区谱面…」中选择 OGG/MP3 音频。
2. `<slug>` 最长 48 个字符，只用小写 `a-z0-9-_`，首字符用字母或数字；目录名要唯一。不要把一个投稿拆散到多个共享目录。
3. 填写 `info.json` 与 `CREDITS.md` 的实际作者、许可证和证据链接；加入音频，按[语法 v3](../../docs/CHART_SYNTAX.md)写谱。模板的空授权字段必须填写，不能把占位文字当成实际授权。
4. 用游戏亲自试玩，再运行下方验证。提交 PR 时选择[社区谱面模板](../../.github/PULL_REQUEST_TEMPLATE/fan-chart.md)，附上 Markdown 检查结果。只提交该歌曲目录及必要说明。
5. 维护者审核权利证据、署名、原谱师移植许可、难度和可玩性。检查通过不等于自动收录；脚本插件额外人工审核。

## 文件和元数据

```text
<slug>/
  info.json
  chart.json          # v3，至少有 notes 和 lights 数组
  audio.ogg|audio.mp3  # 二选一，≤ 12 MiB
  cover.jpg|cover.png  # 可选，二选一，≤ 1 MiB
  CREDITS.md
  plugins/<id>/…      # 可选，遵循歌曲插件接口
```

`info.json` 必填：`title`、`artist`、`version`（难度名）、`level`（0–100 整数）、`bpm`（20–400）、`preview`（试听起点秒，-1 禁用）、`audio`、`chart_author`、`chart_license` 和 `audio_license`。`chart.json` 的 BPM 与音频文件名必须一致，音频不能引用目录外文件。可选 `cover` 使用本目录文件名，并同时填写 `cover_license`。

`audio_license` 和 `cover_license` 都是 `{"id":"CC-BY-4.0","url":"https://creativecommons.org/licenses/by/4.0/","evidence":"https://作者的实际发布或授权页面"}`。`url` 是许可条款链接，`evidence` 应证明**该资源**确实适用该许可。允许的音频/封面许可 ID：`CC0-1.0`、`CC-BY-4.0`、`CC-BY-SA-4.0`、`CC-BY-NC-4.0`、`CC-BY-NC-SA-4.0`、`LicenseRef-Permission`。书面许可必须明确允许免费游戏再分发；NC 资源保留非商业限制。许可证链接本身不能证明你拥有资源权利。

谱面数据默认 `CC-BY-SA-4.0`；允许额外使用 `CC0-1.0`、`CC-BY-4.0`、`MIT`、`0BSD` 或 `Unlicense`。投稿的授权条款与每类资源的区别见[许可说明](LICENSE.md)和[贡献指南](../../CONTRIBUTING.md)。禁止没有再分发授权的商业歌曲，即使你购买了音乐或可以在线收听。

从 osu! 或其他游戏谱面转换时，必须填写 `source: {"type":"osu!","url":"原谱 HTTP(S) 链接","permission_url":"原谱师允许移植的 HTTP(S) 证据链接"}`，并在 CREDITS 中署名。自动检查无法判断未申报的移植，请如实声明。若有 `plugins`，其数组须与 `chart.json` 一致（`[{"id":"…","version":"…"}]`）。优先用声明式插件；GDScript 必须位于插件目录并标记人工审核。验证器不执行投稿脚本，脚本禁用时的验证不代表其启用后的行为。

不接受符号链接/目录联接、可执行文件、归档、备份、缓存、编辑器工作记录或额外根文件。插件可含 JSON/GDScript/Godot shader、PNG/JPG/WebP/SVG、TXT/MD、OGG/WAV 资源；单个插件文件 ≤ 2 MiB。每个投稿最多 256 个文件系统项、总计 ≤ 32 MiB，谱面 JSON ≤ 8 MiB，info JSON ≤ 64 KiB，目录深度有限。验证模拟最多 30 分钟谱面。

## 本地测试

先设置已安装的 Godot 4.7.2。验证器只用 Python 标准库，并通过无头、静音 Godot 调用真实 ChartLib 与 GameCore：

```powershell
$env:GODOT = 'E:\tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe'
python tools/validate_fan_chart.py your-slug --summary dist/fan-chart-summary.md
python tools/validate_fan_chart.py --changed origin/main...HEAD
python tools/validate_fan_chart.py  # 检查全部投稿，忽略模板
python tools/test_validate_fan_chart.py
python tools/sync_core.py          # 启动写谱器前运行
python tools/run_tests.py
```

Linux/macOS 设置 `GODOT` 指向本机引擎再用同样的 Python 命令。验证器报告结构/许可错误、ChartLib 诊断（不允许丢弃音符）、全 PERFECT 自动演奏结果、自然主键静态失败数、平均密度与一秒窗口峰值密度。静态人类按键检查仅供参考，不判投稿失败，也不能代替亲自试玩。PR 的 GitHub Actions 会检查变更目录并将结果写入 job summary；手动触发检查全部投稿。

## English

Submit an original chart through a pull request. Copy `_template` to a unique `songs/fan-made/<slug>/`, or choose **新建社区谱面…** in the charter's ⋯ menu. Use 1–48 lowercase letters/digits, `_` or `-`, starting with a letter/digit. **Do not edit the shared index.** Both apps discover submissions automatically and list them under 社区谱面 FAN-MADE, sorted by title. Hidden/underscore folders are ignored, and the template is excluded from releases.

Supply `info.json`, syntax-v3 `chart.json`, one `audio.ogg` or `audio.mp3` (≤12 MiB), `CREDITS.md`, and optionally one `cover.jpg` or `cover.png` (≤1 MiB) with its own `cover_license`. Required info fields are title, artist, version, level, bpm, preview, audio, chart_author, chart_license and audio_license. Media licences have `id`, licence-text `url`, and an `evidence` URL proving permission for the exact asset. Accepted IDs and size limits are listed above. NC assets retain noncommercial restrictions. A licence text link alone does not establish rights. No unlicensed commercial music.

By submitting, you grant CC BY-SA 4.0 for chart data; allowed permissive IDs offer additional permissions. Audio and cover retain their own stated licences. Conversions from osu! or any other game's charts **must** include source type, original chart URL and the original mapper's `permission_url`, plus attribution. See [licensing](LICENSE.md) and [contribution terms](../../CONTRIBUTING.md).

Run the validator commands above with your installed Godot 4.7.2, play the chart yourself, and attach the Markdown summary using the fan-chart PR template. ChartLib diagnostics fail validation; autoplay must finish all PERFECT. Static natural-home-key failures and density are informational. Prefer declarative plugins; submitted scripts are never executed in automation and always need maintainer review. Script-disabled autoplay does not validate enabled script behavior. Do not include symlinks, executables, archives, backups or editor state. Only the files and plugin extensions listed above are accepted.

CI checks changed folders on pull requests, or all folders on manual dispatch, without secrets or write permissions. Maintainers separately review licence evidence, attribution, conversion permission and playability before accepting a submission.
