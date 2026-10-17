# L’âge tendre Charter · 谱面工房

独立 Godot 4.7.2 桌面编谱器，入口为 `charter/charter_main.tscn`。预览直接使用游戏的 `ChartLib / GameCore / Renderer / StageFx / AudioEngine / KB / SU`，不依赖旧网页编辑器或 Python MCP 的运行服务。

## 启动

项目方式（PowerShell）：

```powershell
# 从仓库根目录执行；同步的脚本、插件、资源及 API 文档不应手动修改
python tools/sync_core.py
& $env:GODOT --path charter
```

独立程序位于 `release/LAgeTendreCharter-win64.zip`。解压后运行 `LAgeTendreCharter/LAgeTendreCharter.exe`，保留同目录的 `LAgeTendre.exe`、`KeyGuard.exe`、`songs/`。写谱器有自己的 `project.godot`、主场景和 **Charter** 导出预设，PCK 内嵌。源码试玩通过 Godot 启动 `../game`；发布版试玩启动旁边的 `LAgeTendre.exe`，歌曲、播放头、窗口与静音参数保持一致。源项目中的存档目录仍为 `LAgeTendre`。

```powershell
python tools/build_release.py
```

编辑项目时，歌曲来自相邻 `../songs/`。独立程序从 EXE 同目录的 `songs/` 读取。把一个包含 `chart.json`、`audio.mp3/ogg/wav`、可选 `analysis.json` 的歌曲文件夹放在 `songs/` 下，即可在下次启动时选择。含 `.read-only` 标记的歌曲目录禁止保存或替换音频；请编辑工作副本。构建工具重新生成 `dist/` 中的包，请把要保留的写谱内容放在独立工作目录。

## 工作方式（第四轮：界面与编辑手感重做）

默认只显示两样东西：**时间线和实时预览**（布局照 Claude 桌面版）。其余全部收起，用顶栏上带文字的开关按需打开，并记住开关和宽度（`user://charter_panes.json`）：

| 打开方式 | 内容 |
|---|---|
| 顶栏左侧「歌曲」/ Ctrl+L | 左侧栏的歌曲页：歌曲库（见下方“歌曲文件”） |
| 顶栏左侧「轨道」/ Ctrl+B | 左侧栏的轨道页：轨道列表（承载轨 / 演出轨 / 背景 / 踏板 分组；色点、编号、整首歌上的存在区间、音符数；悬停出现 显示/独奏/锁定） |
| 顶栏右侧「属性」/ Ctrl+E | 右侧停靠栏的属性页：所选音符、轨道、节点、镜头事件的属性。选择时不会自动弹出；收起时底部状态栏会说明选中了什么 |
| 顶栏右侧「Agent」/ Ctrl+I | 共用右侧停靠栏，可选择已安装且已登录的 Claude Code / Codex，或随时使用「外部 Agent」。默认选择首个可用内置后端，否则显示外部连接页；记住选择。附件、快捷请求和选区对所有后端共用，详见下方 Agent 工作流。属性和 Agent 各自记住 320–560 的停靠宽度。 |
| 顶栏右侧「脚本」/ Ctrl+Shift+E | 可调整大小的插件工房浮窗：本曲插件、只读内置插件、文件编辑、字段预览、检查和规范。默认收起，开关、位置、大小、分组和详情展开状态记在 `charter_panes.json` |
| 顶栏右侧「画面」/ Ctrl+P | 实时预览（真实游戏渲染）。右侧停靠栏收起时，预览占满右栏、保持 16:9 居中 |
| 底部条 / Alt+1…7，Ctrl+J | 抽屉：镜头与判定线、轨道属性、音乐、历史、检查、JSON（只读，可切换高级编辑）、写法与版本 |

**歌曲文件**：顶栏左侧显示当前歌名，点击打开歌曲库。歌曲库每首歌一行：封面（`_covers/` 或文件夹里的 cover 文件）、歌名、作者，游戏难度作为小标签（点标签打开该难度）。音频与某个难度完全相同的文件夹，列在那首歌下面作为“工作副本”；以下划线开头的文件夹放在最后的“其他文件夹”。上方有搜索框和“新建”。右键一行：导出歌曲包（.zip，内含精简 chart.json、音频、封面、analysis.json、chart.ext.json 和 manifest.json，manifest 里给以后的插件系统留了 plugins 列表）、导出谱面 chart.json、加入游戏歌单（写入 `songs/index.json`，难度 = 歌曲 set + 难度名，同一首歌不允许重名难度，改前先备份 index.json）、在资源管理器中显示。顶栏“⋯”菜单里有同样的导出项，以及新建歌曲、导入谱面 chart.json（作为当前歌曲的工作副本）、导入歌曲文件夹、导入歌曲包 .zip。所有导出都用系统保存对话框，目标文件已存在时先问再替换。新建歌曲：选音频，填歌名、作者、难度名和等级，BPM 可直接输入或在试听时跟着拍子敲击，点击波形设定第一拍（拍线和小节号画在波形上）；创建后得到 `songs/<文件夹>/`（音频 + 空谱面，带一条覆盖全宽的承载轨，可以立刻放音符）并加入游戏歌单。保存仍是 Ctrl+S，状态栏会写明保存到哪里、备份成了哪个文件。逻辑在 `song_library.gd`，测试在 `tests/charter_library.gd`（临时歌曲目录）。

