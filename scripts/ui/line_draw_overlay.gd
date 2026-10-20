extends Control
## 拖拽画线交互层（任务 7）：选中物流工具后接管场地鼠标，按住→拖→松开发一条指令。
##
## 职责边界：本层只做「指针 → 格集 + 方向」的几何与预览，不碰逻辑层、不校验合法性
## （校验以指令层 command_rejected 为准）。指令由 main_ui.gd 转成信号，接线层 push。
##
## 坐标：与 PlacementOverlay 同为全屏 Control、几何由 main_ui.set_grid_geometry 注入，
## 因此两者 cell_rect 完全一致，画线与卡牌预览不会各算一套。
##
## 交互：左键按下记锚点 → 移动更新终点 → 松开提交（单轴直链，见 line_tool.gd）；
## 右键 / Esc 取消（不提交）。同格按下+松开 = 单格：方向按按下点→松开点的像素
## 相对位移判定（pixel_dir）；纯点击（位移 < deadzone）回退上次拖拽方向（默认向右）。
## 拆除工具：提交与预览都按 2x2 笔刷扩展（指针格 + 右/下/右下），方便大范围擦除。

signal line_committed(kind: String, cells: Array, dir: Vector2i)
signal cancelled()

const LineToolScript = preload("res://scripts/ui/line_tool.gd")

const KIND_PIPE := "pipe"
const KIND_BELT := "belt"
const KIND_REMOVE := "remove"
const KINDS := [KIND_PIPE, KIND_BELT, KIND_REMOVE]

const COLOR_PIPE := Color(0.635, 0.824, 1.0, 1.0)   # Sky Blue
const COLOR_BELT := Color(0.804, 0.706, 0.859, 1.0) # Pink Orchid
const COLOR_REMOVE := Color(1.0, 0.686, 0.8, 1.0)   # Blush Pop

var _origin: Vector2 = Vector2.ZERO
var _cell_size: Vector2i = Vector2i(48, 48)
var _all_cells: Dictionary = {} # Vector2i -> true
var _kind := ""
var _dragging := false
var _anchor := Vector2i(-1, -1)
var _cursor := Vector2i(-1, -1)
var _last_dir := Vector2i(1, 0) # 纯点击的方向回退
var _press_pos := Vector2.ZERO # 按下点（本控件局部像素，单格判向用）
var _cursor_pos := Vector2.ZERO # 拖拽中/松开时的指针位置（本控件局部像素）


func _ready() -> void:
	_apply_input_mode()


## 网格几何：原点（本控件局部坐标）、单格尺寸、全部格子（与放置预览同签名）。
func set_grid_geometry(origin: Vector2, cell_size: Vector2i, cells: Array) -> void:
	_origin = origin
	if cell_size.x > 0 and cell_size.y > 0:
		_cell_size = cell_size
	_all_cells.clear()
	for cell in cells:
		if cell is Vector2i:
			_all_cells[cell] = true
		elif cell is Vector2:
			_all_cells[Vector2i(cell)] = true
	queue_redraw()


## 进入某工具（pipe / belt / remove）。空串之外的未知值只警告不激活。
func activate(kind: String) -> void:
	if not KINDS.has(kind):
		push_warning("[画线层] 未知工具: " + kind)
		return
	_kind = kind
	_dragging = false
	_anchor = Vector2i(-1, -1)
	_cursor = Vector2i(-1, -1)
	_apply_input_mode()
	queue_redraw()


func deactivate() -> void:
	_kind = ""
	_dragging = false
	_anchor = Vector2i(-1, -1)
	_cursor = Vector2i(-1, -1)
	_apply_input_mode()
	queue_redraw()


func is_active() -> bool:
	return not _kind.is_empty()


func get_kind() -> String:
	return _kind


func cell_at(local_pos: Vector2) -> Vector2i:
	if _cell_size.x <= 0 or _cell_size.y <= 0:
		return Vector2i(-1, -1)
	var x := floori((local_pos.x - _origin.x) / float(_cell_size.x))
	var y := floori((local_pos.y - _origin.y) / float(_cell_size.y))
	return Vector2i(x, y)


func cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(_origin + Vector2(cell * _cell_size), Vector2(_cell_size))


