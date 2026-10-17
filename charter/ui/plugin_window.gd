extends Window
## Embedded floating window uses the editor's theme and proportional canvas scale.
const Workspace=preload("res://plugin_workspace.gd")
const Standard=preload("res://plugin_standard.gd")
const Tokens=preload("res://theme.gd")
const U=preload("res://ui/ui_util.gd")
const W=preload("res://ui/widgets.gd")
var app
var workspace=Workspace.new()
var catalog=[]
var selected=""
var buffers={}
var current_file=""
var changing=false
var list=VBoxContainer.new()
var tabs=TabBar.new()
var code=CodeEdit.new()
var heading=Label.new()
var notice=Label.new()
var diagnostics=ItemList.new()
var fields=VBoxContainer.new()
var standard=RichTextLabel.new()
var standard_source=""
var standard_match=-1
var detail_tabs=TabBar.new()
var hidden_overlays=[]
var drag_origin=Vector2i.ZERO
var drag_window=Vector2i.ZERO
var dragging=false
var resizing=false
const DIAGNOSTIC_PHRASES={
	"Manifest must be an object":"清单必须是对象", "Manifest missing ":"清单缺少字段 ", "Invalid plugin id":"插件 id 无效", "Version must be major.minor.patch":"版本必须符合 major.minor.patch 格式", "Unsupported plugin API":"不支持的插件 API", "Unknown plugin tier":"未知的插件层级", "Invalid provides category":"无效的 provides 类别", "Invalid or duplicate provider id":"提供者 id 无效或重复", "Field metadata must be an object":"字段元数据必须是对象", "Field missing ":"字段说明缺少 ", "Unsupported field type":"不支持的字段类型", "Field requires nonempty ":"字段说明必须填写非空的 ", "Duplicate field path":"字段路径重复", "Numeric field missing finite ":"数值字段缺少有限数值的 ", "Field default/range mismatch":"字段默认值与范围不匹配", "Field step must be positive":"字段步长必须为正数", "Integer field requires an integral default":"整数字段的默认值必须为整数", "Enum field requires values":"枚举字段必须提供可选值", "Enum default must be one of its values":"枚举默认值必须属于可选值", "Wrong field default type":"字段默认值类型错误", "Unsafe or unsupported asset":"资源路径不安全或类型不受支持", "Declarative plugins cannot have a script entry":"声明式插件不能包含脚本入口", "Script plugin requires an entry":"脚本插件必须提供入口", "Unsafe script entry":"脚本入口路径不安全", "Dependency requires id and version":"依赖必须包含 id 与 version", "Invalid dependency id/version":"依赖 id 或 version 无效", "Unsupported dependency version range":"不支持的依赖版本范围", "Duplicate plugin id":"插件 id 重复", "Dependency cycle at ":"循环依赖位于 ", "Dependency version mismatch":"依赖版本不匹配", "Missing dependency ":"缺少依赖 ", " for ":"，来源 ",
	"must be an array":"必须是数组", "must be an object":"必须是对象", "Invalid JSON object":"JSON 对象无效", "Cannot read JSON":"无法读取 JSON", "Invalid UNC pack path":"歌曲包 UNC 路径无效", "Song pack folder must be absolute":"歌曲包必须使用绝对路径", "Pack folder traverses its filesystem root":"歌曲包路径越过文件系统根目录", "Cannot inspect pack folder":"无法检查歌曲包目录", "Symlink is not allowed in song pack path":"歌曲包路径不允许符号链接", "Symlink is not allowed in song pack":"歌曲包不允许符号链接", "Missing song pack folder":"找不到歌曲包目录", "Unsafe pack path":"歌曲包路径不安全", "Missing pack folder":"找不到歌曲包目录", "Missing pack file":"找不到歌曲包文件", "Cannot hash pack file":"无法计算歌曲包文件哈希", "Pack changed or failed while hashing":"计算哈希时歌曲包已改变或读取失败", "Pack changed while hashing":"计算哈希时歌曲包已改变", "Pack exceeds safe file inspection limits":"歌曲包超出安全文件检查上限", "Cannot inspect pack directory":"无法检查歌曲包目录", "Cannot list pack directory":"无法列出歌曲包目录", "Unsafe pack filename":"歌曲包文件名不安全", "Cannot create trusted plugin snapshot":"无法创建可信插件快照", "Cannot copy trusted plugin snapshot":"无法复制可信插件快照", "Formula must be a finite number or scalar expression":"公式必须是有限数值或标量表达式", "Invalid formula":"公式无效", "Chart plugins must be an array of {id, version}":"谱面 plugins 必须是包含 id、version 对象的数组", "Duplicate chart plugin requirement":"谱面插件要求重复", "Plugin dependency cycle":"插件存在循环依赖", "Missing or unsafe plugin ":"插件缺失或路径不安全：", " required by ":"，依赖来源：", "Plugin folder/id mismatch: expected ":"插件目录与 id 不一致：应为 ", ", found ":"，实际为 ", "Plugin version mismatch":"插件版本不匹配", " requires ":" 需要 ", "Unsupported declarative category":"不支持的声明式类别", "Unsupported declarative asset type":"不支持的声明式资源类型", "Invalid declarative JSON asset":"声明式 JSON 资源无效", "numeric note field is required":"必须提供数值音符字段", "field requires a numeric notes[]. schema":"字段需要数值类型的 notes[] 说明", " violates the declared ":" 不符合已声明的 ", " field schema":" 字段说明", "Invalid ":"无效的 ", "Unsupported ":"不支持的 "
}
var standard_search=LineEdit.new()
var details=TabContainer.new()
var details_toggle=Button.new()
var file_names=[]
var bind_button=Button.new()
var trust_button=Button.new()
var pending_conflict={}
var conflict=ConfirmationDialog.new()
var trust=ConfirmationDialog.new()
var create_dialog=ConfirmationDialog.new()
var id_input=LineEdit.new()
var title_input=LineEdit.new()
var template_input=OptionButton.new()
var diagnostics_data=[]
var background=ColorRect.new()

