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
	"res://scripts/ui/line_tool.gd",
	"res://scripts/ui/line_draw_overlay.gd",
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
	"HUD/TopBar/Row/LineTools",
	"HUD/TopBar/Row/LineTools/Pipe",
	"HUD/TopBar/Row/LineTools/Belt",
	"HUD/TopBar/Row/LineTools/Remove",
	"HUD/TopBar/Row/WaveBox/WaveText",
	"HUD/TopBar/Row/WaveBox/WaveBar",
	"HUD/TopBar/Row/EnemyBox/EnemyText",
	"HUD/TopBar/Row/EnemyBox/EnemyBar",
	"RightRail",
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


## 两个 Vector2i 集合是否相同（顺序敏感，笔刷断言钉住去重后的格序）。
func _cells_eq(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		var va = a[i]
		var vb = b[i]
		if Vector2i(va) != Vector2i(vb):
			return false
	return true


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


## 模拟鼠标移动（拖拽画线的 motion 事件）。
func _motion_event(local_pos: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = local_pos
	return event


## 模拟点击一个 toggle 按钮：Godot 点击时先翻转 button_pressed 再发 pressed。
func _click_toggle(btn: Button) -> void:
	btn.button_pressed = not btn.button_pressed
	btn.pressed.emit()


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
	ui.set_resources({"parts": 10, "special": 2, "power": 3, "mystery": 99})
	_check(parts_value.text == "10", "set_resources 零件=10（实际 %s）" % parts_value.text)
	var special_value := ui.get_node("HUD/TopBar/Row/ResourceBar/Special/VBox/Value") as Label
	_check(special_value.text == "2", "set_resources 特殊材料=2（实际 %s）" % special_value.text)

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

	# 10) 卡牌库 / 战报

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

	# 13) DNA 检视预制体：节点解析 / 碱基列 / 座数徽标 / 双螺旋 / 形象区 / 空态
	var dna := (load("res://scenes/ui/dna_inspector.tscn") as PackedScene).instantiate()
	root.add_child(dna)
	dna.set_view({"title": "测试卡", "bases": ["A", "—", "C"], "locus_names": ["甲", "乙", "丙"],
		"rules": ["规则一"], "debug": "raw", "art": ""})
	var dna_chain := dna.get_node("Box/Main/LeftCol/BaseList")
	var dna_count := dna.get_node("Box/Main/HelixCol/Badge/Count") as Label
	_check(dna_chain.get_child_count() == 3, "DNA 碱基列 3 格（实际 %d）" % dna_chain.get_child_count())
	_check(dna_count.text == "2 / 3 座", "DNA 座数徽标（实际 %s）" % dna_count.text)
	_check(dna_chain.get_child(0).text == "A" and dna_chain.get_child(1).text == "—",
		"DNA 碱基列只写字母（%s/%s）" % [dna_chain.get_child(0).text, dna_chain.get_child(1).text])
	var dna_helix := dna.get_node("Box/Main/HelixCol/HelixHost/HelixView")
	_check(dna_helix != null and (dna_helix as Control).size.y > 0, "DNA 双螺旋已构建且有高度")
	_check(not dna.get_node("Box/Main/FigurePanel").visible, "DNA 无 art 时形象区收起")
	dna.set_view({"title": "带图", "bases": ["A"], "locus_names": ["甲"],
		"rules": [], "debug": "", "art": "res://art/art/card/card miner.png"})
	_check(dna.get_node("Box/Main/FigurePanel").visible, "DNA 有 art 时形象区展开")
	dna.set_view({"title": "空", "bases": [], "locus_names": [], "rules": [], "debug": ""})
	_check(not dna.get_node("Box/Main/LeftCol").visible, "DNA 空碱基列整段隐藏")
	_check(not dna.get_node("Box/RulesSection").visible, "DNA 空规则整段隐藏")
	dna.free()

	# 14) 物流工具：资源板移除水/矿、三按钮互斥、拖拽发指令、与卡牌流程互斥
	_check(ui.get_node_or_null("HUD/TopBar/Row/ResourceBar/Water") == null, "资源板已移除水面板")
	_check(ui.get_node_or_null("HUD/TopBar/Row/ResourceBar/Ore") == null, "资源板已移除矿面板")
	var res_bar := ui.get_node("HUD/TopBar/Row/ResourceBar")
	_check(res_bar.get_child_count() == 3, "资源板只剩 3 槽（实际 %d）" % res_bar.get_child_count())

	var line_records: Array = []
	ui.line_committed.connect(func(kind: String, cells: Array, dir: Vector2i):
		line_records.append({"kind": kind, "cells": cells, "dir": dir}))
	var tool_bar := ui.get_node_or_null("HUD/TopBar/Row/LineTools")
	var pipe_btn := ui.get_node_or_null("HUD/TopBar/Row/LineTools/Pipe") as Button
	var belt_btn := ui.get_node_or_null("HUD/TopBar/Row/LineTools/Belt") as Button
	var remove_btn := ui.get_node_or_null("HUD/TopBar/Row/LineTools/Remove") as Button
	var line_layer := ui.get_node_or_null("LineOverlay")
	_check(pipe_btn != null and belt_btn != null and remove_btn != null, "物流三按钮存在（铺管道/铺传送带/拆除）")
	_check(tool_bar != null and tool_bar.get_child_count() == 3, "三按钮同属 LineTools 容器")
	if pipe_btn != null and belt_btn != null and remove_btn != null and line_layer != null:
		_check(pipe_btn.toggle_mode and belt_btn.toggle_mode and remove_btn.toggle_mode, "三按钮为 toggle（互斥选中态）")
		ui.select_line_tool("pipe")
		_check(ui.get_line_tool() == "pipe", "select_line_tool(pipe) 生效（实际 '%s'）" % ui.get_line_tool())
		_check(pipe_btn.button_pressed and not belt_btn.button_pressed and not remove_btn.button_pressed,
			"选中铺管道 → 三按钮互斥")
		_check(line_layer.visible and line_layer.mouse_filter == Control.MOUSE_FILTER_STOP,
			"工具激活 → LineOverlay 拦截鼠标（吞掉格子点击）")
		ui.select_line_tool("belt")
		_check(ui.get_line_tool() == "belt" and belt_btn.button_pressed and not pipe_btn.button_pressed,
			"切到铺传送带 → 上一个按钮自动弹起")
		var drag_cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
		ui.set_grid_geometry(Vector2(20, 30), Vector2i(32, 32), drag_cells)
		line_records.clear()
		line_layer._gui_input(_click_event(MOUSE_BUTTON_LEFT, line_layer.cell_rect(Vector2i(0, 0)).get_center()))
		line_layer._gui_input(_motion_event(line_layer.cell_rect(Vector2i(1, 0)).get_center()))
		line_layer._gui_input(_motion_event(line_layer.cell_rect(Vector2i(2, 0)).get_center()))
		var release := _click_event(MOUSE_BUTTON_LEFT, line_layer.cell_rect(Vector2i(2, 0)).get_center())
		release.pressed = false
		line_layer._gui_input(release)
		_check(line_records.size() == 1, "拖拽松开 → 一次 line_committed（实际 %d）" % line_records.size())
		if line_records.size() == 1:
			var rec: Dictionary = line_records[0]
			_check(str(rec["kind"]) == "belt", "指令 kind=belt（实际 %s）" % str(rec["kind"]))
			_check((rec["cells"] as Array).size() == 3,
				"拖 0,0→2,0 → 3 格（实际 %d）" % (rec["cells"] as Array).size())
			_check(rec["dir"] == Vector2i(1, 0), "指令 dir=(1,0)（实际 %s）" % str(rec["dir"]))
		# 同格拖拽：按下+松开在同一格，方向按按下点→松开点的像素相对位移判定
		line_records.clear()
		var cell0: Rect2 = line_layer.cell_rect(Vector2i(0, 0))
		line_layer._gui_input(_click_event(MOUSE_BUTTON_LEFT, cell0.position + Vector2(4, 16)))
		line_layer._gui_input(_motion_event(cell0.position + Vector2(28, 18)))
		var release_same := _click_event(MOUSE_BUTTON_LEFT, cell0.position + Vector2(28, 18))
		release_same.pressed = false
		line_layer._gui_input(release_same)
		_check(line_records.size() == 1 and (line_records[0]["cells"] as Array).size() == 1
			and line_records[0]["dir"] == Vector2i(1, 0),
			"同格右拖 → 单格 dir=(1,0)（实际 %s）" % str(line_records[0] if line_records.size() == 1 else "无"))
		line_records.clear()
		line_layer._gui_input(_click_event(MOUSE_BUTTON_LEFT, cell0.position + Vector2(16, 4)))
		line_layer._gui_input(_motion_event(cell0.position + Vector2(18, 28)))
		var release_down := _click_event(MOUSE_BUTTON_LEFT, cell0.position + Vector2(18, 28))
		release_down.pressed = false
		line_layer._gui_input(release_down)
		_check(line_records.size() == 1 and line_records[0]["dir"] == Vector2i(0, 1),
			"同格下拖 → 单格 dir=(0,1)（实际 %s）" % str(line_records[0] if line_records.size() == 1 else "无"))
		ui.select_line_tool("remove")
		line_records.clear()
		line_layer._gui_input(_click_event(MOUSE_BUTTON_LEFT, line_layer.cell_rect(Vector2i(0, 0)).get_center()))
		line_layer._gui_input(_motion_event(line_layer.cell_rect(Vector2i(1, 0)).get_center()))
		var release2 := _click_event(MOUSE_BUTTON_LEFT, line_layer.cell_rect(Vector2i(1, 0)).get_center())
		release2.pressed = false
		line_layer._gui_input(release2)
		# 2x2 笔刷：拖过 (0,0)(1,0) → 6 格中只剩网格内的 3 格（本 mock 网格只有 1 行）
		_check(line_records.size() == 1 and str(line_records[0]["kind"]) == "remove"
			and (line_records[0]["cells"] as Array).size() == 3,
			"拆除拖拽 → 2x2 笔刷（mock 网格内 3 格，实际 %d）" % ((line_records[0]["cells"] as Array).size() if line_records.size() == 1 else -1))
		# 2 行网格：笔刷完整展开为 2x2 且不含网格外格
		var two_rows: Array[Vector2i] = []
		for yy in 2:
			for xx in 3:
				two_rows.append(Vector2i(xx, yy))
		ui.set_grid_geometry(Vector2(20, 30), Vector2i(32, 32), two_rows)
		line_records.clear()
		line_layer._gui_input(_click_event(MOUSE_BUTTON_LEFT, line_layer.cell_rect(Vector2i(1, 0)).get_center()))
		var release3 := _click_event(MOUSE_BUTTON_LEFT, line_layer.cell_rect(Vector2i(1, 0)).get_center())
		release3.pressed = false
		line_layer._gui_input(release3)
		_check(line_records.size() == 1 and _cells_eq(line_records[0]["cells"], [Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(2, 1)]),
			"拆除单击 → 2x2 四格（实际 %s）" % str(line_records[0]["cells"] if line_records.size() == 1 else "无"))
		line_records.clear()
		line_layer._gui_input(_click_event(MOUSE_BUTTON_LEFT, line_layer.cell_rect(Vector2i(2, 1)).get_center()))
		var release4 := _click_event(MOUSE_BUTTON_LEFT, line_layer.cell_rect(Vector2i(2, 1)).get_center())
		release4.pressed = false
		line_layer._gui_input(release4)
		_check(line_records.size() == 1 and _cells_eq(line_records[0]["cells"], [Vector2i(2, 1)]),
			"拆除右下角单击 → 笔刷外溢格被过滤只剩自身（实际 %s）" % str(line_records[0]["cells"] if line_records.size() == 1 else "无"))
		ui.set_grid_geometry(Vector2(20, 30), Vector2i(32, 32), drag_cells)
		ui.select_line_tool("remove")
		ui.select_line_tool("remove")
		_check(ui.get_line_tool() == "remove", "select_line_tool 幂等（显式设置，不是 toggle）")
		_click_toggle(remove_btn) # 用户再点一次同一按钮 = 弹起取消
		_check(ui.get_line_tool() == "" and not remove_btn.button_pressed, "再点同一按钮 → 取消选中")
		_check(not line_layer.visible, "取消工具后 LineOverlay 不再拦截鼠标")
		# 与卡牌打出流程互斥（hand 在第 12 段已注入 1 张「卡Z」）
		var card_btns := _hand_buttons(hand)
		ui.select_line_tool("pipe")
		(card_btns[0] as Button).pressed.emit()
		_check(ui.get_line_tool() == "" and not pipe_btn.button_pressed, "选卡 → 工具自动取消（互斥）")
		_check(ui.is_placing(), "工具取消后选卡仍进入放置预览")
		ui.cancel_placement()
		(card_btns[0] as Button).pressed.emit()
		ui.select_line_tool("belt")
		_check(not ui.is_placing() and ui.get_selected_card().is_empty(), "选工具 → 卡牌选择清空（格子点击归工具）")
		ui.select_line_tool("")
		# 工具与融合互斥（融合亮着却被工具接管 → 格子点击无消费方，静默失效）
		var fusion_toggle = ui._fusion_toggle
		_check(fusion_toggle != null, "融合开关已构建（互斥断言用）")
		if fusion_toggle != null:
			fusion_toggle.button_pressed = true
			_check(ui.is_fusion_mode(), "开融合 → is_fusion_mode()==true")
			ui.select_line_tool("pipe")
			_check(not ui.is_fusion_mode() and not fusion_toggle.button_pressed,
				"工具激活 → 融合模式退出（is_fusion_mode()==false 且开关弹起）")
			_check(ui.get_line_tool() == "pipe" and line_layer.visible,
				"融合被工具顶掉后画线层仍接管格子点击")
			ui.select_line_tool("")
		# 左键松开落在网格外：不提交，且拖拽态/预览复位（否则预览线跟着鼠标）
		ui.select_line_tool("belt")
		line_records.clear()
		line_layer._gui_input(_click_event(MOUSE_BUTTON_LEFT, line_layer.cell_rect(Vector2i(1, 0)).get_center()))
		var release_out := _click_event(MOUSE_BUTTON_LEFT, Vector2(4000, 4000))
		release_out.pressed = false
		line_layer._gui_input(release_out)
		_check(line_records.is_empty(), "松手落在网格外 → 不提交指令（实际 %d 条）" % line_records.size())
		_check(not bool(line_layer._dragging), "松手落在网格外 → 拖拽态复位（预览不再跟随鼠标）")
		ui.select_line_tool("")

	_finish()


func _finish() -> void:
	print("SELFTEST: %d checks, %d failed" % [_checks, _fails.size()])
	for failure in _fails:
		print("  FAILED: " + failure)
	quit(0 if _fails.is_empty() else 1)