**歌曲设置（BPM、偏移、歌名）**：不选中任何东西时，「属性」页就是歌曲设置；也可以从「⋯」菜单或歌曲库右键打开。内容：歌名、作者、难度名、等级（写进谱面 meta，可撤销；「同步到游戏歌单」再写进 index.json）；音频文件（替换前确认，旧音频改名备份）；音频偏移 `chart.offset`（音频第 0 秒在谱面时钟上的位置，秒）；节拍表 `chart.timing`：每段的第一拍位置、BPM、拍号，可以在播放头加变速、删变速、“设为第一拍”、跟着音乐敲击定速。下方是播放头附近的波形和拍线，开着节拍器播放就能听出网格和音乐是否对齐。所有数值都能滚轮、方向键或拖动调整，每次提交是一个撤销步骤，走 document.gd 的事务（`song` 目标只接受编辑器界面，MCP 不能改）。`chart.bpm` 始终跟 timing 第一段同步。音符、轨道和镜头按谱面秒存放，所以改 BPM / 第一拍只移动网格（小节号和吸附），改偏移只移动音频。另有两个需要确认的整体操作：「让 note 跟着新节拍移动」把所有事件按小节和拍位置从原网格换算到新网格（整张谱面原本按错的网格写时用）；「整体平移谱面」让音频和整张谱面一起在谱面时钟上平移。逻辑在 `song_timing.gd`，测试在 `tests/charter_timing.gd`。

**键位标尺**：时间线底部按当前键盘布局（ANSI / 短右 Shift / ISO / JIS，见 scripts/kb.gd）的 Shift 行分格：左 Shift、Z X、C V、B N、M ,、. /、右 Shift，格线作为淡竖线贯穿时间线，中心虚线保留。悬停在上下标尺上会显示指针所在位置每一排键盘对应的键。

**界面大小**：整套界面（文字、图标、间距、时间线）按 1600×900 的设计尺寸随窗口等比放大，不是只把页面拉大；Ctrl + = / Ctrl + − 在此基础上再放大或缩小，Ctrl+0 复原（记在 `charter_settings.json`）。实时预览按屏幕的真实像素渲染，放大后仍然清晰。字号只用 12 / 14 / 16 / 20 / 28 五级（设计尺寸下；文字最小 14，12 只给刻度和计数徽标），顶栏图标 20、工具行 18、行内 16，点击区域 32–36。底部右侧只显示“已保存 / 有未保存的修改”，修订号和 MCP 端口在它的悬停提示里。

**工具**（1–4 或 V/N/H/T）：选择 · 点按 · 长按 · 画轨道。点按/长按工具下指针处有吸附到网格的“幽灵音符”；规则（SPEC §2）不允许时变红，并用一句话说明原因（例如“A 键在这里没有轨道覆盖”“轨道需要从落下前 1.3 秒就存在”）。

**直接操作**：拖音符 = 改时间和落键（Shift 关吸附，Alt 拖 = 复制）；拖长按顶端 = 改长度；拖空白 = 框选；Shift/Ctrl 点击 = 加选/反选；Delete、Ctrl+C/V/D、方向键按网格/按键微调、Esc 取消。滚轮沿时间滚动，Ctrl+滚轮以指针为中心缩放，Shift+滚轮走一格网格，中键拖动平移，Space 从播放头播放/暂停，Home/End，`[` `]` 切换网格密度（每小节 1/2/3/4/6/8/12/16 分），`?` 打开快捷键表。右键音符/节点/轨道/空白都有对应菜单。

**检查器**只显示所选对象需要的字段，改动立即生效，每个手势一步撤销：数字字段可在标签上左右拖动、滚轮/↑↓ 步进（Shift 粗调、Ctrl/Alt 细调）、或直接输入（时间可写 `44.1`、`44.2+1/16` 或秒）；枚举（落键、类型、缓动、镜头词级）滚轮循环；色调是色板；不透明度是带 0/.25/.5/.75/1 刻度的滑条。多选时显示共同值，“—”表示不同，修改同时作用于全部。

## 轨道 = 可编辑的外形

选中一条轨道后，它的轮廓出现节点（方块 = 关键帧，小圆环 = 与网格线的交点）。拖节点只动这一点；拖边线 = 整条边加宽/收窄；拖主体 = 整体移动；双击边线插入节点；框选多个节点；Ctrl+点两个节点（或选两个后按 Enter）打开**片段设置**：直线 / 缓入 / 缓出 / 缓入缓出 / 自由曲线，平滑/尖角，插入/删除节点，拉平，片段中心与宽度，起止不透明度，色调。音符始终保持在自己的落键上（编辑轨道时自动重算 u）。画轨道工具可选矩形、菱形、圆、星、心形，拖出范围即创建。

