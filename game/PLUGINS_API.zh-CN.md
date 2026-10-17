# L’âge tendre 插件作者指南 — API 1

[English](PLUGINS_API.md) · Godot 4.7.2 · GL Compatibility

本指南说明已经实现的 API 1 注册表、提供者和歌曲会话接口。它是作者与集成方的
参考文档，不表示某个施工阶段已经验收；阶段状态以仓库工作日志和实际门禁为准。
这里的写谱器接入部分只写方案，不修改独立维护的 `charter/`。

## 1. 歌曲包、依赖与第一个可运行插件

源树的两个顶层目录保持相邻：

```text
songs/<歌曲目录>/
  chart.json
  audio.wav
  plugins/<插件-id>/
    plugin.json
    entry.gd                 # 仅脚本级需要
    ...数据、已列出的资源...
```

谱面必须显式声明使用的插件：

```json
{"plugins":[{"id":"glow_ring","version":"1.0.0"}]}
```

解析依赖时先查可用内置插件，再查本歌曲的 `plugins/<id>/plugin.json`，递归包含
其必要依赖。仅仅把文件夹放进歌曲并不会激活插件。没有插件要求的旧谱只使用
`standard_chart`、`standard_render`、`standard_rules`、`standard_stage`；这条
路径不扫描、不计算歌曲目录哈希。可选内置插件不会因出现在安装目录而自动生效。

下面是完整的纯声明式 manifest，可保存为 `plugins/glow_ring/plugin.json`：

```json
{
  "id":"glow_ring", "version":"1.0.0", "api":1, "tier":"declarative",
  "title":"蓝色音符光环", "author":"示例作者",
  "description":"只增加视觉光环，不改变时间、判定轨道或计分。",
  "provides":{"flags":["ring"],"elements":["glow_ring"]},
  "fields":[{
    "path":"notes[].ring", "type":"number", "unit":"键宽",
    "min":0, "max":4, "step":0.25, "default":0,
    "doc":"音符外圈的视觉半径，单位为局部键宽；0表示隐藏。"
  }],
  "assets":[], "entry":null,
  "requires":[{"id":"standard_render","version":"1.0.0"}],
  "definitions":{
    "flags":{"ring":{"field":"ring"}},
    "elements":{"glow_ring":{
      "kind":"glow_ring", "field":"ring", "radius":"value",
      "opacity":"alpha * (0.5 + 0.5 * progress)",
      "color":[0.42,0.78,1,0.85], "width":2, "order":41
    }}
  }
}
```

配套的完整小谱：

```json
{
  "bpm":120,
  "plugins":[{"id":"glow_ring","version":"1.0.0"}],
  "lights":[{"t":0,"id":0,"type":"on","x":0.5,"w":0.4,"a":0.5,"auto":true}],
  "notes":[{"t":2,"light":0,"u":0.5,"kind":"tap","ring":1}]
}
```

必须有对应 `flag`：单独写字段说明不会自动保留音符字段，也不会凭空生成绘制实现。
带项目原有演示音频的完整实例见 `songs/_plugin_demos/glow_ring/`。
同级 `script_trust/` 额外提供需信任的金色装饰；拒绝脚本后蓝色光环仍有效。
`_plugin_demos/index.json` 是选歌菜单的补充索引，原歌曲索引和原歌曲不变。
主程序先按原逻辑建立旧分组，再追加校验通过的示例分组，不与旧组混合；补充索引
可以缺省。文件上限 1 MiB、数组上限 512 项。每项须有非空 dir/title/artist/version，
set 默认 title；文本最多 256 字符，不允许 C0/DEL 控制字符。dir 必须恰好为
`_plugin_demos/<直接子目录>`。chart.json、audio 文件名（默认 audio.mp3）、可选的
相对 songs 根目录 cover 都须真实存在且留在该根目录内；拒绝路径穿越、drive/UNC
越界及任意祖先符号链接。目录重复按大小写不敏感检测；同一新组的标题、作者、
BPM、时长、封面、preview 必须一致，仅在新组内部按 level 排难度。

数值必须有限且不能是布尔值：bpm `[0.001,1000]`，length `[0.001,86400]` 秒，
preview `[-1,length]`（缺省 -1），level `[0,100]`（缺省 1），notes `[0,1000000]`
（缺省 0）。非法项会忽略并在菜单显示至多 8 条提示；坏格式、超限或不安全索引
不破坏旧歌单。这些是菜单元数据边界，不是新判定规则。选择 script_trust 时仍走
正常内容哈希信任弹窗，枚举菜单不会执行脚本。


## 2. Manifest 与版本规则

必须包含 `id`、`version`、`api`、`tier`、`title`、`author`、`description`、
`provides`、`fields`、`assets`、`entry`。

| 字段 | API 1 含义 |
|---|---|
| `id` | 匹配 `^[a-z][a-z0-9_.-]*$`，本地插件目录名必须相同。 |
| `version` | 严格的 `major.minor.patch`；不支持后缀、前导零。 |
| `api` | 数值 `1`；未知版本在安装前报错。 |
| `tier` | `declarative` 或 `script`。声明式 `entry:null`；脚本入口为相对 `.gd` 路径。 |
| title/author/description | 非空字符串，用于展示作者信息和用途。 |
| `provides` | 类别到不重复提供者 ID 数组的对象，只接受真实注册表类别。 |
| `fields` | 完整字段说明，见 §7。脚本字段说明自身不是实现。 |
| `assets` | 已列出数据/资源的相对路径。拒绝绝对路径、协议、`..`、空路径段、反斜杠和符号链接。 |
| `requires` | 可选的 `{id,version}` 数组，先安装依赖。 |
| `definitions` | 声明式各项 `provides` 对应的真实实现数据，见 §6。 |

依赖支持精确版本、`*`、`^major.minor.patch`。Caret 表示不低于要求的版本且
非零主版本相同；`^0.y.z` 限于相同的非零次版本 `y`；`^0.0.z` 只匹配自身。
缺失插件、不兼容版本、重复谱面要求、重复包 ID、依赖循环都会明确报错。
会话不会自动下载依赖。

