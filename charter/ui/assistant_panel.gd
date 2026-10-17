extends "res://ui/stable_pane.gd"
## Agent side panel: optional native CLI backends and an always-available external MCP page.
## Shared conversation, attachment copies, selection context and GUI permission opt-ins.
## Follows the GUI selection (pin to freeze), one persistent conversation per song, tool calls
## as collapsible cards, keep / undo per turn. The empty conversation offers charting quick
## actions; later they sit behind a small 快捷 button above the input.

signal close_requested
signal turn_undo
signal turn_keep

const U = preload("res://ui/ui_util.gd")
const W = preload("res://ui/widgets.gd")
const Tokens = preload("res://theme.gd")
const Icons = preload("res://ui/icons.gd")
## Quick actions: [label, needs a selection, what to ask]. The selection context is added on send.
const QUICK := [
	["检查这段手感", true, "检查这一段的手感：找出纵连、跨键、判定窗过窄、单手过载的地方。按“小节.拍 + 问题 + 建议”逐条列出，最严重的放前面。只读，不要修改谱面。"],
	["按音乐补全灯光", true, "按音乐给这一段补全轨道灯光：先用 music 和 analysis 读能量、段落和重音，再用 track_state 看现有轨道。不移动音符；每个音符的承载轨要从落下前 1.3 秒起一直存在到长按结束。"],
	["让键型跟着旋律走", true, "让这一段的键型跟着旋律走：上行或下行用楼梯，来回的音型用交互，和弦用左右镜像。只改落键，不改时间，不要制造纵连或跨键。"],
	["给这段加镜头运动", true, "给这一段加镜头运动：先用 camera 读现有镜头事件和词表，按段落和重音加入远近、方向和判定线的变化，幅度克制，不要抢音符的视线。"],
	["把重音对上", true, "把这一段的重音对上：用 analysis 找出重音，把大音符和黄键（EX）放在重音上，去掉落在弱拍上的大音符和黄键。不改时间。"],
	["做一个简单难度版本", false, "做一个简单难度版本：先用 versions 查看写法；如果版本管理没有启用，就说明原因并停止，不要改谱面。启用了的话，用 branch_create 新建写法 easy 并切换过去，在上面删减音符：去掉连打和和弦里的次要音，保留主旋律和重音，长按保留。"],
	["解释这段为什么难", true, "解释这一段为什么难：从密度、节奏型、跨手和移位、判定窗、读谱（轨道和镜头变化）几个方面说明，指出最难的两三处（小节.拍）。只读，不要修改谱面。"],
]
const TOOL_RULES := "请使用 charter 的 MCP 工具：先读（song_info、selection、notes、track_state 等）再改，修改时带 expected_revision；这一轮的所有修改会合成一个撤销步骤。最后用两三句话说明你做了什么。"
const MENU_NEW := 0
const MENU_STATUS := 1
const MENU_LOGOUT := 2
const MENU_SAVE := 3
const MENU_COMMIT := 4

var bridge
var doc
var app
var backend := "external"
var selector = OptionButton.new()
var attachment_chips = HFlowContainer.new()
var attachment_quick = VBoxContainer.new()
var attachment_dialog = FileDialog.new()
var conversation_id = ""
var backend_sessions: Dictionary = {}
var external_page
var composer_shell
var copy_thread: Thread
var copy_paths: Array = []
var attachment_store:
	get: return app.api.attachments

var messages: Array = []
var context_pinned := false
var pinned_selection: Dictionary = {}
var plugin_context: Dictionary = {}
var streaming: RichTextLabel = null

var header := HBoxContainer.new()
var backend_slot := HBoxContainer.new()
var title := Label.new()
var more := MenuButton.new()
var logged_in := false
var quick_b := Button.new()
var quick_tray := PanelContainer.new()
var quick_flows: Array = []       # every rendered set of quick-action buttons, kept in step
var auth_row := HBoxContainer.new()
var auth_label := Label.new()
var login := Button.new()
var auth_log := RichTextLabel.new()
var chip_label := Label.new()
var pin := W.IconButton.new("lock", "固定当前选区（不再跟随）")
var scroll := ScrollContainer.new()
var list := VBoxContainer.new()
var thinking := Label.new()
var turn_actions := HBoxContainer.new()
var composer := TextEdit.new()
var send_b := Button.new()
var stop_b := W.IconButton.new("stop", "停止")

