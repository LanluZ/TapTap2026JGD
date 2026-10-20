extends Control
## 关卡 UI 根节点：HUD + 手牌 + 放置预览 + 卡牌库/战报 + 设置面板。
##
## 对外契约（逻辑层接线只依赖这里）：
##   公开方法：set_resources / set_hand / set_hand_max / set_wave_info /
##             set_enemy_count / set_placement_preview / set_grid_geometry /
##             set_library_cards / set_library_expanded /
##             set_receipts / cancel_placement / get_selected_card / is_placing /
##             get_hand / open_settings / is_settings_open / load_mock_data /
##             select_line_tool / get_line_tool / show_result
##   信号：card_selected(card)、card_played(card, cell)、placement_cancelled()、
##         line_tool_selected(tool)、line_committed(kind, cells, dir)
##
## 数据全部由调用方注入；本脚本只做展示与交互状态，不引用
## scripts/ecs/、scripts/systems/、scripts/config/ 下任何内容。

signal card_selected(card: Dictionary)
signal card_played(card: Dictionary, cell: Vector2i)
signal placement_cancelled()
signal fusion_toggled(enabled: bool) # 融合模式开关（DNA 系统）
signal fusion_confirmed(seed: int) # 融合确定（种子，0 = 随机）
signal factory_cell_clicked(cell: Vector2i) # 融合模式下点选工厂所在格
signal wave_toggled(running: bool) # 右上角「开始/暂停」按钮
signal speed_toggled(speed: float) # 右上角速度按钮（1/2 倍速切换）
signal line_tool_selected(tool: String) # 物流工具选中态变化（"" = 无工具）
signal line_committed(kind: String, cells: Array, dir: Vector2i) # 拖拽画线松手

const HudScript = preload("res://scripts/ui/hud.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")
const HandScript = preload("res://scripts/ui/hand_area.gd")
const OverlayScript = preload("res://scripts/ui/placement_preview.gd")
const LineOverlayScript = preload("res://scripts/ui/line_draw_overlay.gd")
const LibraryScript = preload("res://scripts/ui/card_library.gd")
const ReceiptsScript = preload("res://scripts/ui/receipt_list.gd")
const DnaInspectorScene = preload("res://scenes/ui/dna_inspector.tscn")

## true 时在 _ready 里灌入演示假数据（便于 UI 单独自展示）；
## 调用方只要在 ready 前/后调用过任意 setter，演示数据即让位。
@export var auto_mock: bool = true

var _hud: HudScript
var _hand: HandScript
var _overlay: OverlayScript
var _library: LibraryScript
var _receipts: ReceiptsScript
var _hand_count: Label

var _nodes_ready := false
var _signals_ready := false
var _structure_warned := false
var _external_data := false
var _fusion_panel: PanelContainer
var _fusion_toggle: CheckButton
var _fusion_seed_edit: LineEdit
var _fusion_status: Label
var _fusion_enabled := false
var _dna_popup: PanelContainer
var _dna_inspector: Control
var _current_card_id := "" # 右键同一张卡再次点击 = 收起
var _start_btn: Button
var _speed_btn: Button
var _settings: Control # scenes/ui/settings_panel.tscn 实例（main.tscn 内）
var _wave_running := false # 与 GameState.waves_running 初值一致（默认暂停）
var _speed := 1.0
var _line_overlay: LineOverlayScript
var _line_buttons: Dictionary = {} # "pipe"/"belt"/"remove" -> Button
var _line_tool := "" # "" = 无工具；与卡牌选中互斥（见 _apply_line_tool）
var _result_panel: Control = null # 胜负结算面板（程序化构建，见 show_result）
var _result_data: Dictionary = {}


func _ready() -> void:
	_prepare()
	if auto_mock and not _external_data:
		load_mock_data()


func _prepare() -> void:
	_resolve_nodes()
	_connect_signals()