提供者 ID 只按类别隔离，不自动加插件 ID 前缀。应选不易冲突的名字。加载器会
检查每项声明确实由该插件注册，也拒绝未声明的注册。注册表采用事务提交；受信任
脚本任意产生的文件、网络等副作用不能因此自动回滚。

行为变化时请升级插件版本。信任按内容哈希区分，成绩按 `id@version` 区分；只改
字节、不升版本会重新询问信任，但不会产生新的成绩身份。

## 3. 信任、载入、卸载与身份

使用 `SongPluginSession`。不要为了读取元信息先 `ResourceLoader.load` 歌曲
GDScript：加载时就可能执行 `_static_init()`。

以下是宿主函数内部的流程片段；异步弹窗与正常游玩循环由宿主负责：

```gdscript
var session := SongPluginSession.new()
var report := session.prepare(song_folder, raw_chart, chart_id)
if not report.errors.is_empty():
    return                         # 展示错误，禁止开局
if report.requires_trust:
    return                         # 展示允许/拒绝/取消，等待真实选择
# 允许/拒绝回调中先调用 remember_trust(true/false)，再调用 open()。
var opened := session.open()
if not opened.errors.is_empty():
    return
var core := GameCore.new(session.registry)
if not core.load_chart(session.chart_data):
    core = null
    session.close()
    return
var renderer := Renderer.new(session.registry)
# renderer 加入场景、正常游玩，并持续显示会话提示。
# 退出时先断开宿主回调、释放 renderer、清除 core/stage 引用。
renderer.free()
renderer = null
core = null
session.close()
```

`prepare(folder:String, raw:Dictionary, chart_id:String) -> Dictionary` 只检查
文件与数据。报告含 `errors`、`notices`、`script_ids`、`content_hash`、
`requires_trust`、预计启用的 `identity`、`score_key`、`disabled`。不运行未信任代码。
玩家明确选择后，`remember_trust(allowed:bool) -> bool` 再检查字节，将这一个
哈希的允许/拒绝记入 `user://plugin_trust.json`。取消只需关闭尚未打开的会话。

`open() -> {errors,disabled,loaded}` 重新读取决定并验证文件。未知脚本信任会阻止
启动；拒绝会禁用脚本及依赖它的包，独立声明式部分仍加载。界面须持续显示具体
禁用 ID，包括游玩中；降级状态不能冒充完整组合。损坏的信任文件仍按未知处理；
用户新选择只能在原字节备份成功后恢复记录。哈希或保存失败不等于默认允许。

内容哈希使用 SHA-256，按排序后的相对文件名和全部字节做长度分隔编码，包含音频、
图片、README 与隐藏文件。拒绝路径穿越和符号链接。相同字节的包移动位置不影响
记录；任一包含文件变化都会重新询问。大包哈希确实有 I/O 成本，旧无插件谱完全
避开这条路径。

允许脚本后，会话在 `user://plugin_sessions/` 建立唯一整包快照，再核对批准哈希，
从快照加载。原因是已实测 Godot 4.7.2 即使用 `CACHE_MODE_IGNORE_DEEP` 刷新入口，
仍可能复用旧的相对 `preload()` 依赖。包内依赖请用相对路径。快照包括媒体，会
临时占用一份完整包的磁盘空间；`close()` 不跟随符号链接地删除本次快照，也检查
祖先链接，可能保留空的哈希分组目录。

这不是 GDScript 沙箱。受信任脚本可使用应用、文件和网络 API；绝对路径、包外
或动态构造的加载不受相对快照机制约束。合作式清理不能撤销任意外部副作用，
也不保证抵挡恶意受信任脚本造成的文件系统竞争。

成功 `open()` 后，以 `session.registry`、`chart_data`、`identity`、`score_key`
为准。身份是实际启用的包与依赖闭包的有序版本列表，总包含四个标准包。
注册表只属于本次运行。`PluginRegistry.standard()` 是独立缓存的四标准目录；
`builtins()` 是含可选插件的可用目录，不是当前歌曲选择。不能修改这两个基础目录。
`runtime_notices()` 返回去重的持续提示和公式运行错误；宿主只需对插件歌曲低频轮询。

## 4. 脚本入口与合作式所有权

入口导出 `static func install(registry, manifest, folder) -> void`。加载器调用时
已经设置当前包为注册所有者。可选 `static func teardown(registry) -> void`
会在安装前自动登记。外部受信任插件收到的 `folder` 是已验证快照中的插件目录，
不一定是原目录。

```gdscript
@static_unload
extends RefCounted

static var state: Node

static func install(registry: PluginRegistry, _manifest: Dictionary, _folder: String) -> void:
    state = registry.own(Node.new())
    registry.register("elements", "my_decoration", {
        "phase":"plugin.my_package.decoration", "order":41,
        "additive":true, "callback":draw
    })

static func draw(renderer, canvas: CanvasItem) -> void:
    if renderer.f.is_empty() or not renderer.f.get("play", false): return
    canvas.draw_circle(Vector2(960, 150), 4.0, Color(0.4, 0.8, 1, 0.6))

static func teardown(_registry: PluginRegistry) -> void:
    state = null                    # registry 负责释放自己持有的 Node
```

manifest 要在 `provides.elements` 声明 `my_decoration`，仍填写 §2 的完整字段，
并设 `tier:"script"`、`entry:"entry.gd"`。

作者常用接口：

- `register(category:String,id:String,provider:Dictionary,replace=false) -> bool`。
  注册表补入 `id`、`plugin` 所有者与整数 `order`，默认顺序 0。重复 ID 默认
  失败；显式 replace 只应发生在当前工作会话。若有意替换已有提供者，应声明其
  原包和版本依赖。不能修改基础目录或标准判定规则。
- `get_entry(category,id) -> Dictionary`、`ordered(category,phase="") -> Array`。
  先按 order 升序，同序按 ID 字典序。返回记录视为只读；`field_schema()` 返回深拷贝。
- `own(object:Object) -> Object` 持有对象直至卸载。非 RefCounted 对象被 free，
  RefCounted 资源被释放引用。不会自动将 Node 加入场景，也不会替你清掉别处引用。
- `connect_owned(signal:Signal,callback:Callable,flags=0) -> Error` 登记需清理的
  信号；`on_close(callback:Callable) -> bool` 登记关闭回调，唯一参数是该注册表。
