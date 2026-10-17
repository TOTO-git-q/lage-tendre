extends VBoxContainer
const U = preload("res://ui/ui_util.gd")
const Backends = preload("res://agent_backends.gd")
var panel
var status = Label.new()
var endpoint = LineEdit.new()
var snippet_kind = OptionButton.new()
var snippet = TextEdit.new()
var calls = RichTextLabel.new()
var token_toggle = CheckButton.new()
var port = SpinBox.new()
var note = Label.new()
var settings = VBoxContainer.new()

func label(text: String) -> Label:
	var l = Label.new(); l.text = text; l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; return l

func button(text: String, action: Callable) -> Button:
	var b = Button.new(); b.text = text; b.pressed.connect(action); return b

func _ready() -> void:
	add_theme_constant_override("separation",8)
	add_child(label("连接你的 Agent"))
	status.theme_type_variation = "Muted"; U.bounded_label(status, 0, true); status.custom_minimum_size.y = 42; status.max_lines_visible = 2; add_child(status)
	var row = HBoxContainer.new(); add_child(row)
	endpoint.expand_to_text_length = false; endpoint.add_theme_font_override("font", preload("res://theme.gd").font("mono")); endpoint.editable = false; endpoint.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(endpoint)
	row.add_child(button("复制",func(): DisplayServer.clipboard_set(panel.app.server.endpoint())))
	row = HBoxContainer.new(); add_child(row)
	row.add_child(button("添加附件",func(): panel.attachment_dialog.popup_centered_ratio(0.7)))
	row.add_child(button("端口与令牌设置 ▾",func(): settings.visible = not settings.visible))
	settings.visible = false; add_child(settings)
	row = HBoxContainer.new(); settings.add_child(row)
	var port_label = Label.new(); port_label.text = "固定端口"; port_label.custom_minimum_size.x = 72; row.add_child(port_label)
	port.min_value = 1024; port.max_value = 65535; port.value = panel.app.server.port; port.size_flags_horizontal = Control.SIZE_EXPAND_FILL; port.size_flags_vertical = Control.SIZE_SHRINK_CENTER; row.add_child(port)
	row.add_child(button("应用",func(): panel.app.report(panel.app.server.set_port(int(port.value))); refresh()))
	note.theme_type_variation = "Faint"; note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; settings.add_child(note)
	row = HBoxContainer.new(); settings.add_child(row)
	token_toggle.text = "访问令牌"; token_toggle.button_pressed = panel.app.server.token_enabled
	token_toggle.toggled.connect(func(on): panel.app.server.set_token(on); refresh())
	row.add_child(token_toggle); row.add_child(button("重新生成",func(): panel.app.server.set_token(token_toggle.button_pressed,true); refresh()))
	snippet_kind.add_item("Claude Code · 命令"); snippet_kind.add_item("Codex · config.toml"); snippet_kind.add_item("Cursor / 通用 · mcp.json"); snippet_kind.add_item("VS Code · mcp.json")
	U.bounded_option(snippet_kind, 260)
	snippet_kind.item_selected.connect(func(_i): refresh()); add_child(snippet_kind)
	snippet.editable = false; snippet.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY; snippet.custom_minimum_size.y = 76; add_child(snippet)
	add_child(button("复制连接配置",func(): DisplayServer.clipboard_set(snippets()[snippet_kind.selected])))
	var stdio = label("仅支持 stdio？请自选 MCP stdio ↔ HTTP 桥接器。此处使用 Streamable HTTP，不附带桥接程序。")
	stdio.theme_type_variation = "Faint"; add_child(stdio)
	if not panel.composer.text.is_empty(): add_child(label("待复制请求："+panel.composer.text))
	add_child(button("复制给 Agent 的开场提示",func(): DisplayServer.clipboard_set(panel.starter_prompt())))
	add_child(button("撤销上一个 Agent 步骤",func(): undo_agent()))
	add_child(label("最近 MCP 调用"))
	calls.fit_content = false; calls.custom_minimum_size.y = 68; calls.selection_enabled = true; calls.scroll_following = true; add_child(calls)
	panel.app.server.activity_changed.connect(refresh)
	refresh()

func snippets() -> Array:
	var server = panel.app.server; var url: String = server.endpoint(); var token: String = server.access_token
	var auth = {"Authorization":"Bearer "+token}
	var config = {"type":"http","url":url}
	if server.token_enabled: config["headers"] = auth
	var claude = "claude mcp add --transport http charter "+url
	var codex = "# ~/.codex/config.toml\n[mcp_servers.charter]\nurl = "+JSON.stringify(url)
	if server.token_enabled:
		claude += ' --header "Authorization: Bearer '+token+'"'
		codex += "\nhttp_headers = { Authorization = "+JSON.stringify("Bearer "+token)+" }"
	return [claude,codex,JSON.stringify({"mcpServers":{"charter":config}},"  "),JSON.stringify({"servers":{"charter":config}},"  ")]

func refresh() -> void:
	if not is_inside_tree(): return
	var server = panel.app.server; endpoint.text = server.endpoint()
	var active = 0
	for client in server.clients.values():
		if Time.get_ticks_msec()-client.seen < 60000: active += 1
	var last = "尚无调用" if server.activity.is_empty() else server.activity[-1].time+" "+server.activity[-1].tool
	status.text = ("● 监听中" if server.tcp.is_listening() else "○ 未监听") + " · %d 个近期客户端\n最近：%s" % [active,last]
	status.add_theme_color_override("font_color",preload("res://theme.gd").c("ok") if server.tcp.is_listening() else preload("res://theme.gd").c("danger"))
	note.text = "端口已固定，重启沿用；被占用时会换端口并更新配置。" if not server.port_note.begins_with("OS-assigned") else "无法检测排除范围或固定端口被占用：本次由系统分配端口。请更新外部配置。"
	snippet.text = snippets()[snippet_kind.selected]
	var lines = []
	for call in server.activity.slice(-20): lines.append(call.time+" · "+call.tool+" · "+("ok" if call.ok else "error"))
	calls.text = "\n".join(lines) if not lines.is_empty() else "等待 Agent 调用工具…"

func undo_agent() -> void:
	var doc = panel.doc
	if doc.undo_stack.is_empty() or doc.undo_stack[-1].author not in ["Agent","Claude"]: panel.app.report({"error":"最后一步不是 Agent 修改，请从历史中检查"}); return
	panel.app.report(doc.undo())