func _ready() -> void:
	workspace.doc=app.doc
	title="脚本 · 插件工房"; min_size=Vector2i(1050,600); size=Vector2i(1400,760)
	transient=true; exclusive=false; visible=false; borderless=true
	close_requested.connect(close)
	size_changed.connect(remember)
	background.color=Tokens.c("s1"); background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); background.mouse_filter=Control.MOUSE_FILTER_IGNORE; add_child(background)
	var root=MarginContainer.new(); root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]: root.add_theme_constant_override("margin_"+side,16)
	add_child(root)
	root.draw.connect(func(): root.draw_style_box(Tokens.box(Tokens.c("s1"),10,Tokens.c("border_strong"),1,1),Rect2(Vector2.ZERO,root.size)))
	var outer=VBoxContainer.new(); outer.add_theme_constant_override("separation",10); root.add_child(outer)
	var caption=HBoxContainer.new(); outer.add_child(caption)
	var caption_text=Label.new(); caption_text.text=title; U.bounded_label(caption_text); caption_text.theme_type_variation="Title"; caption_text.size_flags_horizontal=Control.SIZE_EXPAND_FILL; caption.add_child(caption_text)
	caption_text.mouse_filter=Control.MOUSE_FILTER_STOP; caption_text.mouse_default_cursor_shape=Control.CURSOR_MOVE; caption_text.gui_input.connect(frame_input.bind(false))
	button(caption,"关闭 ✕",close)
	var toolbar=HBoxContainer.new(); toolbar.add_theme_constant_override("separation",8); outer.add_child(toolbar)
	heading.text="脚本"; heading.theme_type_variation="Title"; heading.clip_text=true; heading.custom_minimum_size.y=30; heading.max_lines_visible=1; heading.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL; toolbar.add_child(heading)
	button(toolbar,"检查",validate_selected)
	bind_button=button(toolbar,"绑定",toggle_binding); bind_button.clip_text=true; bind_button.custom_minimum_size.x=110
	trust_button=button(toolbar,"信任此包（我写的）",confirm_trust); trust_button.clip_text=true; trust_button.custom_minimum_size.x=180
	button(toolbar,"试玩",play_song)
	var ask=MenuButton.new(); ask.text="问 Agent"; ask.flat=false; ask.custom_minimum_size.y=36
	for state in ["normal","hover","pressed","focus"]: ask.add_theme_stylebox_override(state,app.theme.get_stylebox(state,"Button"))
	for text in ["解释这个插件","按规范检查","给它加一个字段","写一个新插件…"]: ask.get_popup().add_item(text)
	ask.get_popup().index_pressed.connect(ask_claude); toolbar.add_child(ask)
	U.bounded_label(notice); notice.custom_minimum_size.y=40; notice.max_lines_visible=2; notice.theme_type_variation="Muted"; notice.text="插件文本仅作为数据。修改内容会使脚本包需要重新信任。"; outer.add_child(notice)
	var split=HSplitContainer.new(); split.size_flags_vertical=Control.SIZE_EXPAND_FILL; split.split_offset=275; outer.add_child(split)
	var left=VBoxContainer.new(); left.custom_minimum_size.x=245; split.add_child(left)
	var new_button=W.IconButton.new("plus","从模板新建插件","新建"); new_button.custom_minimum_size.y=36; new_button.pressed.connect(func(): create_dialog.popup_centered(Vector2i(480,260))); left.add_child(new_button)
	var sc=ScrollContainer.new(); sc.size_flags_vertical=Control.SIZE_EXPAND_FILL; sc.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; left.add_child(sc)
	list.size_flags_horizontal=Control.SIZE_EXPAND_FILL; sc.add_child(list)
	var centre=VBoxContainer.new(); centre.custom_minimum_size.x=450; split.add_child(centre)
	tabs.clip_tabs=true; tabs.max_tab_width=180; centre.add_child(tabs); tabs.tab_changed.connect(select_file)
	code.size_flags_vertical=Control.SIZE_EXPAND_FILL; code.gutters_draw_line_numbers=true; code.auto_brace_completion_enabled=true; code.add_theme_font_size_override("font_size",14); code.add_theme_font_override("font",Tokens.font("mono")); centre.add_child(code)
	code.text_changed.connect(changed_text)
	var detail_header=HBoxContainer.new(); centre.add_child(detail_header)
	detail_tabs.size_flags_horizontal=Control.SIZE_EXPAND_FILL; detail_header.add_child(detail_tabs)
	for label in ["检查","字段","规范"]: detail_tabs.add_tab(label)
	detail_tabs.tab_clicked.connect(func(index): details.current_tab=index; details_toggle.button_pressed=true)
	details_toggle.text="▸"; details_toggle.tooltip_text="展开或收起检查、字段与规范"; details_toggle.toggle_mode=true; details_toggle.custom_minimum_size=Vector2(36,32)
	details_toggle.toggled.connect(func(on): details.visible=on; details_toggle.text="▾" if on else "▸"; app.panes["scripts_details"]=on; app.save_panes())
	detail_header.add_child(details_toggle); details.tabs_visible=false
	details.tab_changed.connect(func(index): detail_tabs.current_tab=index)
	details.size_flags_vertical=Control.SIZE_FILL; details.custom_minimum_size.y=225; centre.add_child(details)
	diagnostics.name="检查"; diagnostics.item_selected.connect(jump_diagnostic); details.add_child(diagnostics)
	var fsc=ScrollContainer.new(); fsc.name="字段"; fsc.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; details.add_child(fsc); fields.size_flags_horizontal=Control.SIZE_EXPAND_FILL; fsc.add_child(fields)
	var spec=VBoxContainer.new(); spec.name="规范"; details.add_child(spec)
	standard_search.placeholder_text="搜索插件规范（Enter 查找下一处）"; standard_search.text_submitted.connect(search_standard); spec.add_child(standard_search)
	standard.bbcode_enabled=true; standard.selection_enabled=true; standard.size_flags_vertical=Control.SIZE_EXPAND_FILL; standard.add_theme_font_size_override("normal_font_size",14); spec.add_child(standard)
	build_standard()
	var grip=Label.new(); grip.text="◢"; grip.tooltip_text="拖动调整窗口大小"; grip.mouse_filter=Control.MOUSE_FILTER_STOP; grip.mouse_default_cursor_shape=Control.CURSOR_FDIAGSIZE; grip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT); grip.position=Vector2(-20,-20); add_child(grip); grip.gui_input.connect(frame_input.bind(true))
	add_child(conflict); conflict.title="文件已被外部修改"; conflict.dialog_text="重新载入会放弃本地未保存文本。覆盖会以刚读取的磁盘修订号再次保存并保留备份。"; conflict.ok_button_text="覆盖"; conflict.cancel_button_text="取消"
	conflict.add_button("重新载入",true,"reload"); conflict.confirmed.connect(overwrite); conflict.custom_action.connect(func(_action): reload_conflict(); conflict.hide())
	add_child(trust); trust.title="信任此包（我写的）"; trust.ok_button_text="信任当前内容"; trust.dialog_text="脚本拥有与游戏相同的文件和系统权限。仅在你编写或检查了整个歌曲包时继续。\n信任按整包当前内容哈希记录；再改脚本或其他文件后，游戏会重新询问。AI 无法执行此操作。"
	trust.confirmed.connect(func(): var result=workspace.author_trust(); notice.text="已信任当前歌曲包；修改内容后需重新信任。" if result.trusted else JSON.stringify(result); refresh())
	build_create_dialog()
	app.doc.changed.connect(document_changed)
	details.visible=bool(app.panes.get("scripts_details",false)); details_toggle.button_pressed=details.visible
	refresh()