- teardown 按安装/登记逆序执行，然后断开 owned 信号，释放 owned 对象和目录回调。
  失败安装也走清理。关闭时不要假定 Renderer 还存在。作者必须清理自己保留的
  static/global 引用、计时器、线程和外部工作。RefCounted 回调宿主要用 own 持有，
  不能把 Callable 本身当作可靠的生命周期管理。

高级内置实现还使用 `register_service(id,script:Script,replace=false)`。service
是旧 facade 选用的工厂：`chart`、`game_session`、`stage`、`renderer`、`ranks`；
不属于 `provides` 类别，也不是自动创建任意服务的生命周期接口。替换 service
必须满足完整 facade/runtime 契约，普通扩展应使用提供者。`begin_plugin/end_plugin`、
`adopt`、直接调用 loader 是基础设施接口，正常由加载器/会话管理。

## 5. 九种注册类别的真实契约

`note_kinds` 与 `flags` 是两类，总计九类；service 单列。除特别说明外，回调
返回值忽略，通过共享字典修改结果。规则和绘制回调收到的是实际 runtime 对象，
不是兼容 facade。

### validators

提供者 `{order,callback(context)}`。初始 context 为 `{raw,chart:{},registry}`。
按排序执行；标准校验器 order 0，将规范化结果赋给 `context.chart`。前置校验器
可以替换 `context.raw`；后置校验器检查/扩展 `chart`，向 `chart.warnings` 加
字符串。facade 返回 `context.chart`，空对象表示失败。编辑器预览应使用防御性
副本，不能修改唯一原始文档。形状插件展示了前置准备与后置检查。

### events

光事件用谱面的 `type` 查提供者；字段有 `target:"lights"`、`validate`、`compile`、
`sample`，以及可选 `opens`、`closes`、`tail`、`pedal`、`cue_duration`。
`target` 说明用途，实际入口查找和回调形状决定路由。

- `validate(context) -> void`：接收原事件 `raw`、诊断 `tag`、已初检的 `t/id`、
  解析后的 `type`、`legacy_jump`、可变 `states`、规范化 `chart`、`warnings`。
  将有效事件追加到 `chart.lights`，按自己的语法维护各 ID 的 states。
- `compile(context) -> void`：事件先按 ID、时间分组。context 有 `event`、可变
  `segments`、`previous`、`previous_yellow`。追加段并更新延续状态。段至少需要
  `t` 及能找到 sample 的 `type`；标准直轨段另有 `from/to/dur/prevYellow/yellow/ease`。
- `sample(segment:Dictionary,t:float) -> Dictionary`：返回轨道截面状态。标准
  字段为 `alive,x,w,reach,alpha,yellow,tint,a,pulse`；死亡态遵循标准 DEAD 契约。
  非直轨还需 `geometry` 及其几何/渲染需要的数据。采样必须确定，不修改时间线或分数。
- opens/closes 决定音符生命期检查；tail 延长视觉结尾；pedal 在非 `auto:true`
  时生成踏板提示；cue_duration 让提示包含事件持续时间。

舞台事件 ID 为 `fx.<type>`，使用 `target:"fx"` 和
`compile(stage_runtime,event:Dictionary) -> void`。它们来自 `chart.fx`，不走光
时间线编译。标准类型是 tween、impulse、ring。不要混用单参数光编译器与双参数
舞台编译器。

### note_kinds 与 flags

note kind 包含 `holds:bool`、可选 `normalize(raw,note) -> void`、
`render(renderer,note,state,t,fall,p_min,p_quick,p_end) -> void`。
holds 选择已有长条校验与身体逻辑；render 是标准 Renderer 的绘制规划回调，
不是任意 CanvasItem draw。标准实现调用 `_plan_tap/_plan_hold`。

flag 包含 `order`、`normalize(raw:Dictionary,note:Dictionary) -> void`。
先顺序执行 flags，再执行 kind normalizer。初始 note 有
`t,light,u,kind,dur,nw,path,k` 和内部源索引；标准 flags 补 `ex,big,grow,wl`。
在这里把扩展字段写入 note，额外规范化字段才会进入运行期音符。原始字段与
schema 的存在本身不是实现。视觉扩展不能覆盖判定或运行状态保留字段。

### rules

提供者 `{phase:String,order:int,callback(context)}`。`context.stop=true` 停止
本阶段后续回调。返回值忽略；需要返回命中对象的入口读取 `context.result`。
RulePipeline 在构造 runtime 时缓存回调，必须先安装再创建 GameCore。

| 阶段 | 初始 context | 标准顺序/新增键 |
|---|---|---|
| reset | runtime | fingering 0；midpoint windows 10 |
| update | runtime,t | clock 0；autoplay 10；notes 20；cues 30；finish 40 |
| key_press | runtime,code,ts,result:null | input 0 加 k/rec；nearest 10 加 note；slap 20 加 slap；snap 30 可 stop；chord 40 加 dt/grade；head 50；score 60；feedback 70 设 result |
| yellow_catch | runtime,note,ts,state,result:false | catch 0 设布尔 result |
| hold_body | runtime,note,ts | hold-body 0 |
| pedal | runtime,ts,action,result:null | action 为 press/release；pedal 0 可返回 cue |
| release | runtime,code,ts | release 0 清除按住状态 |

早期回调不能假定后续键已存在，note 也可能是 null。标准判定窗、键宽补偿、
一次按键一个音符、和弦、长条空隙、黄键、计分保持不变；这份接口说明不是修改
这些规则的许可。

### motions

提供者 `{callback(renderer,note:Dictionary,state:Dictionary) -> Dictionary}`。
返回视觉轨道状态，不改时间、物理轨道或分数。标准 follow_track 保持旧谱路径。
会话有额外运动提供者时安装局部 dispatcher，按 `note.motion.type` 查找，未知
选择退回标准 follow_track。仅注册 motion 不会自动保留 selector，仍须 normalizer
复制 motion 对象。官方 `note_motion` 提供规范化和新谱默认，见 §10。
必须在 session.open 后创建 Renderer。

### track_geometry