func _resolve_nodes() -> void:
	if _nodes_ready:
		return
	_hud = get_node_or_null("HUD") as HudScript
	_hand = get_node_or_null("HandPanel/VBox/HandArea") as HandScript
	_overlay = get_node_or_null("PlacementOverlay") as OverlayScript
	_library = get_node_or_null("RightRail/CardLibrary") as LibraryScript
	_receipts = get_node_or_null("RightRail/Receipts") as ReceiptsScript
	_hand_count = get_node_or_null("HandPanel/VBox/Head/Count") as Label
	if _hud == null or _hand == null or _overlay == null:
		if not _structure_warned:
			_structure_warned = true
			push_error("[关卡UI] 场景缺少必需节点或脚本（HUD / HandPanel/VBox/HandArea / PlacementOverlay），检查 main.tscn")
		return
	_nodes_ready = true
	_start_btn = get_node_or_null("HUD/TopBar/Row/StartBtn") as Button
	_speed_btn = get_node_or_null("HUD/TopBar/Row/SpeedBtn") as Button
	if _start_btn == null or _speed_btn == null:
		push_warning("[关卡UI] main.tscn 缺少 HUD/TopBar/Row 下的 StartBtn/SpeedBtn")
	_bind_settings()
	_build_fusion_panel()
	_build_dna_popup()
	_bind_line_tools()


## 设置面板实例（main.tscn 内的 SettingsPanel）：「返回标题」由本层切场景，
## 其余（暂停/恢复、ESC 关闭）都由 settings_panel.gd 自己处理。
func _bind_settings() -> void:
	_settings = get_node_or_null("SettingsPanel")
	if _settings == null:
		push_warning("[关卡UI] main.tscn 缺少 SettingsPanel 实例（res://scenes/ui/settings_panel.tscn）")
		return
	if not _settings.is_connected("title_requested", _on_settings_title_requested):
		_settings.connect("title_requested", _on_settings_title_requested)


## 物流工具（main.tscn 的 HUD/TopBar/Row/LineTools + LineOverlay）：三按钮互斥选中，
## 选中后拖拽画线由 LineOverlay 接管（几何走同一个 set_grid_geometry）。
## 与卡牌打出流程互斥：选工具清卡牌选中，选卡/融合清工具（仲裁收口在 _apply_line_tool）。
func _bind_line_tools() -> void:
	_line_overlay = get_node_or_null("LineOverlay") as LineOverlayScript
	if _line_overlay == null:
		push_warning("[关卡UI] main.tscn 缺少 LineOverlay（拖拽画线层）")
	else:
		_line_overlay.line_committed.connect(_on_line_committed)
		_line_overlay.cancelled.connect(_on_line_cancelled)
	var bar := get_node_or_null("HUD/TopBar/Row/LineTools")
	if bar == null:
		push_warning("[关卡UI] main.tscn 缺少 HUD/TopBar/Row/LineTools")
		return
	for entry in [["Pipe", "pipe"], ["Belt", "belt"], ["Remove", "remove"]]:
		var node_name := String(entry[0])
		var kind := String(entry[1])
		var btn := bar.get_node_or_null(node_name) as Button
		if btn == null:
			push_warning("[关卡UI] LineTools 缺少按钮: " + node_name)
			continue
		btn.toggle_mode = true
		_line_buttons[kind] = btn
		btn.pressed.connect(_on_line_tool_pressed.bind(kind))


## 按钮点击：toggle 已把自身状态翻好，按下 = 切到该工具，弹起 = 取消工具。
func _on_line_tool_pressed(kind: String) -> void:
	var btn: Button = _line_buttons.get(kind, null)
	_apply_line_tool(kind if btn != null and btn.button_pressed else "")


## 拖拽松手 → 上层接线层（game.gd）转成 place_line / remove_line 指令。
func _on_line_committed(kind: String, cells: Array, dir: Vector2i) -> void:
	line_committed.emit(kind, cells, dir)


## 右键 / Esc 取消画线工具（LineOverlay 自己已 deactivate，这里同步按钮与状态）。
func _on_line_cancelled() -> void:
	_apply_line_tool("")


## DNA 检视弹窗（程序化构建）：内嵌 dna_inspector 预制体；关闭按钮/Esc/再右键收起。
func _build_dna_popup() -> void:
	if _dna_popup != null:
		return
	_dna_popup = PanelContainer.new()
	# 外壳只提供投影，卡片观感由 dna_inspector 自带的圆角面板负责（避免双重描边）
	var shadow := StyleBoxFlat.new()
	shadow.bg_color = Color(0, 0, 0, 0)
	shadow.set_corner_radius_all(12)
	shadow.shadow_size = 14
	shadow.shadow_color = Color(0, 0, 0, 0.5)
	shadow.shadow_offset = Vector2(0, 4)
	_dna_popup.add_theme_stylebox_override("panel", shadow)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_dna_inspector = DnaInspectorScene.instantiate()
	vbox.add_child(_dna_inspector)
	var close := Button.new()
	close.text = "关闭"
	close.pressed.connect(hide_dna)
	vbox.add_child(close)
	_dna_popup.add_child(vbox)
	add_child.call_deferred(_dna_popup)
	_dna_popup.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_dna_popup.offset_top = 96.0
	_dna_popup.visible = false