func _ready() -> void:
	theme_type_variation = "Pane"
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 10); add_child(v)
	# header
	v.add_child(header)
	var mark := Control.new(); mark.custom_minimum_size = Vector2(24, 34)
	mark.draw.connect(func(): Icons.draw(mark, "sparkle", Vector2(11, 17), 18, Tokens.CLAY))
	header.add_child(mark)
	title.text = "Agent"; title.theme_type_variation = "Title"; title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_PASS; title.tooltip_text = "使用已登录的 Claude CLI 的默认模型"
	U.bounded_label(title, 54)
	header.add_child(title)
	U.bounded_option(selector, 132)
	backend_slot.name = "BackendSlot"; header.add_child(backend_slot); backend_slot.add_child(selector); selector.item_selected.connect(_select_backend)   # "Claude | Codex" goes here
	var spacer := Control.new(); spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL; header.add_child(spacer)
	more.flat = true; more.text = "⋯"; more.focus_mode = Control.FOCUS_NONE; more.tooltip_text = "对话与权限"
	more.add_theme_font_size_override("font_size", Tokens.LG); more.custom_minimum_size = Vector2(34, 34)
	header.add_child(more)
	var popup := more.get_popup()
	popup.add_item("新对话", MENU_NEW); popup.add_separator()
	popup.add_check_item("允许助手保存谱面", MENU_SAVE); popup.add_check_item("允许助手保存版本", MENU_COMMIT)
	popup.add_separator(); popup.add_item("刷新登录状态", MENU_STATUS)
	popup.hide_on_checkable_item_selection = false
	popup.id_pressed.connect(_menu)
	var close_b := W.IconButton.new("close", "收起（Ctrl+I）"); close_b.pressed.connect(func(): close_requested.emit()); header.add_child(close_b)
	set_model_id(bridge.model_id if bridge != null else "")
	# auth
	v.add_child(auth_row)
	var dot := Control.new(); dot.custom_minimum_size = Vector2(12, 24); dot.name = "Dot"
	dot.draw.connect(func(): dot.draw_circle(Vector2(5, 12), 4, Tokens.c("ok") if auth_label.text.begins_with("已登录") else Tokens.c("faint"), true, -1, true))
	auth_row.add_child(dot)
	auth_label.text = "正在检查登录…"; auth_label.theme_type_variation = "Muted"; auth_label.clip_text = true; auth_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	auth_row.add_child(auth_label)
	login.text = "登录 Claude"; login.visible = false; login.pressed.connect(func(): app.report(bridge.auth("login"))); auth_row.add_child(login)
	auth_log.fit_content = false; auth_log.visible = false; auth_log.scroll_following = true; auth_log.custom_minimum_size.y = 80; v.add_child(auth_log)
	auth_row.visible = false
	# selection context chip
	var chip_box := PanelContainer.new(); chip_box.theme_type_variation = "ToolCard"; v.add_child(chip_box)
	var chip_row := HBoxContainer.new(); chip_box.add_child(chip_row)
	chip_label.theme_type_variation = "Muted"; chip_label.clip_text = true; chip_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip_row.add_child(chip_label)
	pin.toggle_mode = true; pin.custom_minimum_size = Vector2(32, 32); pin.icon_size = 16
	pin.toggled.connect(func(on): context_pinned = on; pinned_selection = doc.selection.duplicate(true); update_context())
	chip_row.add_child(pin)
	# conversation
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; list.add_theme_constant_override("separation", 12); scroll.add_child(list)
	U.bounded_label(thinking)
	thinking.custom_minimum_size.y = 20
	thinking.theme_type_variation = "Faint"; v.add_child(thinking)
	v.add_child(turn_actions); turn_actions.visible = false
	# quick actions behind a small button once the conversation has started
	quick_tray.theme_type_variation = "ToolCard"; quick_tray.visible = false; v.add_child(quick_tray)
	quick_tray.add_child(_quick_box())
	var keep := Button.new(); keep.text = "保留"; keep.theme_type_variation = "Ghost"; keep.pressed.connect(func(): turn_keep.emit()); turn_actions.add_child(keep)
	var undo_b := Button.new(); undo_b.text = "撤销这次修改"; undo_b.pressed.connect(func(): turn_undo.emit()); turn_actions.add_child(undo_b)
	var attachments_scroll := ScrollContainer.new(); attachments_scroll.custom_minimum_size.y = 40; attachments_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(attachments_scroll); attachment_chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL; attachments_scroll.add_child(attachment_chips); v.add_child(attachment_quick)
	# composer (CDS Chat Composer: 20 px shell, soft dual-ring shadow)
	var shell := PanelContainer.new(); composer_shell = shell; shell.theme_type_variation = "Composer"; v.add_child(shell)
	var cv := VBoxContainer.new(); cv.add_theme_constant_override("separation", 4); shell.add_child(cv)
	composer.placeholder_text = "描述你想怎样改这一段…"; composer.custom_minimum_size.y = 58
	composer.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY; composer.scroll_fit_content_height = false
	composer.gui_input.connect(_composer_input)
	cv.add_child(composer)
	var bar := HBoxContainer.new(); cv.add_child(bar)
	quick_b.text = "快捷"; quick_b.theme_type_variation = "Ghost"; quick_b.focus_mode = Control.FOCUS_NONE; quick_b.toggle_mode = true
	quick_b.tooltip_text = "常用的写谱请求"; quick_b.visible = false
	quick_b.toggled.connect(func(on): quick_tray.visible = on)
	bar.add_child(quick_b)
	var attach_b = W.IconButton.new("attach", "添加附件（也可拖放到窗口任意位置）"); attach_b.pressed.connect(func(): attachment_dialog.popup_centered_ratio(0.7)); bar.add_child(attach_b)
	attachment_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES; attachment_dialog.access = FileDialog.ACCESS_FILESYSTEM; attachment_dialog.use_native_dialog = true
	attachment_dialog.files_selected.connect(add_files); add_child(attachment_dialog)

	var hint := Label.new(); hint.text = "Enter 发送，Shift+Enter 换行"; hint.theme_type_variation = "Faint"; U.bounded_label(hint); bar.add_child(hint)
	stop_b.visible = false; stop_b.pressed.connect(func(): bridge.stop()); bar.add_child(stop_b)
	send_b.theme_type_variation = "Primary"; send_b.custom_minimum_size = Vector2(36, 36); send_b.focus_mode = Control.FOCUS_NONE
	send_b.tooltip_text = "发送"; send_b.draw.connect(func(): Icons.draw(send_b, "send", send_b.size / 2.0, 18, Color.WHITE, 2.0))
	for k in ["normal", "hover", "pressed", "disabled"]:
		var b: StyleBoxFlat = Tokens.box(Tokens.CLAY if k != "hover" else Tokens.CLAY_HOVER, 18, Color.TRANSPARENT, 0, 0)
		if k == "disabled": b.bg_color = Color(Tokens.CLAY, 0.35)
		send_b.add_theme_stylebox_override(k, b)
	send_b.pressed.connect(send); bar.add_child(send_b)
	set_backends(bridge.available)
	refresh_attachments()