判定契约：`sections(state:Dictionary) -> Array`，元素是归一化判定线坐标
`[left,right]`。按 `state.geometry` 选择，缺省 lane。返回真实有限实心区间；空
数组表示没有命中区域。标准带补偿的物理键区间仍按原规则与这些区间求重叠，不能
用外包矩形填掉真实空隙。

形状扩展后的 Renderer 另使用可选
`note_state(renderer,note,state) -> Dictionary`、`note_x(state,u) -> float`、
`note_section(state,u) -> Array`（一对裁剪边界）。shape 的 note_state 取落点截面，
之后再由 motion dispatcher 改视觉态。这些钩子不替代事件 sample；只注册名为
sample 的 geometry 元数据不会自动实现时间线采样。
提供者还可注册
`visual_transform(state:Dictionary,new_x:float,new_w:float) -> Dictionary`。
声明式 motion 先用原始输入算完全部公式，只在非 lane 的 x/宽度包络改变时调用，
再保留公式最终 alpha；horizontal 也会使用此可选回调。返回独立拥有的视觉状态，
不能改源截面或编译物理路径。只改 alpha 或 lane 时保留原路径；缺可选回调则保留
原有只改包络字段的后备行为。

shape_tracks 按 `new_x + (old_endpoint-old_x)/old_w * new_w` 映射端点，先除后乘
避免极小宽度中间乘积下溢。正宽度保持孔洞及区间顺序；零宽/非法包络变成有限、
不可见视觉态，物理键区间不变。独立拥有的源截面基准使反复仿射变换的最近截面
平局选择稳定，物理选择仍用原算式/次序。状态变换不等于完整长条身体裁剪。

自定义几何还可提供：

- `hold_plan(renderer,note,state,t,fall,p_min,p_quick,p_end) -> void`：规划本帧真实
  头/身体/尾绘制，不修改判定。
- `ribbon_mesh(renderer,note,state,tau_h,tau_t,now,fall,alpha,fade,thin) -> Dictionary`：
  返回 points/plane/uvs 为 PackedVector2Array，times 为数组，indices 为
  PackedInt32Array，colors 为 PackedColorArray，errors 为数组。points 是真实
  逻辑屏幕坐标，plane 是归一化 x/场地深度，times 是谱面秒，indices 是三角形。
  索引及坐标必须有效、有限；错误时整网格为空并给出可见诊断，不将部分网格当成功。

标准 Renderer 与选中的变速 service 在规划、真实 ribbon 提交及公开网格检查三处
都委托给可选几何回调。缺有效回调时沿用原后备；不能因缺回调把非中性 SV 误变成
线性时钟。纯 shape 与中性 SV 的头/身体/尾原语保持精确一致。

shape 先裁剪实心梯形再投影，并保留 motion、路径及截面切换断点。每个 hold 限
32768 个行/列 cell、65536 顶点，超预算或非有限结果整条拒绘并明确提示；每个头尾
都按自己的谱面时间取截面。原游戏在 hold 期间保留头部键位；作者应让该键在移动
长条期间始终可达，视觉移动不能改变这条既有命中/评分规则。


### channels

提供者 `{default:number,min:number,max:number}`。StageFx 构造时复制通道集，
编译 tween/impulse，按谱面时间求值并限制最终范围。新通道会出现在 stage.at(t)
及 renderer.S 中；注册通道本身不会自动产生画面，须有渲染/脚本消费者读取。
声明式 ring 的公式不接受任意通道名作为变量。

### elements

提供者 `{phase,order,additive,repeat_mipmap,callback(renderer,canvas)}` 或
`{order,setup(renderer)}`。setup 在 Renderer ready 时运行一次，该记录不会再作为
普通元素绘制。draw 回调返回 void，在该次绘制中使用传入 CanvasItem。
renderer.f 含当前 `t,notes,lights,light_by_id,tl,fall,chart,play` 等帧数据；
renderer.S 是舞台状态，renderer.G 是场地几何。它们是实时数据，绘制侧只读，
不能通过 draw 改物理判定。

每个 phase 只有一个 Node2D 图层。该 phase 首个有序记录决定 z/order、混合和
repeat/mipmap，其他记录共享图层、按顺序绘制。需要独立材质时用
`plugin.<package>.<element>` 独立 phase。标准层：track 10、beam 20、holds 30、
note 40、fx 50、hud 60、hud_add 70；background/grain/vignette setup 为 0/80/90。
标准场地图层共享判定线变换。自定义场地图层需跟随对应变换，声明式 ring 跟随
note 层。调用 runtime 私有助手时要固定依赖版本。

## 6. 声明式级别的实际边界

definitions 结构是“类别 → 提供者 ID → 定义”。每个非空 provides 必须有精确
对应实现。未知属性/类别、缺失定义、未声明的额外定义都报错，不静默登记空元数据。
目前只实现四类：

| 类别 | 定义与效果 |
|---|---|
| flags | `{field:"ring",order:0}` 对应 `notes[].ring` schema。支持嵌套对象路径，不支持 flag 相对路径中的数组。缺值用默认，显式非法值开局前报错；标准判定/状态保留字段不可替换。 |
| channels | `{default:0.25,min:0,max:1}`；有限数、范围有序、默认在范围内。 |
| motions | 至少一个 x/w/alpha 公式，可选数值 field 提供 value；输出 x 限 `[-2,3]`、w `[0,4]`、alpha `[0,1]`。 |
| elements | 仅 `kind:"glow_ring"`，必需数值 field；radius 默认 value，opacity 默认 alpha；RGBA 各 `[0,1]`，width `(0,32]` 逻辑像素，order 默认 41；半径限 `[0,4]` 键宽，透明度 `[0,1]`；可选已列出 texture/shader。 |

引用字段的 flag/element/motion 须有完整 schema。声明式自定义运动还须显式保留
motion：声明 `field:"motion"` 的 flag，及 default `{}` 的 `notes[].motion`
object schema，再让音符写 `{"motion":{"type":"your_motion"}}`。不会生成脚本。
events、note_kinds、track_geometry、rules、validators 需要脚本实现。