## 显示 DNA 检视（data 由调用方注入：{title, bases, locus_names, rules, debug}）
func show_dna(data: Dictionary) -> void:
	_prepare()
	if _dna_popup == null or _dna_inspector == null:
		return
	_dna_inspector.set_view(data)
	_dna_popup.visible = true


func hide_dna() -> void:
	_prepare()
	if _dna_popup != null:
		_dna_popup.visible = false


## 融合面板（DNA 系统）：程序化构建，不改 main.tscn。顶部居中：开关 / 种子 / 确定 / 已选计数。
func _build_fusion_panel() -> void:
	if _fusion_panel != null:
		return
	_fusion_panel = PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_fusion_toggle = CheckButton.new()
	_fusion_toggle.text = "融合"
	_fusion_toggle.toggled.connect(_on_fusion_toggled)
	row.add_child(_fusion_toggle)
	var seed_label := Label.new()
	seed_label.text = "种子"
	row.add_child(seed_label)
	_fusion_seed_edit = LineEdit.new()
	_fusion_seed_edit.text = "0"
	_fusion_seed_edit.custom_minimum_size = Vector2(64, 0)
	_fusion_seed_edit.tooltip_text = "0 = 每次随机；非 0 = 同种子同双亲必出同子代"
	row.add_child(_fusion_seed_edit)
	var confirm := Button.new()
	confirm.text = "确定"
	confirm.pressed.connect(_on_fusion_confirm_pressed)
	row.add_child(confirm)
	_fusion_status = Label.new()
	_fusion_status.text = "已选 0 / 2"
	row.add_child(_fusion_status)
	_fusion_panel.add_child(row)
	# Main._ready 期间 add_child 会被 ready_lock 拒绝（busy setting up children），延迟挂载
	add_child.call_deferred(_fusion_panel)
	_fusion_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_fusion_panel.offset_top = 76.0 # TopBar 内容边距调整后高约 66，留 10px 间隙


func _connect_signals() -> void:
	if not _nodes_ready or _signals_ready:
		return
	_hand.card_selected.connect(_on_card_selected)
	_hand.selection_cleared.connect(_on_selection_cleared)
	_hand.card_right_clicked.connect(_on_card_right_clicked)
	_overlay.cell_clicked.connect(_on_cell_clicked)
	_overlay.cancelled.connect(_on_overlay_cancelled)
	if _start_btn != null:
		_start_btn.pressed.connect(_on_start_pressed)
	if _speed_btn != null:
		_speed_btn.pressed.connect(_on_speed_pressed)
	_signals_ready = true


# ---------------------------------------------------------------- 公开 API

## 资源条数值注入：{"parts","special","power"} -> 数值（与 hud.gd 的 RESOURCE_IDS 一致）
func set_resources(resources: Dictionary) -> void:
	_prepare()
	_external_data = true
	if _hud != null:
		_hud.set_resources(resources)


## 手牌注入：元素为卡牌 Dictionary{id,name,kind,icon,desc,cost}（cost=消耗文案，空则卡面不显示）
func set_hand(cards: Array) -> void:
	_prepare()
	_external_data = true
	if _hand == null:
		return
	_hand.set_hand(cards)
	_update_hand_count()


## 手牌上限（决定槽位数量）
func set_hand_max(hand_max: int) -> void:
	_prepare()
	_external_data = true
	if _hand == null:
		return
	_hand.set_hand_max(hand_max)
	_update_hand_count()


## 波次进度 current/total
func set_wave_info(current: int, total: int) -> void:
	_prepare()
	_external_data = true
	if _hud != null:
		_hud.set_wave_info(current, total)


## 路径敌人数 / 失败上限
func set_enemy_count(count: int, cap: int) -> void:
	_prepare()
	_external_data = true
	if _hud != null:
		_hud.set_enemy_count(count, cap)


## 放置预览：可放格集合（元素 Vector2i；也接受未类型化 Array）
func set_placement_preview(valid_cells: Array) -> void:
	_prepare()
	_external_data = true
	if _overlay != null:
		_overlay.set_valid_cells(valid_cells)