func button(parent: Node, text: String, callback: Callable) -> Button:
	var b=Button.new(); b.text=text; b.custom_minimum_size.y=36; b.pressed.connect(callback); parent.add_child(b); return b

func show_workspace() -> void:
	apply_editor_theme()
	var saved=app.panes.get("scripts_rect",[])
	if saved is Array and saved.size()==4:
		size=Vector2i(clampi(saved[2],1050,1550),clampi(saved[3],600,850)); position=Vector2i(maxi(0,saved[0]),maxi(0,saved[1]))
	else: position=Vector2i(100,80)
	var bounds=app.get_viewport_rect().size
	size=Vector2i(minf(size.x,bounds.x-32),minf(size.y,bounds.y-48))
	position=Vector2i(clampi(position.x,8,maxi(8,int(bounds.x)-size.x-8)),clampi(position.y,32,maxi(32,int(bounds.y)-size.y-8)))
	hidden_overlays.clear()
	for overlay in [app.popover,app.sheet,app.hint_card]:
		if overlay!=null and overlay.visible: hidden_overlays.append(overlay); overlay.hide()
	visible=true; app.panes["scripts"]=true; app.scripts_b.active=true; refresh(); remember()

func apply_editor_theme() -> void:
	theme=app.theme.duplicate(); background.color=Tokens.c("s1")
	theme.set_stylebox("embedded_border","Window",Tokens.box(Tokens.c("s1"),10,Tokens.c("border_strong"),8,8))
	theme.set_stylebox("embedded_unfocused_border","Window",Tokens.box(Tokens.c("s1"),10,Tokens.c("border"),8,8))
	standard.add_theme_color_override("font_readonly_color",Tokens.c("text"))