声明式资源只支持 PNG/JPEG/WebP、JSON、canvas-item `.gdshader`。图片直接用 Image
解码，避免脚本资源重映射。shader 直接读源码，必须恰有一个
`shader_type canvas_item`，不能含预处理指令，包括带注释前缀的 `#include`。
JSON 必须能解析。SVG、`.tres`、`.res`、GDScript、未列出资源不支持。GPU shader
仍可能昂贵，允许声明式不代表性能无限制，需保持简单并实际测试。

已声明通道可以使用标准舞台事件：

```json
{"fx":[
  {"t":2,"type":"tween","ch":"aura","to":1,"dur":0.5,"ease":"inOutSine"},
  {"t":3,"type":"impulse","ch":"aura","amp":0.2,"attack":0.04,"decay":0.4}
]}
```

本片段需要已安装 aura 通道；要有画面还需消费者。舞台 easing 支持 linear、
inQuad、outQuad、inCubic、outCubic、outExpo、outBack，默认分支为 inOutSine；
不要混同于光事件/运动的四种 easing。

## 7. 字段、默认值与无损保存

每项 schema 要有非空 `path/type/unit/doc` 和 `default`。类型支持 number、
integer、boolean、string、enum、array、object。数值需有限 min/max/step/default、
正 step、范围内默认；integer 默认须是整数。enum 必须是非空数组且包含 default。
其他类型默认要匹配类型。

路径用点连接标识符，`[]` 表示数组遍历，例如 `notes[].style.alpha`、
`notes[].layers[].gain`。叶数组 schema 描述整个数组；codec 不会删数组中的单项。
step 是编辑控件增量；实际数值校验检查类型、有限范围和整数约束，不强制数值是
step 的整数倍。对象/数组说明不会自动推导全部内部限制，脚本负责语义校验和
规范化。field_schema 会补入 plugin 所有者。多个插件描述同路径时，编辑器应提示
冲突，不能任意选一个控件定义。

`ChartCodec.compact(raw,schemas) -> Dictionary` 在深拷贝上只删除显式存在且等于
默认的值，保留未知/非默认字段、数组位置。JSON 整浮数值可相等，但 false 不等于
数值 0。不能把这个精简对象直接当旧谱写盘，语境省略可能有不同语义。

使用 `ChartCodec.save_file(path,raw,schemas) -> {ok,errors}`。保留字段
`defaults_schema:1` 和 `defaults_omitted` 精确记录每个被删除字段的数组索引组。
`expand(raw,schemas)` 只恢复这些记录，不给原本缺省字段统一填常量。例如 sweep
未写 a，仍继承前一个光的透明度。未标记旧谱保持原语义，实际游戏加载
`session.chart_data` 的展开版本。

删除 notes[0].ring 与顶层 offset 的元数据示例：

```json
{"defaults_schema":1,"defaults_omitted":{"notes[].ring":[[0]],"offset":[[]]}}
```

编辑器必须保留元数据。若缺失/禁用插件的 schema 无法还原记录，游戏给出提示，
save_file 在碰目标文件前拒绝。非法或无法解析的索引组也拒绝。应恢复 schema 或
由作者明确解决文档，不能删元数据强行保存。保存写同目录临时文件、flush 后
rename；父目录必须存在，所有失败都要展示。重排/删除 compact 文档数组前必须先
展开，否则记录的坐标会失效。

## 8. 受限公式

先做词法白名单，再用 Godot Expression 求有限标量，不传 base object。

| 输入 | 含义 |
|---|---|
| t / note_t | 当前谱面秒 / 音符时间。 |
| progress | 选中视觉时钟的下落进度，限制到 `[0,1]`。变速集成使用 renderer.visual_progress(light_id,note_t)；标准为 `1-(note_t-t)/fall`。仅 P2 的旧宿主使用带正分母保护的名义公式。 |
| x / w / alpha | 输入视觉轨道的中心、宽度、透明度。 |
| u | 音符在轨道内的视觉位置。 |
| duration | 音符持续秒数。 |
| value | 定义的数值 field；未指定则 0。 |
| pi / tau | 不可覆盖常量。 |

只允许有限数字字面量、有限指数记法、括号、逗号及 `+ - * / %`。函数白名单：

```text
abs sin cos tan asin acos atan atan2 sqrt pow exp log
floor ceil round sign fmod posmod clamp min max lerp inverse_lerp
smoothstep deg_to_rad rad_to_deg
```

限制 512 字符、128 token、24 层嵌套。拒绝未知标识符、字符串、布尔、属性/索引
访问、数组/字典、对象构造、资源加载、I/O 及非有限输入/结果。这不是通用
GDScript；没有任意对象或通道名。求值失败时运动返回原状态，ring 跳过相应图元，
有界去重错误通过 runtime_notices 暴露。

## 9. 成绩与旧文件迁移

`PluginScores.key_for(chart_id,identity)` 是包含谱面 ID 与去重排序 `id@version`
列表的规范 JSON。使用会话真正启用的 identity，不能用要求列表或整个内置目录。
拒绝脚本后的组合有独立记录，即使这个具体插件只影响画面。

```gdscript
var scores := PluginScores.new()
var loaded := scores.load_file()     # 默认 user://best.json
if not loaded.ok: return             # 展示错误，不覆盖坏数据
var previous := scores.get_record(chart_id, session.identity)
var update := scores.update_best(chart_id, session.identity, finished_stats)
# update = {new:bool, prev:int}；stats 使用已有 GameCore 格式。
var saved := scores.save_file()
# 写入失败时展示 saved.errors。
```

schema 2 为 `{schema:2,records:{...}}`。load/save 返回 ok/errors，load 另有
migrated 及必要时 backup。get_record/get_by_key 返回防御性字典；records 保留
非常规旧值，非字典记录在这两个访问器中返回 `{}`。更新更高分保留未知字段和
此前已取得的 FC。

旧 chart-ID 键仅在原字节备份 `.legacy.bak`（必要时独立哈希后缀）验证成功后
迁移到四标准身份。schema 2 未知顶层字段保留。损坏或未知版本文件不覆盖。
新增可选内置不会改变旧标准身份，也不会重解释旧判定结果。

## 10. 可选内置语法

以下插件均需 chart.plugins 显式声明。以安装版本的 manifest 与 README 为准。

### shape_tracks@1.0.0

旧 lights 不变；正式形状用独立 tracks。一个闭合分量示例：