func _composer_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode in [KEY_ENTER, KEY_KP_ENTER] and not e.shift_pressed:
		send(); composer.accept_event()

func _menu(id: int) -> void:
	var popup := more.get_popup()
	match id:
		MENU_NEW: new_conversation()
		MENU_STATUS: bridge.auth("status")
		MENU_SAVE:
			doc.allow_save = not doc.allow_save; popup.set_item_checked(popup.get_item_index(MENU_SAVE), doc.allow_save)
		MENU_COMMIT:
			var store = doc.version_store(); store.allow_commit = not store.allow_commit
			popup.set_item_checked(popup.get_item_index(MENU_COMMIT), store.allow_commit)
		MENU_LOGOUT:
			var confirm := ConfirmationDialog.new(); confirm.dialog_text = "确定退出 Claude CLI 登录？这也会影响终端中的 Claude。"; add_child(confirm)
			confirm.confirmed.connect(func(): app.report(bridge.auth("logout")))
			confirm.popup_centered(); confirm.visibility_changed.connect(func(): if not confirm.visible: confirm.queue_free())

func set_auth(value: Dictionary) -> void:
	if value.has("available"): set_backends(value.available)
	else:
		logged_in = value.get("loggedIn",false) and not value.has("error")
		bridge.available["claude"] = logged_in
		set_backends(bridge.available)
	_update_quick()