func remember() -> void:
	if not visible or app==null: return
	app.panes["scripts_rect"]=[position.x,position.y,size.x,size.y]; app.save_panes()

func _process(_dt: float) -> void:
	if dragging or resizing:
		var delta=DisplayServer.mouse_get_position()-drag_origin
		if resizing: size=Vector2i(maxi(min_size.x,drag_window.x+delta.x),maxi(min_size.y,drag_window.y+delta.y))
		else: position=drag_window+delta
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): dragging=false; resizing=false
	if visible and app.panes.get("scripts_rect",[])!=[position.x,position.y,size.x,size.y]: remember()

func frame_input(event: InputEvent, resize_frame: bool) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		dragging=event.pressed and not resize_frame; resizing=event.pressed and resize_frame
		drag_origin=DisplayServer.mouse_get_position(); drag_window=size if resize_frame else position

func close() -> void:
	remember(); hide();
	for overlay in hidden_overlays:
		if is_instance_valid(overlay): overlay.show()
	hidden_overlays.clear()
	app.panes["scripts"]=false; app.scripts_b.active=false; app.save_panes()

func document_changed() -> void:
	if not buffers.is_empty() and not str(buffers.get("song","")).is_empty() and buffers.song!=app.doc.path:
		# UI song switching guards dirty buffers; saved caches belong to the previous path.
		buffers={}; selected=""; current_file=""
	if visible: refresh()

func refresh() -> void:
	if app.doc.raw.is_empty():
		notice.text="先打开一首歌曲，再从三个模板创建插件。"; catalog=[]; selected=""; current_file=""; tabs.clear_tabs(); code.text=""; code.editable=false; trust_button.hide(); bind_button.disabled=true
		for child in list.get_children(): list.remove_child(child); child.queue_free()
		diagnostics.clear(); diagnostics.add_item("尚未打开歌曲，请先从歌曲库选择歌曲。")
		build_fields([])
		return
	catalog=workspace.list_plugins().get("plugins",[])
	for child in list.get_children(): list.remove_child(child); child.queue_free()
	for group in ["本曲插件","内置可选","标准内置（只读）"]:
		var fold=Button.new(); fold.text=group+"  ▾"; fold.alignment=HORIZONTAL_ALIGNMENT_LEFT; fold.custom_minimum_size.y=32; list.add_child(fold)
		var box=VBoxContainer.new(); list.add_child(box)
		box.visible=bool(app.panes.get("scripts_group_"+group,group!="标准内置（只读）"))
		fold.pressed.connect(func(): box.visible=not box.visible; app.panes["scripts_group_"+group]=box.visible; app.save_panes())
		for row in catalog:
			var category="标准内置（只读）" if row.standard else ("内置可选" if row.read_only else "本曲插件")
			if category!=group: continue
			var line=HBoxContainer.new(); box.add_child(line)
			var bound=CheckBox.new(); bound.button_pressed=row.bound; bound.disabled=row.standard; bound.tooltip_text="绑定至 chart.plugins（一步撤销）"; line.add_child(bound)
			bound.toggled.connect(func(on): bind_row(row,on))
			var pick=Button.new(); pick.alignment=HORIZONTAL_ALIGNMENT_LEFT; pick.size_flags_horizontal=Control.SIZE_EXPAND_FILL; pick.text=plugin_title(row)+"\n"+row.id+"@"+str(row.get("version","?"))+" · "+("内置" if row.read_only else ("脚本" if row.get("tier")=="script" else "声明式")); pick.add_theme_font_size_override("font_size",14); pick.clip_text=true; pick.tooltip_text=pick.text; pick.pressed.connect(func(): select_plugin(row.id)); line.add_child(pick)
			var dot=Label.new(); dot.text="●"; dot.add_theme_color_override("font_color",Tokens.OK if row.status=="ok" else Tokens.GOLD); dot.tooltip_text=status_text(row.status)+"\n"+"\n".join(row.diagnostics.map(func(d): return human_message(d.message))); line.add_child(dot)
	if catalog.filter(func(p): return not p.read_only).is_empty():
		var empty=Label.new(); empty.text="本曲还没有插件。\n点“新建”：视觉 / 事件 / 脚本。"; empty.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; list.add_child(empty)
	if selected.is_empty():
		for row in catalog:
			if not row.read_only: selected=row.id; break
	if not selected.is_empty(): select_plugin(selected)