今天的游戏语法只能写“左右两条边随时间变化、两边共用一个关键帧时间和一种缓动、起止边水平”的轨道。编辑器内部把轨道当成任意闭合路径（`charter/track_shape.gd`），由适配层 `charter/track_adapter.gd`（`from_events / is_representable / to_events`）决定怎么保存：

- 能用今天语法表达的形状 → 写成 light 事件，只写真正改变形状的关键帧（共线、重复的节点不写；原有事件的起点保留，保证闪光与踏板不变）。
- 不能表达的形状（星、心、自由贝塞尔、两边节点时间不一致……）→ `chart.json` 里写按网格采样的外轮廓近似，游戏照常可玩；精确形状存到同目录的 **`chart.ext.json`**，界面标出“需要新轨道语法（待引擎支持）”。引擎支持后只需替换适配层。

## 音符运动（插件）

音符默认直落到落点。选中音符 → 检查器“运动”或右键“运动”选择类型：**水平**（从侧面滑入，参数：起点偏移、开始/到位时刻、曲线）或 **跟随轨道**（今天的随轨道移动）。时间线上画出淡淡的轨迹，拖动起点圆点调整；多选可一起设置，“从中心展开”让和弦从中心向两侧散开。类型是 `charter/motions/` 下的插件，可继续添加。运动同样只存进 `chart.ext.json`，引擎支持前预览里看不到。

## 脚本与插件工房

打开歌曲后按 **Ctrl+Shift+E**，或点顶栏右侧「脚本」。浮窗使用编辑器同一套主题与等比缩放，拖动标题栏移动、拖边缘调整大小。左侧分为「本曲插件」「内置可选」「标准内置（只读）」；标准组默认收起。每行显示名称、`id@version`、声明式/脚本标签、绑定复选框和状态点；悬停状态点可读诊断。勾选绑定会修改 `chart.plugins`，一步撤销/重做；标准插件始终启用，不能取消。

**新建**提供三个模板：声明式视觉元素（光环）、声明式事件（FX 通道与字段）、脚本元素。当前 API 1 的声明式级别不能新增任意事件回调，所以事件模板沿用 `tween` / `impulse`，声明自己的 FX 通道；不是一份不可执行的虚构语法。新模板通过真实加载器的数据检查；脚本模板初始显示未信任。

中间的文件页签支持 `plugin.json`、`.gd`、`.gdshader`、`.md`、`.txt`、`.json`；显示行号和语法颜色。修改后页签带 **●**，在浮窗内按 **Ctrl+S** 保存该文件。每个文件限制 UTF-8 文本 256 KB，范围严格限制在本曲 `plugins/<id>/`；拒绝 `..`、绝对路径、符号链接/目录联接和非文本。内置插件只能阅读。保存比较读取时的 SHA-256 修订，先留 `.bak-<timestamp>` 备份，再原子替换；若外部改了文件，会让你选择重新载入、覆盖或取消。覆盖也会再次检查磁盘修订并留备份。

**文件保存立即落盘，与谱面撤销分开**；不要把“撤销 Claude 此轮谱面修改”理解为恢复已保存的脚本。启用歌曲版本管理后，「保存版本」会包含插件文件；版本差异与干净/切换检查也包含插件。首次保存插件版本时，会在歌曲 `.gitattributes` 追加 `plugins/** -text`（已有文件先备份），防止 Windows 全局 autocrlf 在切换版本时改变脚本修订字节。编辑插件时先提交一个歌曲版本便于比较和恢复。工房里尚有未保存文件时，界面会阻止切换歌曲。

下方「检查 / 字段 / 规范」可收起，记住开关。「检查」检查已保存文件，错误尽可能含文件和行号，点击可跳转；「字段」由 manifest.fields 生成数值（范围/步长，滚轮与方向键）、枚举、布尔、字符串控件，**只预览默认值，不修改谱面**，编辑有效的 plugin.json 时即时更新；object/array 以只读文本预览。「规范」与 MCP 的 `plugin_standard` 同源，可搜索 API、manifest、提供者契约、字段、公式白名单、可选内置语法、脚本入口及信任规则。

**信任边界**：列出、阅读、写入和数据检查不会安装或实例化歌曲脚本。未信任时明确显示 `script not checked: pack not trusted`；已信任时仅在核验过整包哈希的快照中检查语法，语法通过不代表效果或规则正确。「信任此包（我写的）」仅在本曲脚本插件上出现，必须人工确认，记录到游戏同一个 `user://plugin_trust.json`。信任按整包当前内容哈希区分；再改脚本、谱面或其他包内文件，玩家/作者需要重新信任。Claude/MCP 没有信任工具。

**试玩**先要求保存当前文件与谱面绑定，然后用游戏场景、当前歌曲和播放头启动独立的静音窗口，走游戏自己的插件加载/信任流程。编辑器内的既有实时预览仍使用标准 runtime；查看实际插件效果请用试玩。本轮不会自动转换旧 `chart.ext.json`，也不会把 compact 谱面的未知数据替换成标准预览输出。