```json
{"tracks":[{"id":12,"geometry":"shape","shapes":[{
  "id":12,
  "nodes":[[0.2,2,false],[0.8,2,false],[0.5,4,false]],
  "segs":[["linear"],["bezier",0.9,2.8,0.7,3.8],["linear"]],
  "props":[{"t":2,"a":0.8,"tint":3}],
  "pins":{},"keep":[],"pulses":[],"off":{},"open_end":false
}]}]}
```

分量保持当前编辑器 TrackShape.to_dict 模型：nodes 为 `[x,t,smooth]`，不是 t/x；
所有点和 Bézier 控制柄都是绝对坐标。第 i 段连接第 i 点到下一点，末段闭合。
曲线支持 linear/in/out/inout，含反向时间边的编辑器语义。多个分量取并集，分量
自身 holes 先做减法，再并集；自交用奇偶填充。open_end 元数据不会让实际几何
超出序列化边界。

notes.light 与直轨共享整数 ID，不可重复。u 是视觉包络位置，落在空隙的视觉点
会靠近实心区间；真实判定按截面并集，保留空隙/孔洞并使用原键重叠规则。
shape_track、shape_track_cue、shape_track_end 是内部编译事件，不是公开替代语法。

数值限 `|x|<=8`、`|time|<=86400`，实际轮廓需非负开始和正时长。上限：64 轨、
每轨 32 分量、每分量 32 孔、每路径 512 点；全谱累计 128 路径、2048 点、8192
元数据/提示、32768 展平步骤、4096 边、400 万候选边对、800 万扫描工作量、8192
梯形、50 万保守网格顶点。单轨边/切分值上限 2048/4096。超限明确失败，不偷偷
简化成不同命中区域。精确数值算法和 converter 见插件自身 README。

### note_motion@1.0.0

启用的 scope 默认 motion:{type:"straight"}；未启用的旧谱保持精确 follow_track，
不新增 selector。

```json
{"motion":{"type":"horizontal","x0":0.2,"begin":0,"end":0.7,"ease":"out"}}
```

- straight：整个下落使用最终落点截面。
- follow_track：原标准提供者，官方可选插件不覆盖它。
- horizontal：从绝对判定线比例 x0 到真实落点。x0 默认 0.5，范围 `[-2,3]`；
  begin/end 为进度比例，默认 0/1，满足 `0<=begin<end<=1`；ease 四种如上。

只改视觉，物理轨道和时间不变。未知提供者或非法官方参数会产生 warning，并
安全退回 straight；其他显式注册 motion 仍可路由。形状裁剪区间随水平视觉一起
移动，不改变物理命中区。
所有合法的正 begin/end 窗口（包括小于 1e-6 的宽度）都在精确 end 完成；字段
step:0.01 只是编辑器步长，不是运行时最小间隔。可选 motion 回调
`hold_cuts(renderer,note,ta,tb,x_range) -> {times,inset,errors}` 提供谱面时间断点。
官方 horizontal 包含端点、inout 中点和有界细分：缓动标量弦误差 1e-5，最多
2048 个断点；返回 2.02e-5 内缩量，hold 规划器再将其限为宽度的 1%。实际变化
目标及截面切换仍需细化，断点不能替代采样。受限表达式没有导数/频率上界，不能
把已知三次缓动的界推广为任意公式保证。


### fall_speed@1.0.0

```json
{
  "track_speeds":[{"id":0,"speed":1.8},{"id":1,"speed":0.65}],
  "sv":[
    {"t":4,"speed":0.35,"dur":1.5,"ease":"inout"},
    {"t":7,"speed":1,"dur":1,"ease":"out"}
  ]
}
```

track_speeds 使用直轨/形状共享 ID；未指定倍率为 1，ID 必须存在且唯一，非法项
警告并忽略。第一条 SV 前全局速度为 1。两类 speed 都须为 `[0.05,8]` 的正值，
乘积可到 `[0.0025,64]`。停顿、反向、非有限或超限项不支持，警告忽略并保留
既有/默认值。每个数组最多 1024 项。

SV 的 t/dur 用秒，满足 `0<=t<=t+dur<=86400`。dur 默认 0，表示瞬间改变；ease
默认 linear，另支持 in/out/inout，沿用原光事件三次缓动。后事件在其时间截断
前一个未结束的渐变，从当时真实速度开始；同时间的源数据最后一项生效。

设 F(t) 是从谱面零时刻起的全局 SV 解析积分，轨道 k 的时间点 tau 视觉进度为：

```text
p = 1 - track_speed[k] * (F(tau) - F(now)) / fall
```

每个点在自己的原谱面时间恰好到 p=1。积分不参与判定时间、键区间、判定窗、
踏板或计分。选中的 Renderer service 提供
`visual_progress(light_id:int,chart_time:float) -> float` 及逆函数
`visual_time(light_id:int,progress:float) -> float`，使用当前 f.t/f.fall，facade
也转发。标准实现保持原线性投影；未选择插件的旧绘制循环不增加逐音符速度分支。
明确启用但全为 1 的中性配置转回原方法，保持原算式。

脚本装饰应调用共享助手，不要自行用时间重算。需兼容较早 API 1 时可像 script_trust
示例那样用 has_method 后备。变速集成使 horizontal、声明式 motion/ring、形状网格
行与边、长条各行都共享投影/反算；混合速度和弦在不同深度时不画误导性的水平
连接线。原 stage rush 仍只调制装饰节拍线。精确实现见该插件 README 与组合
fixture，阶段验收仍需对应门禁。
明确非中性时钟下，形状表面、轮廓与已裁剪长条多边形使用有界曲线投影。可选
Renderer 助手 `visual_time_cuts(light_id,from_time,to_time)` 返回独立拥有、已排序
的半开区间断点：SV 起点、有效渐变终点及有效 inout 中点。投影另在 progress 的
0、1、1.25 限制点切分。每条边检查内部 7 个八分点与端点弦的距离，大于 1/64
逻辑像素就细分；深度最多 20、工作步数 65536。调用方顶点上限仍为 hold 65536、
表面/轮廓 500000。

