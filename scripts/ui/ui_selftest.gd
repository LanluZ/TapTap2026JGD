extends SceneTree
## 关卡 UI 非视觉自检：脚本可加载、场景结构、公开 API、信号流。
## 运行：godot --headless --path <项目目录> -s res://scripts/ui/ui_selftest.gd
## 退出码 0 = 全部通过；1 = 有失败项。不做任何视觉/交互观感结论。

const UI_SCRIPTS: Array[String] = [
	"res://scripts/ui/ui_style.gd",
	"res://scripts/ui/card_face.gd",
	"res://scripts/ui/hud.gd",
	"res://scripts/ui/hand_area.gd",
	"res://scripts/ui/placement_preview.gd",
	"res://scripts/ui/active_cards.gd",
	"res://scripts/ui/card_library.gd",
	"res://scripts/ui/receipt_list.gd",
	"res://scripts/ui/main_ui.gd",
]

const REQUIRED_NODES: Array[String] = [
	"WorldBG",
	"PlacementOverlay",
	"HUD",
	"HUD/TopBar",
	"HUD/TopBar/Row",
	"HUD/TopBar/Row/ResourceBar",
	"HUD/TopBar/Row/ResourceBar/Parts",
	"HUD/TopBar/Row/ResourceBar/Parts/VBox/Name",
	"HUD/TopBar/Row/ResourceBar/Parts/VBox/Value",
	"HUD/TopBar/Row/ResourceBar/Special/VBox/Value",
	"HUD/TopBar/Row/ResourceBar/Power/VBox/Value",
	"HUD/TopBar/Row/ResourceBar/Water/VBox/Value",
	"HUD/TopBar/Row/ResourceBar/Ore/VBox/Value",
	"HUD/TopBar/Row/WaveBox/WaveText",
	"HUD/TopBar/Row/WaveBox/WaveBar",
	"HUD/TopBar/Row/EnemyBox/EnemyText",
	"HUD/TopBar/Row/EnemyBox/EnemyBar",
	"RightRail",
	"RightRail/ActiveCards",
	"RightRail/ActiveCards/VBox/Head/Count",
	"RightRail/ActiveCards/VBox/Slots",
	"RightRail/CardLibrary",
	"RightRail/CardLibrary/VBox/Head/Toggle",
	"RightRail/CardLibrary/VBox/Body/List",
	"RightRail/Receipts",
	"RightRail/Receipts/VBox/Body/List",
	"HandPanel",
	"HandPanel/VBox/Head/Count",
	"HandPanel/VBox/HandArea",
]

var _checks := 0
var _fails: Array[String] = []
var _selected: Dictionary = {}
var _played: Dictionary = {}
var _cancelled := false


func _init() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("ok   | " + label)
	else:
		_fails.append(label)
		print("FAIL | " + label)


func _on_selected(card: Dictionary) -> void:
	_selected = card


func _on_played(card: Dictionary, cell: Vector2i) -> void:
	_played = {"card": card, "cell": cell}


func _on_cancelled() -> void:
	_cancelled = true


func _hand_buttons(hand: Node) -> Array:
	var out: Array = []
	for child in hand.get_children():
		if child is Button:
			out.append(child)
	return out