func set_backends(available: Dictionary) -> void:
	bridge.available = available.duplicate()
	var saved = JSON.parse_string(FileAccess.get_file_as_string("user://agent_backend.json")) if FileAccess.file_exists("user://agent_backend.json") else {}
	var wanted = str(saved.get("backend","")) if saved is Dictionary else ""
	var options = []
	for key in ["claude","codex"]:
		if available.get(key,false): options.append(key)
	options.append("external")
	var next = wanted if wanted in options else str(options[0])
	if bridge.running: return
	if next != backend:
		backend_sessions[backend] = bridge.session_id
		bridge.session_id = str(backend_sessions.get(next,"")); bridge.model_id = ""
	backend = next
	selector.clear()
	for key in options:
		selector.add_item({"claude":"Claude Code","codex":"Codex","external":"外部 Agent"}[key]); selector.set_item_metadata(selector.item_count-1,key)
	for i in selector.item_count:
		if selector.get_item_metadata(i) == backend: selector.select(i)
	bridge.backend = backend; logged_in = available.get(backend,false)
	render_all(); _update_quick()

func _select_backend(index: int) -> void:
	if bridge.running: app.report({"error":"stop the active turn before switching backend"}); return
	selector.select(index)
	backend_sessions[backend] = bridge.session_id
	backend = str(selector.get_item_metadata(index)); bridge.backend = backend; bridge.session_id = str(backend_sessions.get(backend,""))
	logged_in = bridge.available.get(backend,false)
	var f = FileAccess.open("user://agent_backend.json",FileAccess.WRITE)
	if f: f.store_string(JSON.stringify({"backend":backend})); f.close()
	render_all(); _update_quick()

func set_model_id(id: String) -> void:
	title.tooltip_text = ("模型：" + id) if not id.is_empty() else "使用当前 Agent CLI 的默认模型"

## ------------------------------------------------------------------ quick actions
func _has_selection(sel: Dictionary) -> bool:
	return sel.get("to", 0.0) > sel.get("from", 0.0) or not sel.get("notes", []).is_empty() or not sel.get("tracks", []).is_empty() or not sel.get("fx", []).is_empty()

func _quick_box() -> Control:
	var box := VBoxContainer.new(); box.add_theme_constant_override("separation", 8)
	var flow := HFlowContainer.new(); flow.add_theme_constant_override("h_separation", 6); flow.add_theme_constant_override("v_separation", 6)
	box.add_child(flow)
	for q in QUICK:
		var b := Button.new(); b.text = q[0]; b.focus_mode = Control.FOCUS_NONE; b.tooltip_text = q[2]
		var item: Array = q
		b.pressed.connect(func(): quick(item))
		flow.add_child(b)
	var why := Label.new(); why.theme_type_variation = "Faint"; why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; box.add_child(why)
	quick_flows.append({"flow": flow, "why": why})
	_update_quick()
	return box

## Enable each quick action only when it can run, and say why when it cannot.
func _update_quick() -> void:
	if doc == null: return
	var sel: Dictionary = pinned_selection if context_pinned else doc.selection
	var has_sel := _has_selection(sel)
	var running: bool = bridge != null and bridge.running
	for f in quick_flows:
		if not is_instance_valid(f.flow): continue
		var buttons: Array = f.flow.get_children()
		for i in buttons.size():
			var needs: bool = QUICK[i][1]
			buttons[i].disabled = (backend != "external" and not logged_in) or running or (needs and not has_sel)
		f.why.text = "复制请求给外部 Agent" if backend == "external" else ("Agent 暂不可用" if not logged_in else ("Agent 正在处理上一条" if running else ("" if has_sel else "先在时间线上选中一段")))
		f.why.visible = not f.why.text.is_empty()
	quick_flows = quick_flows.filter(func(f): return is_instance_valid(f.flow))

func quick(item: Array) -> void:
	var sel: Dictionary = pinned_selection if context_pinned else doc.selection
	var where := selection_text(sel)
	var prompt := "%s\n\n范围：%s。\n%s" % [item[2], where, TOOL_RULES]
	_send(prompt, "%s（%s）" % [item[0], where])
	quick_b.button_pressed = false