func selected_row() -> Dictionary:
	for row in catalog:
		if row.id==selected: return row
	return {}

func plugin_title(row: Dictionary) -> String:
	if row.get("read_only",false):
		return {"fall_speed":"快慢光与变速","note_motion":"音符运动","shape_tracks":"形状轨道","standard_chart":"标准谱面","standard_render":"标准渲染","standard_rules":"标准判定","standard_stage":"标准舞台"}.get(row.id,row.id)
	return str(row.get("title",row.get("id","插件")))

func select_plugin(id: String) -> void:
	stash(); var previous_file=current_file; current_file=""; selected=id; var row=selected_row()
	heading.text=plugin_title(row)+" · "+id
	file_names=row.get("text_files",row.get("files",[])); tabs.set_block_signals(true); tabs.clear_tabs()
	for file in file_names: tabs.add_tab(file)
	bind_button.disabled=row.get("standard",false); bind_button.text="解除绑定" if row.get("bound",false) else "绑定"
	trust_button.visible=not row.get("read_only",true) and row.get("tier")=="script"
	notice.text="脚本包未信任：仅检查数据，不加载脚本；可由作者人工信任当前包。" if row.get("status")=="script-untrusted" else ("内置插件只读；勾选可选插件即可绑定。" if row.get("read_only",false) else "编辑插件文件后按 Ctrl+S 保存；文件保存与谱面撤销分开，写入前保留备份。")
	if not file_names.is_empty():
		var index=maxi(0,file_names.find(previous_file)); tabs.current_tab=index; select_file(index)
	else:
		code.text=""; code.editable=false; notice.text="此插件没有可编辑文本文件，请检查插件清单及文件路径。"
	tabs.set_block_signals(false)
	build_fields(row.get("fields",[]))
	display_diagnostics({"diagnostics":row.get("diagnostics",[])})

func stash() -> void:
	if selected.is_empty() or current_file.is_empty() or changing: return
	var key=selected+"/"+current_file
	if buffers.has(key): buffers[key].content=code.text

func select_file(index: int) -> void:
	if index<0 or index>=file_names.size(): return
	stash(); changing=true; current_file=file_names[index]
	var key=selected+"/"+current_file
	if not buffers.has(key):
		var result=workspace.read(selected,current_file)
		if result.has("error"): notice.text=human_message(result.error); code.text=""; code.editable=false; changing=false; return
		buffers[key]=result; buffers[key].saved=result.content; buffers["song"]=app.doc.path
	code.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY if current_file.get_extension().to_lower() in ["json","md"] else TextEdit.LINE_WRAPPING_NONE
	code.scroll_fit_content_width=false
	code.text=buffers[key].content; code.editable=not buffers[key].read_only
	var high=CodeHighlighter.new(); high.number_color=Tokens.GOLD; high.symbol_color=Tokens.CLAY
	high.add_color_region("\"","\"",Color("92b9a4")); high.add_keyword_color("true",Tokens.CLAY); high.add_keyword_color("false",Tokens.CLAY); high.add_keyword_color("null",Tokens.CLAY)
	if current_file.get_extension()=="gd":
		high.add_color_region("#","",Tokens.c("muted"),true); high.add_color_region("'","'",Color("92b9a4"))
		for keyword in ["extends","class_name","static","func","var","const","if","else","elif","for","while","return","pass","match","in","not","and","or","signal","await","class","self","super","void","bool","int","float","String","Array","Dictionary","RefCounted","PluginRegistry"]: high.add_keyword_color(keyword,Tokens.CLAY)
	if current_file.get_extension()=="gdshader": high.add_color_region("//","",Tokens.c("muted"),true); high.add_keyword_color("shader_type",Tokens.CLAY); high.add_keyword_color("void",Tokens.CLAY); high.add_keyword_color("vec4",Tokens.CLAY)
	code.syntax_highlighter=high
	changing=false; update_dirty()

