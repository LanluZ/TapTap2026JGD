extends Control
## 放置预览层：选中卡牌后高亮可放/不可放格子。
##  - 点击合法格 → cell_clicked（由根节点转成 card_played）
##  - 点击非法格 / 网格外 → 只做视觉反馈，不发信号（合法性最终由逻辑层裁决）
##  - 右键 / Esc → cancelled
## 网格数据未就绪时用内置 mock 网格自展示，不引用逻辑层任何类型。

signal cell_clicked(cell: Vector2i)
signal cancelled()

const MOCK_ORIGIN := Vector2(48, 72)
const MOCK_CELL_SIZE := Vector2i(48, 48)
const MOCK_GRID := Vector2i(16, 8)
## mock 环形路径的外接矩形（格坐标）：路径 = 该矩形边框
const MOCK_PATH_RECT := Rect2i(3, 1, 10, 6)

const COLOR_GRID_LINE := Color(0.580, 0.482, 0.639, 0.35)  # 色板 BORDER
const COLOR_VALID_FILL := Color(0.741, 0.878, 0.996, 0.18)  # Icy Blue
const COLOR_VALID_LINE := Color(0.741, 0.878, 0.996, 0.95)
const COLOR_BLOCKED_FILL := Color(1.0, 0.686, 0.8, 0.18)   # Blush Pop
const COLOR_BLOCKED_LINE := Color(1.0, 0.686, 0.8, 0.85)
const COLOR_HOVER := Color(1.0, 0.784, 0.867, 1.0)         # Pastel Petal

var _origin: Vector2 = MOCK_ORIGIN
var _cell_size: Vector2i = MOCK_CELL_SIZE
var _all_cells: Dictionary = {}    # Vector2i -> true
var _valid: Dictionary = {}        # Vector2i -> true
var _active := false
var _card_kind := ""
var _hover := Vector2i(-1, -1)
var _has_hover := false
var _geometry_from_caller := false
var _valid_from_caller := false
var _ensure_attempted := false


func _ready() -> void:
	_ensure_ready()


func _ensure_ready() -> void:
	if _ensure_attempted:
		return
	_ensure_attempted = true
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)
	if not _geometry_from_caller:
		_load_mock_grid()
	_apply_input_mode()


## 网格几何：原点（本控件局部坐标）、单格尺寸、全部格子
func set_grid_geometry(origin: Vector2, cell_size: Vector2i, cells: Array) -> void:
	_ensure_ready()
	_geometry_from_caller = true
	_origin = origin
	if cell_size.x > 0 and cell_size.y > 0:
		_cell_size = cell_size
	_all_cells.clear()
	_add_cells(cells, _all_cells, "网格")
	queue_redraw()


## 可放格子集合（元素为 Vector2i；兼容未类型化 Array 与 Vector2）
func set_valid_cells(cells: Array) -> void:
	_ensure_ready()
	_valid_from_caller = true
	_valid.clear()
	_add_cells(cells, _valid, "可放格")
	queue_redraw()


func get_all_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell in _all_cells:
		out.append(cell)
	return out


func get_valid_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell in _valid:
		out.append(cell)
	return out


## 进入放置预览（card_kind 仅作内部标记，便于调试）
func activate(card_kind: String = "") -> void:
	_ensure_ready()
	_active = true
	_card_kind = card_kind
	_apply_input_mode()
	queue_redraw()


func deactivate() -> void:
	_active = false
	_card_kind = ""
	_has_hover = false
	_hover = Vector2i(-1, -1)
	_apply_input_mode()
	queue_redraw()


func is_active() -> bool:
	return _active


func get_card_kind() -> String:
	return _card_kind


func cell_at(local_pos: Vector2) -> Vector2i:
	if _cell_size.x <= 0 or _cell_size.y <= 0:
		return Vector2i(-1, -1)
	var x := floori((local_pos.x - _origin.x) / float(_cell_size.x))
	var y := floori((local_pos.y - _origin.y) / float(_cell_size.y))
	return Vector2i(x, y)