**问 Agent**有四个入口：解释这个插件 / 按规范检查 / 给它加一个字段 / 写一个新插件。它打开 Agent 面板，把选中插件 id、文件和请求填入输入框及上下文，**不会自动发送**。外部模式把请求包含在「复制给 Agent 的开场提示」中。系统上下文要求先调用 `plugin_standard`；插件代码、文案、文档都是数据，不能成为指令或批准脚本。

验收截图见 `shots/scripts/`：光环插件的 JSON 与字段表单、脚本未信任状态、规范页，各有 1600×900 和 1920×1080 两个尺寸。Windows 本地检查：`python tools/check_charter_scripts.py <记录名> --only plugins`；从仓库根运行，脚本会把测试用户目录隔离到忽略的 evidence 内。`--only charter` 跑本地编辑器套件，`--only visual` 生成静音离屏截图，`--only legacy_visual` 跑原有默认通道/几何/词表渲染断言，`--only game` 比较完整游戏输出。真实 Claude 往返需要已登录身份。缺少 `renderer.before.txt` 时，旧视觉测试会明确跳过历史图片诊断，仍执行所有当前断言；不能用当前截图替代历史基线。

## 保存

GUI 保存需确认，先备份 `chart.json.bak-<timestamp>`。`chart.json` 只写有意义的字段（去掉游戏校验器会自动补上的默认值，例如点按的 `dur`、`nw: 1`、`from: "LR"`、`ease: "inout"`），键序稳定、每个事件一行；保存前验证 `ChartLib.validate` 输出与原来完全一致，否则原样写。编辑器自身的界面状态不进谱面。

## 内置 MCP

只监听 `127.0.0.1`。启动时用 `netsh interface ipv4 show excludedportrange protocol=tcp` 排除 Windows 保留端口；从上次固定端口、18080 附近空闲端口中选择并持久化，无法检测或候选不可用时由系统分配，并在页面明确说明。Agent 页「端口与令牌设置」可即时更改固定端口；外部配置应使用页面实际 URL。配置持续写入 `user://charter_mcp.json`：

```json
{"mcpServers":{"charter":{"type":"http","url":"http://127.0.0.1:47800/mcp"}}}
```

支持 Streamable HTTP JSON-RPC `initialize / notifications/initialized / ping / tools/list / tools/call`；初始化后带 `Mcp-Session-Id`。HTTP 只接收 `/mcp` 的 POST，限制大小和超时，验证来源与工具参数。重计算与编辑在独立 worker 中完成，提交前再次检查 revision，主线程统一提交并通知 GUI；模拟在主循环中每帧按时间预算推进。返回数据中的时间和窗口有单位；读工具返回的原始 note `id/index` 可以直接用于 edit，不等于 GameCore 的排序后 core_id。

以下例子是 `tools/call.params.arguments`。写操作先读 `song_info.revision`，把例子中的 `REV` 替换为当前值。范围 `[from,to)`。