func changed_text() -> void:
	if not changing:
		stash(); update_dirty()
		if current_file=="plugin.json":
			var parser=JSON.new()
			if parser.parse(code.text)==OK and parser.data is Dictionary:
				var checked=PluginLoader.validate_manifest(parser.data)
				if checked.errors.is_empty(): build_fields(checked.manifest.fields)

func has_dirty() -> bool:
	return buffers.keys().any(func(k): return k!="song" and buffers[k].content!=buffers[k].saved)

func update_dirty() -> void:
	for i in file_names.size():
		var key=selected+"/"+file_names[i]; var dirty=buffers.has(key) and buffers[key].content!=buffers[key].saved
		tabs.set_tab_title(i,file_names[i]+(" ●" if dirty else ""))

func save_file() -> void:
	stash(); var key=selected+"/"+current_file
	if not buffers.has(key) or buffers[key].read_only: return
	var data=buffers[key]; var result=workspace.write(selected,current_file,data.content,data.revision)
	if result.has("error"):
		if result.error=="stale revision": pending_conflict={"key":key,"revision":result.revision}; conflict.popup_centered(Vector2i(580,190))
		else: notice.text=human_message(result.error)
		return
	data.revision=result.revision; data.saved=data.content; refresh()
	notice.text="文件已保存，备份已保留。"+("脚本包内容已改变，玩家或作者需重新信任。" if selected_row().get("tier")=="script" and not result.get("trusted",false) else "声明式插件无需信任。")

func overwrite() -> void:
	if pending_conflict.is_empty(): return
	if pending_conflict.key!=selected+"/"+current_file: notice.text="文件已切换，请重新保存。"; return
	buffers[pending_conflict.key].revision=pending_conflict.revision; pending_conflict={}; save_file()

func reload_conflict() -> void:
	if pending_conflict.is_empty(): return
	buffers.erase(pending_conflict.key); pending_conflict={}; changing=true; code.text=""; changing=false; select_file(tabs.current_tab)

func bind_row(row: Dictionary, on: bool) -> void:
	var bindings=app.doc.raw.get("plugins",[]).duplicate(true).filter(func(p): return p.id!=row.id)
	if on: bindings.append({"id":row.id,"version":row.version})
	var result=workspace.set_bindings(bindings,app.doc.revision())
	if result.has("error"): notice.text=human_message(result.get("error","操作失败"))
	refresh()

func toggle_binding() -> void:
	var row=selected_row()
	if not row.is_empty(): bind_row(row,not row.get("bound",false))

func validate_selected() -> void:
	var dirty=buffers.keys().any(func(k): return k!="song" and buffers[k].content!=buffers[k].saved)
	var result=workspace.validate_plugin(selected); display_diagnostics(result); details.visible=true; details.current_tab=0; details_toggle.button_pressed=true
	notice.text=("检查已保存文件；请先保存带 ● 的修改。" if dirty else "检查已保存文件：")+status_text(result.get("status",""))

func display_diagnostics(result: Dictionary) -> void:
	diagnostics.clear(); diagnostics_data=result.get("diagnostics",[])
	if diagnostics_data.is_empty(): diagnostics.add_item("✓ 检查通过（脚本仅在受信任时检查语法）")
	for item in diagnostics_data: diagnostics.add_item("%s:%d · %s" % [item.file,item.line,human_message(item.message)])

func jump_diagnostic(index: int) -> void:
	if index>=diagnostics_data.size(): return
	var item=diagnostics_data[index]; var tab=file_names.find(item.file)
	if tab>=0: tabs.current_tab=tab; select_file(tab); code.set_caret_line(maxi(0,int(item.line)-1)); code.grab_focus()

func build_fields(schema: Array) -> void:
	for child in fields.get_children(): fields.remove_child(child); child.queue_free()
	var caption=Label.new(); caption.text="字段控件预览 · 使用默认值，不修改谱面"; caption.theme_type_variation="Muted"; fields.add_child(caption)
	if schema.is_empty():
		var empty=Label.new(); empty.text="此插件尚未声明字段。可在 plugin.json 的 fields 中添加字段说明。"; empty.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; fields.add_child(empty)
	for spec in schema:
		var row=HBoxContainer.new(); row.add_theme_constant_override("separation",12); fields.add_child(row)
		var label=Label.new(); label.text=str(spec.get("path",""))+"  ["+str(spec.get("unit",""))+"]"; label.tooltip_text=label.text+"\n"+str(spec.get("doc","")); label.custom_minimum_size.x=260; label.clip_text=true; row.add_child(label)
		var input: Control
		match spec.get("type",""):
			"number","integer":
				var number=SpinBox.new(); number.min_value=spec.get("min",0); number.max_value=spec.get("max",100); number.step=spec.get("step",1); number.value=spec.get("default",0); input=number
			"boolean":
				var b=CheckBox.new(); b.button_pressed=spec.get("default",false); input=b
			"enum":
				var e=OptionButton.new()
				for value in spec.get("enum",[]): e.add_item(str(value))
				e.select(maxi(0,spec.get("enum",[]).find(spec.get("default")))); input=e
			_:
				var e=LineEdit.new(); e.text=str(spec.get("default","")); e.editable=spec.get("type")=="string"; input=e
		input.custom_minimum_size=Vector2(160,32); input.tooltip_text=str(spec.get("doc","")); row.add_child(input)
		var doc_label=Label.new(); doc_label.text=str(spec.get("doc","")); doc_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; doc_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(doc_label)