## 放置网格几何（格数据来自逻辑层；未调用时 overlay 用内置 mock 网格）
func set_grid_geometry(origin: Vector2, cell_size: Vector2i, cells: Array) -> void:
	_prepare()
	_external_data = true
	if _overlay != null:
		_overlay.set_grid_geometry(origin, cell_size, cells)
	if _line_overlay != null:
		_line_overlay.set_grid_geometry(origin, cell_size, cells)


## 卡牌库
func set_library_cards(cards: Array) -> void:
	_prepare()
	_external_data = true
	if _library != null:
		_library.set_cards(cards)


func set_library_expanded(expanded: bool) -> void:
	_prepare()
	if _library != null:
		_library.set_expanded(expanded)


## 战报 / 回执：元素为 String 或 {icon, text}
func set_receipts(items: Array) -> void:
	_prepare()
	_external_data = true
	if _receipts != null:
		_receipts.set_items(items)


## 程序化取消放置（等价于玩家按 Esc / 右键）
func cancel_placement() -> void:
	_prepare()
	if not _line_tool.is_empty():
		_apply_line_tool("")
	if _hand != null:
		_hand.clear_selection(true)
	if _overlay != null:
		_overlay.deactivate()


## 融合选择状态注入：已选工厂数（显示用）
func set_fusion_selection(count: int) -> void:
	_prepare()
	if _fusion_status != null:
		_fusion_status.text = "已选 %d / 2" % count


func is_fusion_mode() -> bool:
	return _fusion_enabled


func get_selected_card() -> Dictionary:
	_prepare()
	return _hand.get_selected_card() if _hand != null else {}


func is_placing() -> bool:
	_prepare()
	return _overlay.is_active() if _overlay != null else false


## 程序化选择物流工具（"" = 取消；pipe / belt / remove）。按钮态、画线层、卡牌互斥在此收口。
func select_line_tool(tool: String) -> void:
	_prepare()
	if not ["", "pipe", "belt", "remove"].has(tool):
		push_warning("[关卡UI] 未知物流工具: " + tool)
		return
	_apply_line_tool(tool)


func get_line_tool() -> String:
	_prepare()
	return _line_tool


## 交互仲裁唯一入口（三按钮互斥 / 画线层鼠标接管 / 与卡牌选中·融合模式互斥）：
##   选中工具 → 只有该工具按钮按下；LineOverlay 以 MOUSE_FILTER_STOP 吞掉场地点击，
##              同时清空卡牌选中、关掉卡牌放置预览、退出融合模式（否则两套格子点击会抢同一个格）；
##   取消工具 → 归还鼠标与格子点击给卡牌流程。
func _apply_line_tool(tool: String) -> void:
	_line_tool = tool
	for k in _line_buttons:
		(_line_buttons[k] as Button).button_pressed = (k == tool)
	if _line_overlay != null:
		if tool.is_empty():
			_line_overlay.deactivate()
		else:
			_line_overlay.activate(tool)
	if not tool.is_empty():
		if _fusion_enabled and _fusion_toggle != null:
			# 互斥：工具接管格子点击 → 融合必须真正退出。只弹开关不写 _fusion_enabled
			# 会留下「开关亮着但格子点击没有消费方」的静默失效；走 toggled(false) 一并复位。
			_fusion_toggle.button_pressed = false
		if _overlay != null:
			_overlay.deactivate()
		if _hand != null and _hand.get_selected_index() >= 0:
			_hand.clear_selection(true) # 走 selection_cleared → placement_cancelled
	line_tool_selected.emit(tool)


func get_hand() -> Array:
	_prepare()
	return _hand.get_cards() if _hand != null else []


func get_hand_max() -> int:
	_prepare()
	return _hand.get_hand_max() if _hand != null else 0