## 当前悬停格（放置态之外 → (-1,-1)）：上层放置幽灵跟随鼠标用，是否可放由调用方判。
func get_hover() -> Vector2i:
	return _hover if (_active and _has_hover) else Vector2i(-1, -1)


func cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(_origin + Vector2(cell * _cell_size), Vector2(_cell_size))


func _gui_input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventMouseMotion:
		var cell := cell_at(event.position)
		if not _has_hover or cell != _hover:
			_hover = cell
			_has_hover = true
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var cell := cell_at(event.position)
			if _all_cells.has(cell):
				if _valid.has(cell):
					cell_clicked.emit(cell)
				else:
					_hover = cell
					_has_hover = true
					queue_redraw()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			cancelled.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancelled.emit()
		get_viewport().set_input_as_handled()


func _on_mouse_exited() -> void:
	if _has_hover:
		_has_hover = false
		_hover = Vector2i(-1, -1)
		queue_redraw()


func _draw() -> void:
	if not _active:
		return
	for cell in _all_cells:
		draw_rect(cell_rect(cell), COLOR_GRID_LINE, false, 1.0)
	for cell in _valid:
		if not _all_cells.has(cell):
			continue
		var rect := cell_rect(cell)
		draw_rect(rect, COLOR_VALID_FILL, true)
		draw_rect(rect, COLOR_VALID_LINE, false, 1.5)
	for cell in _all_cells:
		if _valid.has(cell):
			continue
		var rect := cell_rect(cell)
		draw_rect(rect, COLOR_BLOCKED_FILL, true)
		draw_rect(rect, COLOR_BLOCKED_LINE, false, 1.0)
	if _has_hover and _all_cells.has(_hover):
		var rect := cell_rect(_hover)
		if _valid.has(_hover):
			draw_rect(rect, COLOR_HOVER, false, 2.0)
		else:
			draw_rect(rect, COLOR_BLOCKED_FILL, true)
			draw_rect(rect, COLOR_BLOCKED_LINE, false, 2.0)


func _apply_input_mode() -> void:
	# 未激活时不拦截鼠标，让点击穿透到下层
	mouse_filter = Control.MOUSE_FILTER_STOP if _active else Control.MOUSE_FILTER_IGNORE
	visible = _active


func _add_cells(cells: Array, target: Dictionary, what: String) -> void:
	for cell in cells:
		if cell is Vector2i:
			target[cell] = true
		elif cell is Vector2:
			target[Vector2i(cell)] = true
		else:
			push_warning("[放置预览] %s 中的非法坐标项已跳过：%s" % [what, str(cell)])


## 内置 mock 网格：16×8，路径为矩形环，可放 = 与路径四邻接且不在路径上
func _load_mock_grid() -> void:
	_geometry_from_caller = true
	_origin = MOCK_ORIGIN
	_cell_size = MOCK_CELL_SIZE
	_all_cells.clear()
	for y in MOCK_GRID.y:
		for x in MOCK_GRID.x:
			_all_cells[Vector2i(x, y)] = true
	if _valid_from_caller:
		return
	_valid.clear()
	var directions := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for cell in _all_cells:
		if _on_mock_path(cell):
			continue
		for direction in directions:
			if _on_mock_path(cell + direction):
				_valid[cell] = true
				break


func _on_mock_path(cell: Vector2i) -> bool:
	var rect := MOCK_PATH_RECT
	var x0 := rect.position.x
	var y0 := rect.position.y
	var x1 := rect.position.x + rect.size.x - 1
	var y1 := rect.position.y + rect.size.y - 1
	if cell.x < x0 or cell.x > x1 or cell.y < y0 or cell.y > y1:
		return false
	return cell.x == x0 or cell.x == x1 or cell.y == y0 or cell.y == y1
