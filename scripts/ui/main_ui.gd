extends Control
## 关卡 UI 根节点：HUD + 手牌 + 放置预览 + 生效中卡牌/卡牌库/战报。
##
## 对外契约（逻辑层接线只依赖这里）：
##   公开方法：set_resources / set_hand / set_hand_max / set_wave_info /
##             set_enemy_count / set_placement_preview / set_grid_geometry /
##             set_active_cards / set_library_cards / set_library_expanded /
##             set_receipts / cancel_placement / get_selected_card / is_placing /
##             get_hand / load_mock_data
##   信号：card_selected(card)、card_played(card, cell)、placement_cancelled()
##
## 数据全部由调用方注入；本脚本只做展示与交互状态，不引用
## scripts/ecs/、scripts/systems/、scripts/config/ 下任何内容。

signal card_selected(card: Dictionary)
signal card_played(card: Dictionary, cell: Vector2i)
signal placement_cancelled()
signal fusion_toggled(enabled: bool) # 融合模式开关（DNA 系统）
signal fusion_confirmed(seed: int) # 融合确定（种子，0 = 随机）
signal factory_cell_clicked(cell: Vector2i) # 融合模式下点选工厂所在格

const HudScript = preload("res://scripts/ui/hud.gd")
const HandScript = preload("res://scripts/ui/hand_area.gd")
const OverlayScript = preload("res://scripts/ui/placement_preview.gd")
const ActiveCardsScript = preload("res://scripts/ui/active_cards.gd")
const LibraryScript = preload("res://scripts/ui/card_library.gd")
const ReceiptsScript = preload("res://scripts/ui/receipt_list.gd")
const DnaInspectorScene = preload("res://scenes/ui/dna_inspector.tscn")

## true 时在 _ready 里灌入演示假数据（便于 UI 单独自展示）；
## 调用方只要在 ready 前/后调用过任意 setter，演示数据即让位。
@export var auto_mock: bool = true

var _hud: HudScript
var _hand: HandScript
var _overlay: OverlayScript
var _active_cards: ActiveCardsScript
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
	_active_cards = get_node_or_null("RightRail/ActiveCards") as ActiveCardsScript
	_library = get_node_or_null("RightRail/CardLibrary") as LibraryScript
	_receipts = get_node_or_null("RightRail/Receipts") as ReceiptsScript
	_hand_count = get_node_or_null("HandPanel/VBox/Head/Count") as Label
	if _hud == null or _hand == null or _overlay == null:
		if not _structure_warned:
			_structure_warned = true
			push_error("[关卡UI] 场景缺少必需节点或脚本（HUD / HandPanel/VBox/HandArea / PlacementOverlay），检查 main.tscn")
		return
	_nodes_ready = true
	_build_fusion_panel()
	_build_dna_popup()


## DNA 检视弹窗（程序化构建）：内嵌 dna_inspector 预制体；关闭按钮/Esc/再右键收起。
func _build_dna_popup() -> void:
	if _dna_popup != null:
		return
	_dna_popup = PanelContainer.new()
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
	_fusion_panel.offset_top = 56.0


func _connect_signals() -> void:
	if not _nodes_ready or _signals_ready:
		return
	_hand.card_selected.connect(_on_card_selected)
	_hand.selection_cleared.connect(_on_selection_cleared)
	_hand.card_right_clicked.connect(_on_card_right_clicked)
	_overlay.cell_clicked.connect(_on_cell_clicked)
	_overlay.cancelled.connect(_on_overlay_cancelled)
	_signals_ready = true


# ---------------------------------------------------------------- 公开 API

## 资源条数值注入：{"parts","special","power","water","ore"} -> 数值
func set_resources(resources: Dictionary) -> void:
	_prepare()
	_external_data = true
	if _hud != null:
		_hud.set_resources(resources)


## 手牌注入：元素为卡牌 Dictionary{id,name,kind,icon,desc}
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


## 生效中卡牌
func set_active_cards(cards: Array) -> void:
	_prepare()
	_external_data = true
	if _active_cards != null:
		_active_cards.set_cards(cards)


func set_active_slot_count(count: int) -> void:
	_prepare()
	if _active_cards != null:
		_active_cards.set_slot_count(count)


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


func get_hand() -> Array:
	_prepare()
	return _hand.get_cards() if _hand != null else []


func get_hand_max() -> int:
	_prepare()
	return _hand.get_hand_max() if _hand != null else 0


## 演示假数据（仅 UI 自展示用，全部可被上层 setter 覆盖）
func load_mock_data() -> void:
	_prepare()
	set_resources({"parts": 246, "special": 3, "power": 38, "water": 12, "ore": 67})
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
	set_active_cards([{"id": "mock_supply", "name": "补给线", "kind": "factory", "icon": "📦"}])
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


func _on_card_selected(card: Dictionary) -> void:
	hide_dna()
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
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		hide_dna()


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