## 演示假数据（仅 UI 自展示用，全部可被上层 setter 覆盖）
func load_mock_data() -> void:
	_prepare()
	set_resources({"parts": 246, "special": 3, "power": 38})
	set_hand_max(7)
	set_hand([
		{"id": "mock_slow_tile", "name": "减速带", "kind": "tile", "icon": "🛣"},
		{"id": "mock_wind_plant", "name": "风力电厂", "kind": "factory", "icon": "🌬"},
		{"id": "mock_refinery", "name": "精炼厂", "kind": "factory", "icon": "🏭"},
		{"id": "mock_fork_tile", "name": "岔路", "kind": "tile", "icon": "🔀"},
		{"id": "mock_turret", "name": "自动炮塔", "kind": "factory", "icon": "🔫"},
	])
	set_wave_info(7, 15)
	set_enemy_count(13, 20)
	set_library_cards([
		{"id": "mock_turret", "name": "自动炮塔", "kind": "factory", "icon": "🔫"},
		{"id": "mock_wind_plant", "name": "风力电厂", "kind": "factory", "icon": "🌬"},
		{"id": "mock_refinery", "name": "精炼厂", "kind": "factory", "icon": "🏭"},
		{"id": "mock_slow_tile", "name": "减速带", "kind": "tile", "icon": "🛣"},
		{"id": "mock_fork_tile", "name": "岔路", "kind": "tile", "icon": "🔀"},
		{"id": "mock_pipe_tile", "name": "水管", "kind": "tile", "icon": "🚿"},
	])
	set_receipts([
		{"icon": "·", "text": "（演示数据）这是战报/回执占位，等待逻辑层注入"},
		{"icon": "·", "text": "（演示数据）资源、波次、手牌均为占位值"},
	])


# ---------------------------------------------------------------- 内部接线

func _on_fusion_toggled(on: bool) -> void:
	_fusion_enabled = on
	if on and not _line_tool.is_empty():
		_apply_line_tool("") # 互斥：融合点选与物流工具都吃格子点击，同时只能有一个
	if _hand != null:
		_hand.clear_selection(true) # 融合模式下不打牌
	if _overlay != null:
		if on:
			_overlay.activate("fusion")
		else:
			_overlay.deactivate()
	set_fusion_selection(0)
	fusion_toggled.emit(on)


func _on_fusion_confirm_pressed() -> void:
	fusion_confirmed.emit(_fusion_seed_edit.text.strip_edges().to_int())


## 开始/暂停切换：按钮文案与波次开关同步，状态由逻辑层接线落地
func _on_start_pressed() -> void:
	_wave_running = not _wave_running
	_start_btn.text = "暂停" if _wave_running else "开始"
	wave_toggled.emit(_wave_running)


func _on_speed_pressed() -> void:
	_speed = 2.0 if _speed == 1.0 else 1.0
	_speed_btn.text = "%d倍速" % int(_speed)
	speed_toggled.emit(_speed)


func _on_card_selected(card: Dictionary) -> void:
	hide_dna()
	if not _line_tool.is_empty():
		_apply_line_tool("") # 互斥：选卡 = 退出物流工具，格子点击交回卡牌流程
	if _fusion_enabled:
		_fusion_toggle.button_pressed = false # 选卡退出融合模式
	if _overlay != null:
		_overlay.activate(str(card.get("kind", "")))
	card_selected.emit(card)


## 右键卡片 → DNA 检视；再右键同一张或 Esc/关闭按钮收起。
func _on_card_right_clicked(card: Dictionary) -> void:
	var data: Dictionary = card.get("dna_ui", {})
	if _dna_popup != null and _dna_popup.visible and _current_card_id == str(card.get("id", "")):
		hide_dna()
		return
	_current_card_id = str(card.get("id", ""))
	if data.is_empty():
		data = { "title": str(card.get("name", "")), "bases": [], "locus_names": [],
			"rules": ["该卡没有 DNA"], "debug": str(card.get("dna", "")) }
	show_dna(data)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		return
	# 面板打开时处于暂停态：ESC 由 settings_panel.gd 处理（它 process_mode=WHEN_PAUSED）
	if _settings != null and _settings.visible:
		return
	# ESC 优先收尾正在看的东西，其次才是打开设置
	if _dna_popup != null and _dna_popup.visible:
		hide_dna()
		get_viewport().set_input_as_handled()
		return
	open_settings()
	get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- 设置面板

## 打开设置面板（等价于游戏内按 ESC）：暂停整棵场景树
func open_settings() -> void:
	_prepare()
	if _settings != null:
		_settings.open()


func is_settings_open() -> bool:
	return _settings != null and _settings.visible


# ---------------------------------------------------------------- 胜负结算