func _click_event(button_index: MouseButton, local_pos: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	event.pressed = true
	event.position = local_pos
	return event


func _run() -> void:
	# 1) 脚本可解析 / 可实例化
	for path in UI_SCRIPTS:
		var script = load(path)
		_check(script != null, "脚本可加载: " + path)
		if script != null:
			_check(script is GDScript and (script as GDScript).can_instantiate(),
				"脚本可实例化: " + path)

	# 2) 场景可加载 / 可实例化
	var packed = load("res://scenes/main.tscn")
	_check(packed != null and packed is PackedScene, "main.tscn 可加载")
	if packed == null or not (packed is PackedScene):
		_finish()
		return
	var ui := (packed as PackedScene).instantiate()
	_check(ui != null, "main.tscn 可实例化")
	if ui == null:
		_finish()
		return
	root.add_child(ui)

	# 3) 必需节点齐全
	for path in REQUIRED_NODES:
		_check(ui.get_node_or_null(path) != null, "节点存在: " + path)

	# 4) 演示假数据（auto_mock 默认开）
	var wave_text := ui.get_node("HUD/TopBar/Row/WaveBox/WaveText") as Label
	var enemy_text := ui.get_node("HUD/TopBar/Row/EnemyBox/EnemyText") as Label
	var parts_value := ui.get_node("HUD/TopBar/Row/ResourceBar/Parts/VBox/Value") as Label
	var hand_count := ui.get_node("HandPanel/VBox/Head/Count") as Label
	var hand := ui.get_node("HandPanel/VBox/HandArea")
	var overlay := ui.get_node("PlacementOverlay")
	_check(wave_text.text == "波次 7 / 15", "auto_mock 波次占位（实际 %s）" % wave_text.text)
	_check(enemy_text.text == "路径敌人 13 / 20", "auto_mock 敌人数占位（实际 %s）" % enemy_text.text)
	_check(parts_value.text == "246", "auto_mock 资源占位（实际 %s）" % parts_value.text)
	_check(hand.get_child_count() == 7, "auto_mock 手牌槽位 7（实际 %d）" % hand.get_child_count())

	# 5) HUD 注入
	ui.set_resources({"parts": 10, "special": 2, "power": 3, "water": 4, "ore": 5, "mystery": 99})
	_check(parts_value.text == "10", "set_resources 零件=10（实际 %s）" % parts_value.text)
	var special_value := ui.get_node("HUD/TopBar/Row/ResourceBar/Special/VBox/Value") as Label
	_check(special_value.text == "2", "set_resources 特殊材料=2（实际 %s）" % special_value.text)
	var ore_value := ui.get_node("HUD/TopBar/Row/ResourceBar/Ore/VBox/Value") as Label
	_check(ore_value.text == "5", "set_resources 矿=5（实际 %s）" % ore_value.text)

	ui.set_wave_info(3, 12)
	_check(wave_text.text == "波次 3 / 12", "set_wave_info 文本（实际 %s）" % wave_text.text)
	var wave_bar := ui.get_node("HUD/TopBar/Row/WaveBox/WaveBar") as ProgressBar
	_check(wave_bar.max_value == 12.0 and wave_bar.value == 3.0,
		"set_wave_info 进度条 max=12 value=3（实际 %s/%s）" % [wave_bar.max_value, wave_bar.value])

	ui.set_enemy_count(5, 20)
	_check(enemy_text.text == "路径敌人 5 / 20", "set_enemy_count 文本（实际 %s）" % enemy_text.text)
	var enemy_bar := ui.get_node("HUD/TopBar/Row/EnemyBox/EnemyBar") as ProgressBar
	_check(enemy_bar.max_value == 20.0 and enemy_bar.value == 5.0,
		"set_enemy_count 进度条 max=20 value=5（实际 %s/%s）" % [enemy_bar.max_value, enemy_bar.value])

	# 6) 手牌注入
	ui.set_hand_max(6)
	_check(ui.get_hand_max() == 6, "set_hand_max 生效（实际 %d）" % ui.get_hand_max())
	ui.set_hand([{"id": "a", "name": "卡A", "kind": "factory", "icon": "⚙"},
		{"id": "b", "name": "卡B", "kind": "tile", "icon": "🛣"},
		{"id": "c", "name": "卡C", "kind": "tile", "icon": "🔀"}])
	_check(hand.get_child_count() == 6, "手牌槽位=6（实际 %d）" % hand.get_child_count())
	_check(hand_count.text == "3 / 6", "手牌计数 3 / 6（实际 %s）" % hand_count.text)
	_check(ui.get_hand().size() == 3, "get_hand 返回 3 张")
	var buttons := _hand_buttons(hand)
	_check(buttons.size() == 6, "手牌按钮数=6（实际 %d）" % buttons.size())
	if buttons.size() == 6:
		_check((buttons[5] as Button).disabled, "空槽位按钮为禁用态")

	# 7) 选中 → 放置预览
	ui.card_selected.connect(_on_selected)
	ui.card_played.connect(_on_played)
	ui.placement_cancelled.connect(_on_cancelled)
	if buttons.size() >= 3:
		(buttons[0] as Button).pressed.emit()
		_check(_selected.get("name", "") == "卡A", "card_selected 携带选中卡（实际 %s）" % str(_selected.get("name", "")))
		_check(ui.is_placing(), "选中卡牌后进入放置预览状态")
		_check(overlay.mouse_filter == Control.MOUSE_FILTER_STOP, "激活时 overlay 拦截鼠标")
		_check(overlay.visible, "激活时 overlay 可见")
		_check(ui.get_selected_card().get("id", "") == "a", "get_selected_card 返回选中卡")

		# 8) 合法 / 非法格点击
		var typed_valid: Array[Vector2i] = [Vector2i(4, 1), Vector2i(5, 1)]
		ui.set_placement_preview(typed_valid)
		_check(overlay.get_valid_cells().size() == 2, "类型化 Array[Vector2i] 注入成功（实际 %d）" % overlay.get_valid_cells().size())
		ui.set_placement_preview([Vector2i(6, 1), Vector2(7, 1)])
		_check(overlay.get_valid_cells().size() == 2, "未类型化 Array/混入 Vector2 也接受（实际 %d）" % overlay.get_valid_cells().size())

		var valid_cell := Vector2i(6, 1)
		overlay._gui_input(_click_event(MOUSE_BUTTON_LEFT, overlay.cell_rect(valid_cell).get_center()))
		_check(not _played.is_empty(), "点击合法格触发 card_played")
		_check(_played.get("cell") == valid_cell, "card_played 坐标正确（实际 %s）" % str(_played.get("cell")))
		_check(str(_played.get("card", {}).get("id", "")) == "a", "card_played 携带选中卡")
		_check(not ui.is_placing(), "打出后退出放置状态")
		_check(not _cancelled, "打出卡牌不触发 placement_cancelled")

		_played = {}
		_selected = {}
		(buttons[1] as Button).pressed.emit()
		_check(ui.is_placing(), "重新选中卡牌进入放置状态")
		var invalid_cell := Vector2i(0, 0)
		_check(not overlay.get_valid_cells().has(invalid_cell), "格 (0,0) 不在合法集合内")
		overlay._gui_input(_click_event(MOUSE_BUTTON_LEFT, overlay.cell_rect(invalid_cell).get_center()))
		_check(_played.is_empty(), "非法格不触发 card_played")
		_check(ui.is_placing(), "非法格点击后仍处于放置状态")

		# 9) 取消路径：Esc / 右键 / 再次点击 / cancel_placement
		_cancelled = false
		var esc := InputEventKey.new()
		esc.keycode = KEY_ESCAPE
		esc.pressed = true
		overlay._unhandled_input(esc)
		_check(_cancelled, "Esc 触发 placement_cancelled")
		_check(not ui.is_placing(), "Esc 后退出放置状态")

		_cancelled = false
		(buttons[2] as Button).pressed.emit()
		overlay._gui_input(_click_event(MOUSE_BUTTON_RIGHT, Vector2.ZERO))
		_check(_cancelled and not ui.is_placing(), "右键触发 placement_cancelled")

		_cancelled = false
		(buttons[2] as Button).pressed.emit()
		_check(ui.is_placing(), "再次选中卡牌进入放置状态")
		(buttons[2] as Button).pressed.emit()
		_check(_cancelled and not ui.is_placing(), "再次点击已选卡触发 placement_cancelled")

		_cancelled = false
		(buttons[0] as Button).pressed.emit()
		ui.cancel_placement()
		_check(_cancelled and not ui.is_placing(), "cancel_placement 取消放置")

	# 10) 生效中卡牌 / 卡牌库 / 战报
	ui.set_active_cards([{"name": "甲", "kind": "factory", "icon": "📦"}, {"name": "乙", "kind": "tile", "icon": "🛣"}])
	var active_slots := ui.get_node("RightRail/ActiveCards/VBox/Slots")
	var active_count := ui.get_node("RightRail/ActiveCards/VBox/Head/Count") as Label
	_check(active_slots.get_child_count() == 3, "生效中卡牌槽位=3（实际 %d）" % active_slots.get_child_count())
	_check(active_count.text == "2 / 3", "生效中卡牌计数（实际 %s）" % active_count.text)
	ui.set_active_slot_count(5)
	_check(active_slots.get_child_count() == 5, "set_active_slot_count 生效（实际 %d）" % active_slots.get_child_count())

	ui.set_library_cards([{"name": "L1", "kind": "factory"}, {"name": "L2", "kind": "tile"},
		{"name": "L3", "kind": "factory"}, {"name": "L4", "kind": "tile"}])
	var library_list := ui.get_node("RightRail/CardLibrary/VBox/Body/List")
	_check(library_list.get_child_count() == 4, "卡牌库列表 4 行（实际 %d）" % library_list.get_child_count())
	var library_body := ui.get_node("RightRail/CardLibrary/VBox/Body")
	var library_toggle := ui.get_node("RightRail/CardLibrary/VBox/Head/Toggle") as Button
	ui.set_library_expanded(false)
	_check(not library_body.visible, "set_library_expanded(false) 隐藏列表")
	_check(library_toggle.text == "展开", "收起后按钮文案=展开（实际 %s）" % library_toggle.text)
	ui.set_library_expanded(true)
	_check(library_body.visible, "set_library_expanded(true) 显示列表")

	ui.set_receipts(["纯文本项", {"icon": "!", "text": "字典项"}])
	var receipt_list := ui.get_node("RightRail/Receipts/VBox/Body/List")
	_check(receipt_list.get_child_count() == 2, "战报 2 行（实际 %d）" % receipt_list.get_child_count())

	# 11) 网格几何替换 mock
	ui.set_grid_geometry(Vector2(20, 30), Vector2i(32, 32),
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
	_check(overlay.get_all_cells().size() == 3, "set_grid_geometry 覆盖 mock 网格（实际 %d）" % overlay.get_all_cells().size())
	ui.set_placement_preview([Vector2i(1, 0)])
	_check(overlay.get_valid_cells().size() == 1, "合法格跟随新几何（实际 %d）" % overlay.get_valid_cells().size())
	_check(overlay.cell_rect(Vector2i(2, 0)).get_center().distance_to(Vector2(100, 46)) < 0.01,
		"cell_rect 坐标换算（原点20,30 + 32px 格 → 中心 100,46）")

	# 12) 容错：非法卡牌项被跳过
	ui.set_hand([123, {"id": "z", "name": "卡Z", "kind": "factory"}])
	_check(ui.get_hand().size() == 1, "set_hand 跳过非法项（实际 %d）" % ui.get_hand().size())
	_check(hand.get_child_count() == 6, "跳过非法项后槽位仍为 6（实际 %d）" % hand.get_child_count())
	_check(hand_count.text == "1 / 6", "跳过非法项后计数 1 / 6（实际 %s）" % hand_count.text)
	ui.set_active_cards(["not-a-card"])
	_check(active_slots.get_child_count() == 5, "生效中卡牌过滤非法项后仍为 5 槽（实际 %d）" % active_slots.get_child_count())
	_check(active_count.text == "0 / 5", "生效中卡牌计数归零（实际 %s）" % active_count.text)

	# 13) DNA 检视预制体：节点解析 / 碱基链 / 座数徽标 / 空态
	var dna := (load("res://scenes/ui/dna_inspector.tscn") as PackedScene).instantiate()
	root.add_child(dna)
	dna.set_view({"title": "测试卡", "bases": ["A", "—", "C"], "locus_names": ["甲", "乙", "丙"],
		"rules": ["规则一"], "debug": "raw"})
	var dna_chain := dna.get_node("Box/ChainSection/ChainBox/Scroll/Chain")
	var dna_count := dna.get_node("Box/Header/LociBadge/Count") as Label
	_check(dna_chain.get_child_count() == 3, "DNA 碱基链 3 格（实际 %d）" % dna_chain.get_child_count())
	_check(dna_count.text == "2 / 3 座", "DNA 座数徽标（实际 %s）" % dna_count.text)
	_check(dna_chain.get_child(0).get_child(2).get_child(0).text == "T", "DNA 互补碱基 A→T")
	dna.set_view({"title": "空", "bases": [], "locus_names": [], "rules": [], "debug": ""})
	_check(not dna.get_node("Box/ChainSection").visible, "DNA 空碱基链整段隐藏")
	_check(not dna.get_node("Box/RulesSection").visible, "DNA 空规则整段隐藏")
	dna.free()

	_finish()


func _finish() -> void:
	print("SELFTEST: %d checks, %d failed" % [_checks, _fails.size()])
	for failure in _fails:
		print("  FAILED: " + failure)
	quit(0 if _fails.is_empty() else 1)