func status_text(status: String) -> String:
	return {"ok": "检查通过", "errors": "检查发现错误", "script-untrusted": "脚本包未信任：只检查了清单和声明式部分", "missing-dependency": "缺少依赖插件"}.get(status,"检查未完成")

func human_message(message: String) -> String:
	var translated={"script not checked: pack not trusted": "脚本包未信任：未检查脚本语法，只检查清单和声明式部分", "stale revision": "文件修订已改变，请重新载入", "open a song first": "请先打开一首歌曲", "built-in plugins are read-only": "内置插件为只读", "unsafe plugin text path": "插件文本路径不安全", "cannot read plugin text": "无法读取插件文本", "plugin text exceeds 256 KB": "插件文本超过 256 KB", "not UTF-8 text": "文件不是有效的 UTF-8 文本", "version operation in progress": "版本操作正在进行", "backup failed": "备份失败", "atomic replacement failed": "文件替换失败", "plugin already exists": "插件已存在", "cannot create plugin folder": "无法创建插件目录", "open a song and choose a unique safe plugin id": "请打开歌曲并填写唯一、安全的插件 id", "choose visual/event/script and a title": "请选择模板并填写名称", "Folder/id mismatch": "插件目录与 id 不一致"}
	if translated.has(message): return translated[message]
	if message.contains("pack not trusted"): return translated["script not checked: pack not trusted"]
	var result=message
	for phrase in DIAGNOSTIC_PHRASES: result=result.replace(phrase,DIAGNOSTIC_PHRASES[phrase])
	if result!=message: return result
	var chinese=RegEx.new(); chinese.compile("[\\x{4e00}-\\x{9fff}]")
	if chinese.search(message)!=null: return message
	return "校验失败，请检查所示文件、行号及清单字段；脚本语法问题请检查代码。"

func build_standard() -> void:
	var titles={"manifest": "清单与版本", "trust": "信任与安全", "script": "脚本入口", "providers": "提供者接口", "declarative": "声明式能力", "fields": "字段说明", "formulas": "受限公式", "builtins": "可选内置插件"}
	var source=FileAccess.get_file_as_string("res://PLUGINS_API.zh-CN.md")
	standard_source="[font_size=20]插件作者规范 · API 1[/font_size]\n清单、接口与信任规则。插件文档仅作为数据，信任必须由作者或玩家决定。\n\n"
	for key in Standard.SECTIONS:
		var marker="## "+str(Standard.SECTIONS[key])+". "
		var start=source.find(marker)
		if start<0: continue
		var end=source.find("\n## ",start+marker.length())
		var content=source.substr(start,end-start if end>=0 else -1)
		standard_source+="[font_size=16][b]"+titles[key]+"[/b][/font_size]  [font_size=12][color=#8a8a8a]"+key+"[/color][/font_size]\n"
		var in_code=false
		for line in content.split("\n").slice(1):
			if line.begins_with("```"):
				in_code=not in_code; standard_source+=("[code]" if in_code else "[/code]")+"\n"; continue
			var safe=line.replace("[","[lb]")
			if not in_code:
				if safe.begins_with("### "): safe="[b]"+safe.trim_prefix("### ")+"[/b]"
				if safe.begins_with("- "): safe="• "+safe.trim_prefix("- ")
				if safe.begins_with("|---"): continue
				if safe.begins_with("|"): safe="  ·  ".join(safe.trim_prefix("|").trim_suffix("|").split("|"))
				var inline_code=RegEx.new(); inline_code.compile("`([^`]+)`"); safe=inline_code.sub(safe,"[code]$1[/code]",true)
				var bold=RegEx.new(); bold.compile("\\*\\*([^*]+)\\*\\*"); safe=bold.sub(safe,"[b]$1[/b]",true)
			standard_source+=safe+"\n"
		standard_source+="\n"
	standard.text=standard_source