## 胜负结算面板（逻辑层在 game_won / game_lost 后调用）：
## data = {level_id, waves_survived, wave_total, enemy_cap}，只用于文案与「重新开始」的关卡回填。
## 幂等：重复调用只更新文案，不重复建节点。程序化构建，不改 main.tscn。
func show_result(won: bool, data: Dictionary = {}) -> void:
	_prepare()
	_result_data = data.duplicate()
	cancel_placement()
	hide_dna()
	if _result_panel == null:
		_build_result_panel()
	var title: Label = _result_panel.get_node_or_null("Center/Panel/Margin/VBox/Title") as Label
	var sub: Label = _result_panel.get_node_or_null("Center/Panel/Margin/VBox/Subtitle") as Label
	if title != null:
		title.text = "关卡胜利" if won else "关卡失败"
		title.add_theme_color_override("font_color",
			UiStyle.COLOR_ACCENT if won else Color(1.0, 0.42, 0.52))
	if sub != null:
		sub.text = _result_subtitle(won)
	_result_panel.visible = true


func _result_subtitle(won: bool) -> String:
	if won:
		return "已撑过 %d / %d 波，场上敌人已清空" % [
			int(_result_data.get("waves_survived", 0)), int(_result_data.get("wave_total", 0))]
	return "同时在场敌人超过上限 %d" % int(_result_data.get("enemy_cap", 0))


## 结算遮罩：暗底 + 居中面板（标题/说明/两个按钮）。名称固定为 ResultOverlay，供自检断言。
func _build_result_panel() -> void:
	_result_panel = Control.new()
	_result_panel.name = "ResultOverlay"
	_result_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result_panel.mouse_filter = Control.MOUSE_FILTER_STOP # 吞掉场地点击，结算后不再落卡
	var dim := ColorRect.new()
	dim.color = Color(0.09, 0.06, 0.11, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_panel.add_child(dim)
	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_panel.add_child(center)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.add_theme_stylebox_override("panel", UiStyle.panel())
	center.add_child(panel)
	var margin := MarginContainer.new()
	margin.name = "Margin"
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)
	var title := Label.new()
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", UiStyle.COLOR_ACCENT)
	vbox.add_child(title)
	var sub := Label.new()
	sub.name = "Subtitle"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", UiStyle.COLOR_TEXT_DIM)
	vbox.add_child(sub)
	var row := HBoxContainer.new()
	row.name = "Buttons"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	vbox.add_child(row)
	var restart := Button.new()
	restart.name = "Restart"
	restart.text = "重新开始"
	restart.custom_minimum_size = Vector2(140, 44)
	restart.pressed.connect(_on_result_restart)
	row.add_child(restart)
	var to_title := Button.new()
	to_title.name = "ToTitle"
	to_title.text = "返回标题"
	to_title.custom_minimum_size = Vector2(140, 44)
	to_title.pressed.connect(_on_result_to_title)
	row.add_child(to_title)
	add_child(_result_panel)
	_result_panel.visible = false


## 重新开始：关卡 id 经 root meta 回填（Game._ready 会取走），否则重载会退回默认关卡。
func _on_result_restart() -> void:
	var lid := str(_result_data.get("level_id", ""))
	if not lid.is_empty():
		get_tree().root.set_meta("pending_level_id", lid)
	SceneTransition.reload_scene()


func _on_result_to_title() -> void:
	SceneTransition.change_scene("res://scenes/menu.tscn")


## 「返回标题」：面板关闭已解除暂停，这里只负责切场景
func _on_settings_title_requested() -> void:
	SceneTransition.change_scene("res://scenes/menu.tscn")


func _on_selection_cleared() -> void:
	if _overlay != null:
		_overlay.deactivate()
	placement_cancelled.emit()


func _on_overlay_cancelled() -> void:
	if _fusion_enabled:
		_fusion_toggle.button_pressed = false # Esc/右键退出融合模式
		return
	if _hand != null and _hand.get_selected_index() >= 0:
		_hand.clear_selection(true)   # 走 selection_cleared -> placement_cancelled
		return
	if _overlay != null:
		_overlay.deactivate()
	placement_cancelled.emit()


func _on_cell_clicked(cell: Vector2i) -> void:
	if _fusion_enabled:
		factory_cell_clicked.emit(cell)
		return
	var card := get_selected_card()
	if card.is_empty():
		# 没有选中卡却收到格子点击：只收尾，不编造 card_played
		if _overlay != null:
			_overlay.deactivate()
		placement_cancelled.emit()
		return
	if _hand != null:
		_hand.clear_selection(false)   # 静默清理，避免紧接一次多余的 placement_cancelled
	if _overlay != null:
		_overlay.deactivate()
	card_played.emit(card, cell)


func _update_hand_count() -> void:
	if _hand_count == null or _hand == null:
		return
	_hand_count.text = "%d / %d" % [_hand.get_card_count(), _hand.get_hand_max()]