| 工具 | 返回与例子 |
|---|---|
| `song_info` | 标题、音频路径/时长、谱面时长、offset、BPM、timing、meta、revision。`{}` |
| `time_map` | 位置转换与网格。`{"points":["44.1",55.268],"from":"44.1","to":"45.1","div":16}` |
| `selection` | 当前 GUI 时间、轨道、音符和 FX 选择。`{}` |
| `tracks` | 轨道角色、生命周期、原始事件、音符索引、移动键数/秒。`{}` |
| `track_state` | x/w/a/tint、边界键单位、覆盖键。`{"id":200,"at":"44.1"}` 或 `{"from":"44.1","to":"45.1","step":0.1}` |
| `notes` | 原始索引、bar.beat、轨道、落点、指法/提示、手、chord、hold ticks、裁切后的早晚窗口及裁切邻居、同键前后间隔。`{"from":"44.1","to":"45.1"}` |
| `camera` | FX、采样值和词语、词表、只读场地参数。`{"from":"44.1","to":"45.1","step":0.25}` |
| `music` | 现有分析的六分格、每拍/每小节、onsets、重音、分离音轨 RMS、音高/keysound 参考、场外声音、能量与来源。`{"from":"44.1","to":"45.1"}` |
| `analysis` | 每小节/手密度、最大和弦、jacks/trills、轨道移动、覆盖违规和原游戏校验警告。`{"from":"44.1","to":"48.1"}` |
| `simulate` | 延后运行真实 GameCore。`{"player":"autoplay"}`、`{"player":"home"}`、`{"player":"offset","offset_ms":-60}`、`{"player":"fat_finger"}`；返回 job_id 后 `{"job_id":"ID"}` 轮询至 done，获得总分、grades 和非 PERFECT 位置。偏移可用 ±30/60/100 ms。 |
| `history` | 当前 undo 的标签/作者与 redo 数。`{}` |
| `edit` | 原子批次，顺序索引相对前一步。`{"expected_revision":"REV","label":"微调","ops":[{"target":"notes","op":"update","index":530,"value":{"t":55.3}}]}`。target 为 notes/lights/fx；op 为 add/update/delete；add/value 完整对象，update/value 字段补丁，delete/index 索引。meta 使用 `{"target":"meta","value":{"kiai":[]}}`（替换完整 meta，先读后保留其余字段）。 |
| `camera_move` | 词语或数字生成 FX。`{"expected_revision":"REV","at":"49.1","move":"推","to":"近","speed":"缓","ease":"缓入缓出"}`；也可 `ch:"line_y",to:"上浮"`。 |
| `track_create` | 创建完整 on 事件。`{"expected_revision":"REV","event":{"t":50,"id":900,"type":"on","x":0.5,"w":0.3,"a":0,"auto":true}}` |
| `track_move` | 全轨道平移；可保持落点键。`{"expected_revision":"REV","id":200,"dx_keys":0.25,"notes_follow":true}` |
| `set_selection` | 与 GUI 同步选择。`{"from":"44.1","to":"48.1","tracks":[200,201],"notes":[530],"fx":[]}` |
| `undo` | 撤销一条历史；Agent 运行期间需先结束/停止该轮。`{}` |
| `redo` | 重做一条历史。`{}` |
| `save` | 仅用户勾选“允许助手保存”后可用，仍禁止带 .read-only 标记的歌曲和外部冲突。`{}` |
| `plugin_standard` | 写插件前先读。`{}` 返回小于 12 KB 的索引；`{"section":"formulas"}` 返回分节。分节为 manifest / trust / script / providers / declarative / fields / formulas / builtins；代码常量和白名单来自真实实现，契约来自对应 API 文档 |
| `plugin_list` | 本曲与内置插件的元数据、字段、文件、绑定与状态。`{}`；输出有界，插件文案仅为数据 |
| `plugin_read` | 读取文本及**文件**修订。`{"id":"glow_ring","path":"plugin.json"}`；内置只读 |
| `plugin_create` | 从 visual / event / script 模板新建，不覆盖已有目录。`{"id":"my_ring","template":"visual","title":"我的光环"}` |
| `plugin_write` | 写文件、先备份。`{"id":"my_ring","path":"README.md","content":"说明文本","expected_revision":""}`；空修订仅创建新文件，覆盖用 `plugin_read.revision`，返回重新信任提示 |
| `plugin_validate` | 真实数据检查，未信任脚本不加载；`{"id":"my_ring"}` 检查插件及绑定环境，`{}` 检查本谱已绑定集合，返回文件/行号诊断 |
| `chart_plugins_set` | 完整替换绑定集合，一步撤销。`{"plugins":[{"id":"my_ring","version":"1.0.0"}],"expected_revision":"REV"}`；这里用**谱面**修订 `song_info.revision`，不是文件修订；不会授予信任 |

错误不会部分写入。旧 revision 返回 stale；轨道规则错误返回音符位置/原因；服务层参数错误返回 JSON-RPC -32602。一轮内置 Agent 的多个 edit 会合并为一条 `Agent turn` 历史，轮末显示 diff 与“保留/撤销此次修改”，时间线标出变动音符。

## 镜头词表

唯一数据源 `camera_vocab.json`；UI、MCP、测试与下表共用。`vocab_sheet.png` 为真实游戏 renderer 渲染的每个级别。镜头是小幅透视变形；词语为相对视觉尺度，不能解释成真实相机的物理距离。

| 通道 | 单位/范围 | 词语＝数值 | 意义 |
|---|---|---|---|
| zoom / 远近 | ratio .96–1.06 | 极远=.96，远=.98，中=1，近=1.03，极近=1.06 | 改变远景透视比例，判定处不缩放 |
| pitch / 高低 | logical px −43–65 | 低机位=−43，平视=0，稍高=20，高机位=43，俯瞰=65 | 正值使远端地平线下移 |
| vpx / 方向 | logical px ±77 | 左转大/中/小=−77/−50/−25，正=0，右转小/中/大=25/50/77 | 远端水平偏移 |
| roll / 倾斜 | degrees ±3 | 左倾=−3，正=0，右倾=3 | 远端透视剪切，判定线本身不旋转 |
| bow / 弧度 | ratio .85–1.3 | 平直=.85，微弯=1，弯=1.15，大弯=1.3 | 透视收窄指数；固定 arc0 不变，平直为相对词 |
| exposure / 曝光 | ratio .25–1.15 | 暗场=.25，昏暗=.55，正常=.85，明亮=1.15 | 舞台/背景亮度 |
| trauma / 抖动 | amplitude 0–.5 | 无=0，微=.08，轻=.18，中=.32，强=.5 | 平方幅度噪声；camera_move 用 impulse |
| flash / 闪光 | alpha 0–.25 | 无=0，微=.05，亮=.15，强=.25 | 全场闪亮 |
| kick / 节拍冲击 | amplitude 0–1 | 无=0，轻=.25，中=.5，强=1 | 轨道边缘辉光 |
| rush / 速度感 | ratio .5–3 | 缓=.5，常=1，快=2，急=3 | 仅小节线流动，音符速度不变 |
| line_y / 判定线高度 | screen fraction ±.04 | 上浮=−.04，原位=0，下沉=.04 | 判定几何上下移动 |
| line_tilt / 判定线倾斜 | degrees ±2 | 左倾=−2，正=0，右倾=2 | 全部场地层绕判定中心旋转，独立于 roll |
| line_glow / 判定线辉光 | ratio .5–1.5 | 隐=.5，淡=.75，常=1，亮=1.25，耀=1.5 | 判定线纹理透明度倍率 |