## 只留网格内的格（2x2 笔刷在右/下边缘会外溢，提交与预览共用此过滤）。
func _on_grid(cells: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in cells:
		if _all_cells.has(c):
			out.append(c)
	return out


func _gui_input(event: InputEvent) -> void:
	if not is_active():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_cancel()
			accept_event()
			return
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		var cell := cell_at(mb.position)
		if mb.pressed:
			if not _all_cells.has(cell):
				accept_event()
				return # 网格外按下：只吞掉，不记锚点（不伪造坐标）
			_dragging = true
			_anchor = cell
			_cursor = cell
			_press_pos = mb.position
			_cursor_pos = mb.position
			queue_redraw()
			accept_event()
			return
		# 松开：任何路径都先复位拖拽态与预览，再决定是否提交。
		# （松手点落不到网格时提前 return 会把预览线留给鼠标跟踪，直到下次按下/Esc）
		if not _dragging:
			return
		if not _all_cells.has(cell):
			_dragging = false
			_anchor = Vector2i(-1, -1)
			_cursor = Vector2i(-1, -1)
			queue_redraw()
			accept_event()
			return
		_cursor = cell
		_cursor_pos = mb.position
		_commit()
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_cursor_pos = (event as InputEventMouseMotion).position
		var cell := cell_at(_cursor_pos)
		if _all_cells.has(cell) and cell != _cursor:
			_cursor = cell
			queue_redraw()
		elif cell == _anchor:
			queue_redraw() # 同格内移动：像素判向的预览箭头要跟手


func _unhandled_input(event: InputEvent) -> void:
	if not is_active():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_cancel()
		get_viewport().set_input_as_handled()


## 松手提交：格集 + 单一方向。拆除不需要方向（ZERO），
## 且按 2x2 笔刷扩展（指针格 + 右/下/右下），越界格过滤掉。
func _commit() -> void:
	var a := _anchor
	var b := _cursor
	_dragging = false
	_anchor = Vector2i(-1, -1)
	_cursor = Vector2i(-1, -1)
	if not _all_cells.has(a) or not _all_cells.has(b):
		queue_redraw()
		return
	var cells: Array = LineToolScript.line_cells(a, b)
	var dir: Vector2i = LineToolScript.line_dir(a, b)
	if _kind == KIND_REMOVE:
		dir = Vector2i.ZERO
		cells = _on_grid(LineToolScript.brush_2x2(cells))
	elif dir == Vector2i.ZERO:
		# 同格单格：方向 = 按下点→松开点的像素相对位移；纯点击回退上次方向
		dir = LineToolScript.pixel_dir(_press_pos, _cursor_pos)
		if dir == Vector2i.ZERO:
			dir = _last_dir
	if dir != Vector2i.ZERO:
		_last_dir = dir
	queue_redraw()
	line_committed.emit(_kind, cells, dir)


func _cancel() -> void:
	deactivate()
	cancelled.emit()


func _apply_input_mode() -> void:
	# 未激活时不拦截鼠标，让点击穿透到下层（卡牌放置/工厂点选照常）
	mouse_filter = Control.MOUSE_FILTER_STOP if is_active() else Control.MOUSE_FILTER_IGNORE
	visible = is_active()


func _color() -> Color:
	match _kind:
		KIND_PIPE:
			return COLOR_PIPE
		KIND_BELT:
			return COLOR_BELT
		KIND_REMOVE:
			return COLOR_REMOVE
	return COLOR_PIPE


func _draw() -> void:
	if not is_active():
		return
	if not (_dragging and _all_cells.has(_anchor) and _all_cells.has(_cursor)):
		return
	var cells: Array = LineToolScript.line_cells(_anchor, _cursor)
	if _kind == KIND_REMOVE:
		cells = _on_grid(LineToolScript.brush_2x2(cells)) # 拆除预览 = 2x2 笔刷实际作用域
	var col := _color()
	for c in cells:
		var rect := cell_rect(c)
		draw_rect(rect, Color(col, 0.20), true)
		draw_rect(rect, Color(col, 0.95), false, 2.0)
	var dir: Vector2i = LineToolScript.line_dir(_anchor, _cursor)
	if dir == Vector2i.ZERO and cells.size() == 1:
		# 同格拖拽预览：与 _commit 的 pixel_dir 判定保持一致（拆除不画方向）
		dir = Vector2i.ZERO if _kind == KIND_REMOVE else LineToolScript.pixel_dir(_press_pos, _cursor_pos)
	if dir != Vector2i.ZERO and cells.size() >= 1:
		# 预览箭头：方向 = 松开后写进整条线的 line_dir（反向拖时箭头跟着翻）
		var start: Vector2 = cell_rect(cells[0]).get_center()
		var end: Vector2
		if cells.size() > 1:
			end = cell_rect(cells[cells.size() - 1]).get_center()
		else:
			end = start + Vector2(dir) * float(_cell_size.x) * 0.5 # 单格：箭头伸出半格
		draw_line(start, end, Color(col, 0.85), 3.0)
		var d := Vector2(dir)
		var side := Vector2(-d.y, d.x) * float(_cell_size.x) * 0.18
		draw_colored_polygon(PackedVector2Array([end, end - d * 18.0 + side, end - d * 18.0 - side]), col)