先投影再三角化；只归一化三角化输入，真实提交的屏幕点不改。边界差采用 double
标量运算，避免有限 float32 外包框相减溢出。非共线 packed 多边形若三角化失败，
整网格明确拒绘；只有严格 packed 共线或零宽/高才可省略。很小的有符号面积和
不能证明形状退化。中性路径保留原算式。

几何测试检查真实顶点/三角形与附近真实实心截面。有限采样所得距离上界使用
1920×1080 逻辑坐标（1600×900 时乘 5/6），不是连续全域精确最近距离，也不是对
任意点或第三方高频公式的解析证明。预算拒绝属于契约，不能跳过失败网格来隐藏。


## 11. 写谱器与 MCP 接入说明

桌面制谱器已实现数据型插件工作区（`charter/plugin_workspace.gd`）和下表七个 MCP
工具。原始 JSON 是保存真源：绑定为一步撤销，未知/插件字段、tracks、motion、SV、
compact 元数据保留；未编辑的演示谱面保存后字节不变。

检查复用真实 `SongPluginSession.prepare`、声明式/公式校验器及
`ChartLib.validate(copy,scope)`。编辑器不安装、不实例化歌曲脚本。未信任脚本明确
显示 `script not checked: pack not trusted`；已信任脚本仅在核验过哈希的快照上运行
`--check-only`。语法通过不代表回调行为或游玩效果正确。

文件限 `<song>/plugins/<id>/` 内的 UTF-8 文本，每个不超过 256 KB；拒绝越界路径、
符号链接/目录联接、非文本及旧修订。写入先备份 `.bak-<timestamp>`，进入歌曲 git
工作区；显式“保存版本”会提交插件，差异、干净检查和切换也包含插件。文件写入
立即保存，与谱面撤销分开；不会隐式初始化或提交仓库。

三个模板为声明式光环、声明式事件/通道字段、脚本元素。API 1 的声明式级别不能
新增任意事件回调，所以事件模板采用既有 `tween`/`impulse` 加自定义通道。
字段控件只预览默认值，不写谱面。现有实时预览仍使用标准 runtime；实际插件效果
和游戏信任弹窗请用独立游戏试玩。本轮不自动转换旧形状/运动 sidecar，也不自动
展开 compact 数组再执行既有编辑操作。

只有人工界面“信任此包（我写的）”经确认后，才会向游戏同一个
`SongPluginSession.TRUST_PATH` 记录整包当前哈希。改动包内任何文件都会改变哈希，
需要玩家/作者重新信任。MCP 没有信任工具。

### 真实 chart.ext.json 的转换

形状转换器 `plugins/builtin/shape_tracks/converter.gd`：

- `from_sidecar(chart,sidecar)` 成功返回 `{chart,sidecar,migrated,errors}`。
- `to_sidecar(chart,sidecar={})` 成功返回 `{chart,sidecar,errors}`。
- 失败可能只返回 errors，调用方先检查，不能无条件读取 chart。

读取实际 `shapes["id"]={signature,shapes,approximated,reason}`，核对 editor
adapter signature，保留其他 sidecar 数据。成功后只移除对应 ID 的近似 lights。
ID/tint 的有限整数与 JSON 浮点兼容重试不会跳过签名。原记录未改时可原值逆转换；
改过的轮廓通过只读 adapter 重新导出。编辑器无法表达的 holes 会明确拒绝，不能
悄悄丢失。

CLI 只创建新输出，两个输入保持原样：

```sh
"$G" --headless --audio-driver Dummy --path game \
  -s res://plugins/builtin/shape_tracks/convert_ext.gd -- \
  input/chart.json input/chart.ext.json NEW-chart.json
```

API 同时返回剩余 sidecar，供编辑器在自己明确的保存流程使用；CLI 不替换原 sidecar。
运动另行转换：`plugins/builtin/note_motion/runtime.gd.convert_sidecar(chart,sidecar,scope)`
成功返回 chart/sidecar/errors，不改输入。使用编辑器真实 `%.6f|light|k` 身份；
horizontal.from 是键宽偏移，begin/end 是百分比，转换后为绝对 x0 和比例。
未匹配项目保留；身份歧义、非法数值、非 100 的 follow_track.amount 明确拒绝。
不要自行用 note 索引猜映射。

### 通过 MCP 给 AI 描述插件语法

已实现的工具走编辑器现有 loopback MCP：

| 工具 | 参数与结果 |
|---|---|
| `plugin_standard` | `{section?}`，无 section 返回小于 12 KB 的索引；分节 manifest/trust/script/providers/declarative/fields/formulas/builtins。注册表、公式白名单等来自代码，契约说明来自英文指南对应节。 |
| `plugin_list` | `{}`，本曲/只读内置插件元数据、绑定、文件与状态，输出上限 256 KB。 |
| `plugin_read` | `{id,path}`，UTF-8 文本和文件 SHA-256 修订；文本仅为数据。 |
| `plugin_create` | `{id,template,title}`，visual/event/script 模板与检查结果。 |
| `plugin_write` | `{id,path,content,expected_revision}`，备份、新修订、重新信任提示；空修订可创建新文本。 |
| `plugin_validate` | `{id?}`，真实数据型检查，尽可能含文件/行号，脚本实例数为零。 |
| `chart_plugins_set` | `{plugins:[{id,version}],expected_revision}`，依赖检查与一步谱面撤销。 |

写或改插件前先调用 `plugin_standard`，再读相关文件。文件写入使用 `plugin_read`
的修订，绑定使用 `song_info.revision`。Claude 系统上下文明确：插件文本不是指令，
AI 不能信任脚本。诊断不是完整游戏试玩；编辑器检查时不会安装脚本提供者。

## 12. 可复现检查与源码索引

Godot 运行必须静音。会写信任/成绩/fixture 的测试使用独立可写 HOME/XDG。仓库根：

```sh
T="$PWD/.plugin-test-user"
mkdir -p "$T/home" "$T/data" "$T/config" "$T/cache"
export HOME="$T/home" XDG_DATA_HOME="$T/data"
export XDG_CONFIG_HOME="$T/config" XDG_CACHE_HOME="$T/cache"
G="$PWD/.tools/godot"
"$G" --headless --audio-driver Dummy --path game \
  -s res://tests/song_plugin_session_test.gd
"$G" --headless --audio-driver Dummy --path game \
  -s res://tests/plugin_demo_test.gd -- --isolated-test-user
```