func show_auth_output(text: String) -> void:
	auth_log.visible = true; auth_log.append_text(text)

func selection_text(sel: Dictionary) -> String:
	if doc == null or doc.raw.is_empty(): return ""
	var parts := []
	if sel.get("to", 0.0) > sel.get("from", 0.0): parts.append("第 %s–%s 小节" % [doc.position(sel.from).bar_beat, doc.position(sel.to).bar_beat])
	if not sel.get("tracks", []).is_empty(): parts.append("轨道 " + ", ".join(sel.tracks.slice(0, 4).map(func(x): return str(int(x)))) + ("…" if sel.tracks.size() > 4 else ""))
	if not sel.get("notes", []).is_empty(): parts.append("%d 个音符" % sel.notes.size())
	if not sel.get("fx", []).is_empty(): parts.append("镜头 %d 个事件" % sel.fx.size())
	return "，".join(parts) if not parts.is_empty() else "没有选中内容，助手会参考整首歌"

func update_context() -> void:
	chip_label.text = ("已固定：" if context_pinned else "") + selection_text(pinned_selection if context_pinned else doc.selection)
	if not plugin_context.is_empty(): chip_label.text="插件 "+str(plugin_context.get("id",""))+" · "+str(plugin_context.get("path",""))
	pin.active = context_pinned
	_update_quick()

## ------------------------------------------------------------------ messages
func _bubble(role: String, text: String) -> Control:
	match role:
		"user":
			var row := HBoxContainer.new(); row.alignment = BoxContainer.ALIGNMENT_END
			var b := PanelContainer.new(); b.theme_type_variation = "Bubble"; b.size_flags_horizontal = Control.SIZE_SHRINK_END
			var l := Label.new(); l.text = text; l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size.x = minf(260.0, maxf(40.0, Tokens.font("sans").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 4))
			b.add_child(l); row.add_child(b)
			return row
		"tool":
			var card := PanelContainer.new(); card.theme_type_variation = "ToolCard"
			var cv := VBoxContainer.new(); card.add_child(cv)
			var parts := text.split("\n", true, 1)
			var head := W.IconButton.new("chevron_right", "展开或收起调用参数", "调用 " + parts[0]); head.icon_size = 14
			head.fixed_width = 240; head._fit(); head.clip_contents = true; head.size_flags_horizontal = Control.SIZE_FILL
			var detail := Label.new(); detail.text = parts[1] if parts.size() > 1 else ""; detail.theme_type_variation = "MonoMuted"
			detail.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY; detail.visible = false
			head.pressed.connect(func(): detail.visible = not detail.visible; head.icon_name = "chevron_down" if detail.visible else "chevron_right"; head.queue_redraw())
			cv.add_child(head); cv.add_child(detail)
			return card
		"note":
			var l := Label.new(); l.text = text; l.theme_type_variation = "Faint"; l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			return l
	var r := RichTextLabel.new(); r.bbcode_enabled = false; r.fit_content = true; r.selection_enabled = true
	r.text = text; r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return r

func add_message(role: String, text: String) -> void:
	messages.append({"role": role, "text": text})
	var node := _bubble(role, text)
	list.add_child(node)
	if role == "assistant": streaming = node
	_scroll_end()

func append_stream(text: String) -> void:
	if streaming == null:
		add_message("assistant", "")
	streaming.text += text
	messages[-1].text = streaming.text
	_scroll_end()

func end_stream() -> void:
	streaming = null

func _scroll_end() -> void:
	(func(): scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)).call_deferred()

func render_all() -> void:
	if composer_shell != null: composer_shell.visible = backend != "external"
	for c in list.get_children(): list.remove_child(c); c.queue_free()
	streaming = null
	quick_b.visible = not messages.is_empty()
	if backend == "external":
		external_page = preload("res://ui/external_agent.gd").new(); external_page.panel = self; list.add_child(external_page)
		return
	if messages.is_empty():
		list.add_child(_quick_box())
		return
	for m in messages: list.add_child(_bubble(m.role, m.text))
	_scroll_end()

## ------------------------------------------------------------------ persistence
func conversation_path() -> String:
	return "user://conversation-" + doc.path.sha256_text().left(20) + ".json"