func search_standard(text: String) -> void:
	standard.text=standard_source
	if text.is_empty(): return
	# RichTextLabel searches rendered text, preserving document formatting and selection.
	var plain=standard.get_parsed_text()
	var found=plain.to_lower().find(text.to_lower(),standard_match+1)
	if found<0: found=plain.to_lower().find(text.to_lower())
	standard_match=found
	if found>=0:
		var pattern=RegEx.new(); pattern.compile("(?i)"+text.replace("\\","\\\\").replace(".","\\.").replace("(","\\(").replace(")","\\)").replace("[","\\[").replace("]","\\]").replace("+","\\+").replace("*","\\*").replace("?","\\?").replace("{","\\{").replace("}","\\}").replace("^","\\^").replace("$","\\$").replace("|","\\|"))
		var chunks=standard_source.split("]")
		for i in chunks.size():
			var tag=chunks[i].find("[")
			var prose=chunks[i].substr(0,tag) if tag>=0 else chunks[i]
			chunks[i]=pattern.sub(prose,"[bgcolor=#665027]$0[/bgcolor]",true)+(chunks[i].substr(tag) if tag>=0 else "")
		standard.text="]".join(chunks)
		standard.scroll_to_paragraph(plain.left(found).count("\n"))

func confirm_trust() -> void:
	var row=selected_row()
	if row.get("read_only",true) or row.get("tier")!="script": return
	trust.popup_centered(Vector2i(620,240))

func build_create_dialog() -> void:
	add_child(create_dialog); create_dialog.title="新建插件"; create_dialog.ok_button_text="创建"
	var v=VBoxContainer.new(); create_dialog.add_child(v)
	for pair in [["插件 id（小写字母开头）",id_input],["名称",title_input]]:
		var l=Label.new(); l.text=pair[0]; v.add_child(l); v.add_child(pair[1]); pair[1].custom_minimum_size.y=32
	for item in ["声明式视觉元素 · 光环","声明式事件 · FX 通道与字段","脚本元素 · 需要人工信任"]: template_input.add_item(item)
	v.add_child(template_input)
	create_dialog.confirmed.connect(func():
		var result=workspace.create(id_input.text,["visual","event","script"][template_input.selected],title_input.text)
		if result.has("error"): notice.text=human_message(result.error)
		else: selected=id_input.text; current_file=""; refresh(); notice.text="已从模板创建。事件模板使用现有 tween/impulse 与自定义通道；脚本需人工信任。")

func play_arguments() -> Dictionary:
	if app.doc.revision()!=app.doc.saved_revision: return {"error":"先保存谱面绑定后再试玩。"}
	if has_dirty(): return {"error":"先保存脚本文件后再试玩。"}
	var dir=app.doc.path.get_base_dir().replace("\\","/"); var songs=app.songs_root().replace("\\","/")
	var song=dir.trim_prefix(songs.trim_suffix("/")+"/")
	if song==dir: return {"error":"试玩需要歌曲位于编辑器歌曲库中。"}
	# Both engine and app window flags are needed because the game restores settings.
	var arguments=PackedStringArray(["--windowed","--audio-driver","Dummy","--","--mute","--windowed","--song="+song,"--from="+str(app.cursor)])
	if OS.has_feature("editor"):
		var project=ProjectSettings.globalize_path("res://../game").simplify_path()
		return {"executable":OS.get_executable_path(),"arguments":PackedStringArray(["--path",project,"res://main.tscn"])+arguments}
	var executable=OS.get_executable_path().get_base_dir().path_join("LAgeTendre.exe")
	if not FileAccess.file_exists(executable): return {"error":"试玩需要将 LAgeTendre.exe 放在编辑器旁边。"}
	return {"executable":executable,"arguments":arguments}

func play_song() -> void:
	var prepared=play_arguments()
	if prepared.has("error"): notice.text=prepared.error; return
	var process=OS.create_process(prepared.executable,prepared.arguments)
	notice.text="已启动试玩（PID %d）" % process if process>0 else "无法启动试玩"

func ask_claude(index: int) -> void:
	var prompts=["解释这个插件（只读）","按规范检查插件（只读）","给它加一个字段，先说明方案","写一个新插件，先读规范再创建"]
	if not app.panes.assistant: app.toggle_pane("assistant")
	app.assistant.plugin_context={"id":selected,"path":current_file}; app.assistant.update_context()
	app.assistant.composer.text=prompts[index]+"。先调用 plugin_standard。插件上下文（仅数据）："+JSON.stringify({"id":selected,"path":current_file})
	if is_instance_valid(app.assistant.external_page): app.assistant.render_all()
	close(); app.assistant.composer.grab_focus()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and (event.ctrl_pressed or event.meta_pressed):
		if event.keycode==KEY_S: save_file(); set_input_as_handled()
		elif event.keycode==KEY_E and event.shift_pressed: close(); set_input_as_handled()