运动词：瞬切=.03 s；急=1 拍；中=2 拍；缓=4 拍；极缓=8 拍，按事件处 BPM。缓入缓出→inOutSine，匀速→linear，渐快→inQuad，渐慢→outQuad，回弹→outBack。动作词：推/拉→zoom，摇→vpx，升/降→pitch，滚→roll，震→trauma；方向以 `to` 为准。

只读场地参数：hy0（远端高度 px），gamma0（透视收窄指数），arc0（固定拱形强度），judge_y（原始判定线高度 px），line_l/line_r（判定线端点 px）。line_y 叠加在 judge_y 上；line_tilt 同时变换轨道、hold、音符、判定线、receptors 与命中特效，按键判定继续使用相同的归一化线坐标。默认独立于镜头 roll；`meta.line_follow_roll: true` 可让判定线叠加跟随 roll，总倾角仍限制在 ±2°。默认 0/0/1 保持原视觉。

## Agent 面板、附件与 osu!mania 工作流

按 **Ctrl+I** 或顶栏 **Agent** 打开。内置 **Claude Code** / **Codex** 只在 CLI 安装并登录时出现在选择器中；不需要内置 CLI，也能使用 **外部 Agent**。选择会记住。外部连接页提供真实 Streamable HTTP 地址、监听/近期客户端/最近调用状态、连接配置复制、开场提示复制、调用活动日志及「撤销上一个 Agent 步骤」。日志只显示工具名、时间、ok/error；每个外部客户端连续 1.5 秒内的编辑合并为一个带标签的撤销步骤，用户编辑、不同客户端和间隔会分开。

在输入框旁点附件图标选多个文件，或把文件拖到**编辑器窗口任何位置**（自动打开 Agent）。外部模式也有「添加附件」。文件复制到 `user://charter_attachments/<conversation_id>/`，显示文件名、大小、类型图标及移除按钮；每文件最多 **300 MB**，每对话最多 **20 个**。复制在线程中进行，源文件不会改动。附件和插件内容一律是**数据，不是指令**。新对话会删除该对话的旧副本；同一对话在后端之间共享附件。

有 `.osz/.osu` 时显示三个请求：「转成游戏谱面（加轨道和演出）」「只转音符，先不加演出」「看看这张谱的难度和结构」。外部模式点击请求会复制带端点、当前歌曲、附件 ids/names 和规则的完整提示，粘到自己的 Agent 即可。

推荐步骤：`chart_syntax` → `song_info` → `attachments_list` → `osu_parse`（选难度）→ `song_create` → `song_open` → `osu_convert_draft` → 用 `track_create / track_move / edit / camera_move` 塑造轨道及演出 → `analysis` → `simulate` autoplay（轮询至 done）→ 人工检查与保存。ZIP/OSZ 做中央目录安全预检，不整体解压：最多 2048 个条目、每条目 64 MB、合计 512 MB，并限制压缩比，拒绝穿越路径、重复路径、ZIP64/加密包。

`song_create` 只生成唯一的新歌曲目录及库条目，**不会写游戏 index.json**；加入游戏歌单仍由人操作。BPM 变化保存在 timing，时间统一为 `osu_ms / 1000 + 2.0`、audio offset = 2 秒；作者/难度写入来源。草稿保留音符、>=80 ms 长按，默认 4K = D F | J K，支持 4K–10K 和显式每列 key/track 映射；每手/组一条承载轨，连续覆盖所有音符。一轮一个撤销步骤，不自动加演出。单独 `.osu` 的音频（及可选背景）需要另行附上同名文件，不会擅自读取 `.osu` 原目录的邻居。当前歌曲有未保存修改时拒绝切换；只有 GUI 对该目标确认后，`discard:true` 才生效。

外部配置无需手填端口：选择 Claude Code 命令、Codex TOML、Cursor/通用 mcp.json 或 VS Code 格式，复制页面生成的片段。支持 stdio 的旧客户端可自选 stdio↔HTTP 桥，不附带桥接器。「访问令牌」默认关闭；打开后所有 HTTP 请求必须带 `Authorization: Bearer <token>`，每种配置都自动包含令牌。重新生成令牌会使旧令牌失效；配置和令牌只保存在本机 user://，不要公开分享启用令牌后的配置。