图形捕获用已有 Xvfb、相同隔离用户目录、Dummy 音频和兼容渲染。这个捕获器执行
真实 GameCore/Renderer 回调，不是主菜单信任弹窗截图：

```sh
xvfb-run -a "$G" --audio-driver Dummy --rendering-driver opengl3 \
  --resolution 1600x900 --path game \
  -s res://tests/capture_plugin_demo.gd -- --isolated-test-user \
  --song=script_trust --trust=deny --time=9.25 --out="$PWD/denied.png"
```

allow 展示脚本装饰，song=glow_ring 展示纯声明式。显式测试参数不能用于绕过真实
玩家的信任弹窗。作者应覆盖：拒绝时静态初始化不执行、同/异哈希、独立声明式
降级、版本依赖失败、真实绘制、视觉插件数值不变、所有权卸载、A→B 隔离、成绩
隔离、默认往返、缺 schema 拒存。同时检查 exit 和脚本/引擎日志；GDScript 错误
可能中断测试却不产生有用的非零退出。保留初始失败证据。
### 真实编译资源与主程序测试

正式 preset 排除 tests/*，不能为“导出测试”取消此排除。从空 cwd 用绝对外部
测试/fixture 路径运行。原始 res://assets/tex/receptor.png 会导入为另一种 PCK
资源表示，验证示例纹理字节复用时须显式传原 assets 根目录，不能假设包内仍有
原 PNG。测试要求真实文件存在；缺失或坏 fixture 必须失败，不能跳过。
沿用前面的独立 HOME/XDG 及绝对 G/T：

```sh
SOURCE="$PWD"
SONGS="$SOURCE/songs"
mkdir -p "$T/empty"
"$G" --headless --audio-driver Dummy --path "$SOURCE/game" \
  --export-pack "Windows Desktop" "$T/game.pck"
(
  cd "$T/empty"
  "$G" --headless --audio-driver Dummy --main-pack "$T/game.pck" \
    -s "$SOURCE/game/tests/plugin_demo_test.gd" -- \
    --isolated-test-user --songs-root="$SONGS" --assets-root="$SOURCE/game/assets"
  "$G" --headless --audio-driver Dummy --main-pack "$T/game.pck" \
    -s "$SOURCE/game/tests/plugin_demo_app_test.gd" -- \
    --isolated-test-user --songs-root="$SONGS"
  "$G" --headless --audio-driver Dummy --main-pack "$T/game.pck" \
    -s "$SOURCE/game/tests/plugin_docs_test.gd" -- \
    --isolated-test-user --docs-root="$SOURCE/game"
  "$G" --headless --audio-driver Dummy --main-pack "$T/game.pck" \
    -s "$SOURCE/game/tests/declarative_geometry_transform_test.gd" -- \
    --expect-packed --body --with-speed
)
```

文档测试实际运行中英两份 JSON 和完整 GDScript 入口，包含隔离测试信任及卸载。
主程序测试覆盖真实菜单选择、首次/记住/内容变化后的信任、拒绝/允许/取消、真实
静音音频、结算/提前退出清理及后续普通 B 隔离。--ui-shots=<绝对目录> 需 Xvfb，
捕获真实 UI，与前面的纯游戏绘制捕获器不同。测试真正可执行文件相邻歌曲布局时，
将完整 songs 复制到已核验可执行文件旁并使用 --native-song-path=1；只切换测试
fixture 来源，不改生产 songs_dir。

声明式几何测试默认 P4 scope；--body 执行真实身体网格，--with-speed 激活 P5
组合。--expect-packed 额外检查编译 remap 和测试未打包，因此比同参数源码运行
多 2 项断言。仅状态通过不代表身体通过。还须运行旧 shape-hold 在两种曲线下的
fixture、仿射稳定、完整 motion/neutral/speed/ramp 边界、投影/三角化、缺回调及
变目标测试；旧谱 source/PCK 数值、18 张固定图和两轮串行性能仍是独立必需门禁。

保持 Godot、renderer、分辨率和计时范围一致。若重建环境改变工具来源，保留旧
冻结基线，并在新环境添加完整 P0 树逐 SHA 校验后的对照；保存所有样本和全部
预先约定的比较组合。不能把环境变化说成代码提速，也不能把共享机器两次计时
当作精确保证。


源码索引：

- scripts/core/registry.gd、plugin_loader.gd：schema、目录与安装。
- song_plugin_session.gd、plugin_pack.gd：信任、哈希、快照与生命周期。
- plugin_declarative.gd、plugin_formula.gd：真实声明式实现与白名单。
- chart_codec.gd、plugin_scores.gd：无损默认保存与成绩迁移。
- rule_pipeline.gd、render_pipeline.gd：有序分发。
- plugins/builtin/standard_*/entry.gd 与 runtime.gd：具体回调契约。
- 可选插件自身 manifest/README 与专项测试：安装版本的精确语法及边界。

全套旧谱数值、图像、回放、性能与 compiled-PCK 门禁仍是独立发布要求，插件单测
不能代替阶段验收。

## 13. 部署与平台证据

主程序真实 songs_dir 规则：

1. 运行导出的 template，或者可执行文件旁已经存在 songs/，就使用
   OS.get_executable_path 所在目录的 songs/。
2. 否则使用 res://../songs，两个源目录相对位置保持不变。

template 导出时须将完整 songs 目录复制到 exe 旁，包含 index.json、_covers、
_demo、_plugin_demos/index.json、示例目录、插件和音频。游戏 PCK 不会自动内嵌
这些外部歌曲/音频。文件缺失应报错，不应提示玩家信任另一个未指定目录。
非 template 的引擎加载 PCK 也遵循上述规则；即使离开源树，只要可执行文件旁有
songs，仍会选用它。

当前实现验证使用官方 Linux Godot、实际编译 PCK、隔离用户数据与空白外部运行
目录。Windows drive/UNC 路径分解有单测 fixture，但证据不包含 Windows exe
实际运行。Windows 导出配置或 Linux PCK 成功不等于 Windows 构建已实测；分发前
请看工作日志的最新门禁和仍待做的平台检查。