func save_conversation() -> void:
	if doc == null or doc.path.is_empty(): return
	backend_sessions[backend] = bridge.session_id
	var f := FileAccess.open(conversation_path(), FileAccess.WRITE)
	if f: f.store_string(JSON.stringify({"backend": backend, "session_id": bridge.session_id, "sessions":backend_sessions,"conversation_id":conversation_id,"messages": messages})); f.close()

func load_conversation() -> void:
	plugin_context={}
	conversation_id = ""; backend_sessions = {}
	context_pinned = false; pinned_selection = {}; bridge.session_id = ""; messages = []
	if FileAccess.file_exists(conversation_path()):
		var saved = JSON.parse_string(FileAccess.get_file_as_string(conversation_path()))
		if saved is Dictionary:
			conversation_id = str(saved.get("conversation_id","")); backend_sessions = saved.get("sessions",{})
			bridge.session_id = str(backend_sessions.get(backend,saved.get("session_id", "") if backend == saved.get("backend","claude") else ""))
			if saved.has("messages"): messages = saved.messages
			elif not str(saved.get("history", "")).is_empty(): messages = [{"role": "assistant", "text": str(saved.history)}]
			messages = _without_old_intro(messages)
	attachment_store.start(conversation_id); conversation_id = attachment_store.conversation_id
	refresh_attachments(); render_all(); update_context()
	save_conversation()

## Conversations saved by the first editor started with a decorative intro; drop it on load.
const OLD_INTRO := ["用音乐的语言，雕刻光与节奏。", "选中一段谱面，再告诉 Claude 你想怎样改变。", "所有编辑通过内置 MCP，随时可以撤销。"]
static func _without_old_intro(list: Array) -> Array:
	var out := []
	for m in list:
		if not m is Dictionary: continue
		var text := str(m.get("text", ""))
		if m.get("role", "") == "assistant":
			for line in OLD_INTRO: text = text.replace(line, "")
			text = text.strip_edges()
			if text.is_empty(): continue
		var copy: Dictionary = m.duplicate(); copy.text = text; out.append(copy)
	return out

func new_conversation() -> void:
	if bridge.running: app.report({"error": "请先停止当前对话"}); return
	if copy_thread != null or not app.server.workers.is_empty(): app.report({"error":"附件或工具仍在处理，请稍后新建对话"}); return
	plugin_context={}; update_context()
	attachment_store.delete_conversation(); attachment_store.start(); conversation_id = attachment_store.conversation_id; backend_sessions = {}
	bridge.session_id = ""; messages = []; refresh_attachments(); render_all(); save_conversation()

## ------------------------------------------------------------------ turn
func send() -> void:
	var text := composer.text.strip_edges()
	if text.is_empty(): return
	if _send(text, text): composer.text = ""

## Send `prompt` to Claude; the conversation shows `shown` as the user's message.
func _send(prompt: String, shown: String) -> bool:
	if backend == "external":
		DisplayServer.clipboard_set(preload("res://agent_backends.gd").starter(app.api,app.server.endpoint())+"\nUser request: "+prompt)
		app.report({"message":"Request copied for external Agent"}); return true
	if messages.is_empty():
		for c in list.get_children(): list.remove_child(c); c.queue_free()
	add_message("user", shown)
	attachment_quick.visible = false
	quick_b.visible = true
	bridge.selection_context = (pinned_selection if context_pinned else doc.selection).duplicate(true)
	if not plugin_context.is_empty(): bridge.selection_context["plugin_data"]=plugin_context.duplicate(true)
	var result: Dictionary = bridge.send(prompt)
	app.report(result)
	if result.has("error"): add_message("note", str(result.error))
	save_conversation(); _update_quick()
	return not result.has("error")

func on_message(value: Dictionary) -> void:
	if value.get("type", "") == "stream_event":
		var delta: Dictionary = value.get("event", {}).get("delta", {})
		if delta.get("type", "") == "text_delta": append_stream(str(delta.get("text", "")))
	elif value.get("type", "") == "assistant":
		for item in value.get("message", {}).get("content", []):
			if item.get("type", "") == "text" and streaming == null: add_message("assistant", str(item.text))
			elif item.get("type", "") == "tool_use":
				end_stream(); add_message("tool", str(item.get("name", "")).trim_prefix("mcp__charter__") + "\n" + JSON.stringify(item.get("input", {}), "  "))
		end_stream()
	elif value.get("type", "") == "result" and value.get("is_error", false):
		var error: String = bridge.friendly_error(JSON.stringify(value))
		add_message("note", error)
		if error.contains("未登录"): bridge.auth("status")