Claude Code 以 `-p --output-format stream-json --verbose --include-partial-messages` 启动，仅启用 charter MCP、禁用内置文件/命令工具和 hooks。Codex 使用 `codex exec --json --sandbox read-only`，通过 `-c mcp_servers.charter.url=...` 及 HTTP header 覆盖连接本编辑器；忽略其它用户 MCP 配置以避免连接无关服务，使用 CLI 自身登录。参数依据安装 CLI 帮助与[官方配置参考](https://developers.openai.com/codex/config-reference/)。两个后端都异步读取 JSON 事件、显示工具活动、可停止并按 PID 结束子进程。身份可用不等于已经验证远程模型执行；自动验收不需要登录，不调用模型。

保存谱面与保存版本始终分别受 GUI 勾选权限控制，外部 Agent 同样适用；没有工具能授予插件信任。

| 新 MCP 工具 | 用途与示例 |
|---|---|
| `attachments_list` | 本对话附件 id/name/bytes/sha256/kind。`{}` |
| `attachment_read` | UTF-8 文本按字节翻页，每次 <=64 KB；OSZ 不给 entry 则列目录。`{"id":"a_ID","entry":"map.osu","offset":0,"limit":16384}` |
| `attachment_image` | 原生 MCP PNG 图像，PNG/JPEG 解码前检查尺寸，最长边 <=1024。`{"id":"a_ID","entry":"bg.jpg","max_side":512}` |
| `osu_parse` | 元数据、键数、BPM/拍号/SV、统计和音符分页；OSZ 未指定 entry 列难度；非 mania 清晰报模式不支持。`{"id":"a_ID","entry":"map.osu","offset":0,"limit":256}` |
| `song_create` | 唯一新建，不覆盖、不同步游戏歌单。`{"from_attachment":"a_ID","osu_entry":"map.osu","dir":"new_chart"}` |
| `song_open` | 安全打开库内歌曲；未保存先拒绝。`{"dir":"new_chart"}` |
| `osu_convert_draft` | 新空谱内一次事务转草稿。`{"id":"a_ID","osu_entry":"map.osu","mapping":["D","F","J","K"]}`；也可用 `[{"key":"D","track":0},...]` |
| `chart_syntax` | 无 section 返回 <12 KB 索引；syntax/notes/judgement/camera/keyboard/warnings 分节，来自代码常量及同步的 CHART_SYNTAX 文档。`{"section":"notes"}` |
| `preview_frame` | 暂停播放后获取 chart seconds = at 的真实实时预览 PNG，最长边 1280；需要离屏图形渲染，纯 headless 无像素时明确报错。`{"at":3}` |

`edit` 现支持一批最多 **10000** 条操作，整批一次验证、一次撤销；HTTP 请求体仍限 2 MB。长计算在 worker 中运行；失败保持原文档。图像只用于检查演出时刻，判断应先读结构化数据。

验收：`python tools/verify_agent_io.py charter_agent_io charter_agent_http charter_agent_visual`。生成器 `tests/fixtures/generate_osu.py` 只用 Python 标准库生成原创 4K/7K、变速/SV/长按、WAV 和 OSZ；**编辑器运行不依赖 Python**。前两套 headless，visual 离屏静音，截图位于 `shots/agent-io/`。`python tools/run_tests.py` 包含新数据/HTTP 测试，新截图测试通过上述独立命令运行。测试用 user:// 位于仓库 dist 下，原歌曲不改动；日志保留 Godot 的证书和退出清理诊断，不把图像/断言通过解释为这些引擎诊断已修复。

## 音乐分析与验证

```powershell
python tools/run_tests.py --suite charter --visual
# 也可使用保留的专用验证入口
python charter/verify.py --visual
```

预生成的 `songs/<dir>/analysis.json` 保留源文件 SHA-256、真实 PCM 峰值波形与分离音轨 RMS。原先的外部 Python 音乐分析环境与旧网页源码未包含在当前仓库中；运行写谱器不依赖它们。分析中的 reference_note_index 是参考谱索引，**不能当成当前工作谱的音符 ID**；onset 强度不是 RMS，二者分开标注。

测试：`charter_model.gd`（模型/规则/保存）；`charter_tools.gd`（读工具/原始索引/notes-follow/锁定/词语/模拟）；`charter_http.gd`（真实 HTTP 和非法参数拒绝）；`charter_ui.gd`（时间线双击、检查器、锁定、镜头曲线与确认保存）；`charter_library.gd`（临时歌曲目录上的新建歌曲、index.json 更新与备份、歌曲库分组、导出 zip 内容、导入、不经确认不覆盖）；`charter_visual.gd`（原 renderer 对照、跟随倾角限制、完整词表）；`charter_claude.gd`（真实 CLI，需有效登录）。`verify.py --visual` 加入离屏图像，`--game` 重跑原游戏七个脚本，`--claude` 加入真实 CLI 往返。原游戏七个测试日志与结果在 `evidence/game_tests.json`。所有验证静音；渲染窗口使用 `--position -5000,-5000`，截图在 `shots/`（不缩放的 1600×900 / 1920×1080）和 `shots/scaled/`（`--shots-scaled`：打开等比缩放，在 2880×1800 与 1920×1080 窗口下截图，即在 2880×1800 屏幕上实际看到的样子）。

`evidence/default_before.png` 与 `default_after.png` 对比证明一个确定帧的默认像素一致；不把它扩大为所有状态的穷尽证明。工作日志记录实际完成情况和剩余边界，只有所有要求完成才写 CHARTER_APP DONE。

## 第二轮：写法、对比与侧栏

展开 Agent 页或刷新状态时，异步调用 CLI 自身的状态命令：`claude auth status --json`、`codex login status`。只保留是否可用，不读取登录凭据，不触发登录/退出登录。需要重新登录时请在终端操作，然后在面板菜单刷新状态；没有可用 CLI 时始终可以使用外部 Agent。

时间线与 16:9 实机预览之间可拖动；“预览”隐藏画面。“侧栏”或右侧箭头把检查器和 Agent 收至图标栏；展开后拖动其左边界调宽（320–560 逻辑像素）。左侧按承载轨、演出轨、背景、踏板分组，超过 20 条默认折叠；按首次事件排序，用微型条显示生命周期。透明轨道显示轮廓符号，时间线用断续边界。指法默认仅悬停/选择显示，可开“显示指法”。“显示通道”选择最多四个并排镜头/判定线曲线，默认远近、判定线高度与辉光。

内置后端使用 CLI 默认模型，不提供模型选择器。选区 chip 随 GUI 改变，可固定选区。每首歌的消息、各后端 session_id 和附件 conversation_id 保存在 `user://conversation-<路径摘要>.json`；重启恢复。「新对话」清除旧消息、会话和旧附件副本并使用新文件夹；系统不会改动附件源文件。导入流程中的 song_open 保留同一对话及附件。

“版本…”先展示当前歌曲的写法与提交。只有用户点击“启用版本管理”才创建该歌曲自己的 .git；测试只在 charter/evidence/version-test-* 副本执行。不会自动初始化真实歌曲、导入分支或提交。启用后点击“保存版本”建立第一版，然后可创建、切换、重命名写法；删除须确认且不能删当前写法。未提交改动阻止切换。已有仓库若跟踪 chart.json/.gitignore 以外的文件，应用拒绝切换，避免改动额外文件。

普通工作副本保存时使用稳定键序、每个 note/light/fx 一行。未编辑的普通保存保持字节原样；首次保存版本会规范化工作副本。autosave 不进入版本提交。提交仅包含 chart.json 与 .gitignore，忽略音频、备份、分析和缓存；无远程、无 push。GUI 版本说明可编辑，默认取上次提交后的撤销标签。Claude 保存版本需要分别启用保存与版本提交权限。

其他歌曲的导入按钮从现有文件读取，在当前歌曲仓库创建对应分支；保留原目录，不切换当前工作文件。比较输入框以逗号填写 2–4 个分支、提交 ID 或 working，再点“比较”。各列共用纵向音乐时间、滚动与缩放，底部仅一份波形/能量；第一列为基准，绿色新增、红色删除、黄色移动、紫色属性变化，边缘热条表示每小节变化数。悬停查看精确对象差异。支持“叠加”，聚焦某列后预览使用该列独立 GameCore。拖选范围后右击执行“这段用该写法”；原子验证接缝，冲突直接拒绝。清空比较输入框再点比较退出。



所有下表及原有读工具支持可选 `version`（分支/提交/working），无需切换当前写法。模拟依旧返回 job_id 并通过 simulate 轮询。

| 新工具 | 示例与返回 |
|---|---|
| `versions` | `{}`：是否启用、分支、提交时间/作者/说明、当前写法、工作 revision/dirty。只读，不初始化。 |
| `diff` | `{"base":"main","other":"alternative","from":"44.1","to":"48.1"}`：对象 before/after、变化类型、秒差与每小节热度。 |
| `compare_stats` | `{"versions":["main","alternative","working"]}`：每版 density、motion、warnings 与真实模拟 job_id。 |
| `branch_create` | `{"name":"alternative"}`：从 HEAD 创建分支，不自动切换或提交。 |
| `branch_switch` | `{"name":"main"}`：清洁工作区切换并重载。当前轮已有未提交编辑时拒绝。 |
| `commit` | `{"message":"Claude: soften the camera"}`：需用户分别开启允许保存/允许保存版本，创建显式提交。 |
| `take_range` | `{"version":"main","from":"44.1","to":"48.1","expected_revision":"REV"}`：替换 [from,to) 的 notes/lights/fx，单步撤销，接缝校验。 |

第二轮验证：`python charter/verify.py --visual --game`；`tests/charter_versions.gd` 在新建临时副本测 git 与段落往返。截图含 dark/light、侧栏展开/收起、三列对比，分别为 1600×900 / 1920×1080。Claude 的真实只读工具回合仍需有效 CLI 登录，用 `python charter/verify.py --claude` 单独复查。