func on_done(result: Dictionary) -> void:
	end_stream()
	set_model_id(bridge.model_id); _update_quick()
	if not str(result.get("stderr", "")).is_empty():
		add_message("note", str(result.stderr))
		if str(result.stderr).contains("未登录"): bridge.auth("status")
	var diff: Dictionary = result.get("diff", {})
	if result.get("changed", false):
		add_message("note", "这一轮改了 %d 个音符、%d 个轨道事件、%d 个镜头事件" % [diff.get("notes", []).size(), diff.get("lights", []).size(), diff.get("fx", []).size()])
	turn_actions.visible = result.get("changed", false)
	save_conversation()

func tick() -> void:
	var running: bool = bridge != null and bridge.running
	thinking.text = "正在思考" + ".".repeat(int(Time.get_ticks_msec() / 400) % 4) if running else ""
	if running and not bridge.model_id.is_empty() and not title.tooltip_text.ends_with(bridge.model_id): set_model_id(bridge.model_id)
	stop_b.visible = running; send_b.disabled = running
	selector.disabled = running
	if copy_thread != null and not copy_thread.is_alive():
		var completed = copy_thread.wait_to_finish(); copy_thread = null
		attachment_store.items = completed.items
		for result in completed.results:
			if result.has("error"): app.report(result); add_message("note",str(result.error))
		refresh_attachments(); save_conversation()
	if copy_thread == null and not copy_paths.is_empty(): _copy_next()
	if is_instance_valid(external_page) and backend == "external" and Time.get_ticks_msec()%30 == 0: external_page.refresh()


func add_files(paths: PackedStringArray) -> void:
	for path in paths: copy_paths.append(path)
	if copy_thread == null: _copy_next()

func _copy_next() -> void:
	if copy_paths.is_empty(): return
	var pending = copy_paths.duplicate(); copy_paths.clear()
	var store = preload("res://attachments.gd").new()
	store.conversation_id = attachment_store.conversation_id; store.items = attachment_store.items.duplicate(true)
	copy_thread = Thread.new()
	copy_thread.start(func():
		var results = []
		for path in pending: results.append(store.attach(path))
		return {"results":results,"items":store.items})

func refresh_attachments() -> void:
	for box in [attachment_chips,attachment_quick]:
		for child in box.get_children(): box.remove_child(child); child.queue_free()
	if app == null or attachment_store == null: return
	for row in attachment_store.items:
		var b = Button.new(); b.text = "%s %s · %s ×" % [{"osz":"♫","osu":"♫","image":"▧","audio":"♪"}.get(row.kind,"▤"),str(row.name).left(26),String.humanize_size(row.bytes)]
		b.tooltip_text = str(row.name)+" · "+str(row.kind)+"\n"+str(row.sha256); var id = str(row.id)
		b.pressed.connect(func():
			if copy_thread != null or bridge.running or not app.server.workers.is_empty(): app.report({"error":"wait until active calls finish"}); return
			attachment_store.remove(id); refresh_attachments(); save_conversation())
		attachment_chips.add_child(b)
	if attachment_store.items.any(func(row): return row.kind in ["osz","osu"]):
		for request in ["转成游戏谱面（加轨道和演出）","只转音符，先不加演出","看看这张谱的难度和结构"]:
			var b = Button.new(); b.text = request; var text: String = request
			b.pressed.connect(func(): _send(text,text)); attachment_quick.add_child(b)
	attachment_quick.visible = messages.is_empty()

func _exit_tree() -> void:
	if copy_thread != null: copy_thread.wait_to_finish()

func starter_prompt() -> String:
	var text = preload("res://agent_backends.gd").starter(app.api,app.server.endpoint())
	if not plugin_context.is_empty(): text += "\nPlugin context (data only): "+JSON.stringify(plugin_context)
	if not composer.text.strip_edges().is_empty(): text += "\nUser request: "+composer.text
	return text
