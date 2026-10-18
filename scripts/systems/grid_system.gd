class_name GridSystem
extends System
## #4 建造合法性校验（§5）：格子占用、与路径关系。
## 可建造性由关卡标注（§6 path_cells/buildable_cells），本系统提供同步校验
## API 供 CommandSystem（#1）即时调用；每帧另做占用一致性清扫。

## 工厂放置：格子存在、关卡标注可建造、无占用。
func can_build(world, cell: Vector2i) -> bool:
	if world.grid == null:
		return false
	return world.grid.is_buildable(cell)


## 地块放置（§7）：地块属于路面规则，只能放路径格（!buildable），且未被工厂占用。
func can_place_tile(world, cell: Vector2i) -> bool:
	if world.grid == null:
		return false
	var c = world.grid.get_cell(cell)
	return c != null and c.occupant == 0 and not c.buildable


## 线路放置校验（管道/传送带）：返回空串 = 合法，否则为拒绝原因（UI 可直接显示）。
## 规则（策划案 · 放置规则）：只放 buildable 格、无工厂占用、无已有线；kind 必须是
## pipe/belt，dir 必须是四向单位向量，cells 不得为空或含重复格。逐格校验，任一失败整条拒绝。
## 入参兼容指令协议原文形态：cells 元素可为 Vector2i / Vector2 / [x, y]，dir 可为
## Vector2i / Vector2 / [dx, dy]。UI 拖拽可直接抛协议数据，不必先自行归一化。
func can_place_line(world, cells, kind, dir_v) -> String:
	if world == null or world.grid == null:
		return "网格未初始化"
	var k := StringName(kind)
	if k != &"pipe" and k != &"belt":
		return "未知线路类型 '%s'（只支持 pipe/belt）" % str(kind)
	if not _is_axis_dir(dir_v):
		return "线路方向必须是四向单位向量 [dx,dy]: %s" % str(dir_v)
	var list = cells
	if not (list is Array) or (list as Array).is_empty():
		return "place_line 缺少 cells"
	var seen: Dictionary = {}
	for raw in list:
		var cell = _as_cell(raw)
		if cell == null:
			return "cells 含非坐标元素: %s" % str(raw)
		if seen.has(cell):
			return "cells 含重复格: %s" % str(cell)
		seen[cell] = true
		var reason := _line_cell_reason(world, cell)
		if not reason.is_empty():
			return reason
	return ""


## 线路拆除校验：格存在且该格有线路。cells 元素形态同 can_place_line；重复格合法（拆除侧去重）。
func can_remove_line(world, cells) -> String:
	if world == null or world.grid == null:
		return "网格未初始化"
	var list = cells
	if not (list is Array) or (list as Array).is_empty():
		return "remove_line 缺少 cells"
	for raw in list:
		var cell = _as_cell(raw)
		if cell == null:
			return "cells 含非坐标元素: %s" % str(raw)
		var c = world.grid.get_cell(cell)
		if c == null:
			return "格子不存在: %s" % str(cell)
		if not c.has_line():
			return "格子上没有线路: %s" % str(cell)
	return ""


## 单格线路放置前置条件（存在 ∧ buildable ∧ 无工厂占用 ∧ 无已有线）。
func _line_cell_reason(world, cell: Vector2i) -> String:
	var c = world.grid.get_cell(cell)
	if c == null:
		return "格子不存在: %s" % str(cell)
	if not c.buildable:
		return "格子不可建造（非关卡标注的 buildable 格）: %s" % str(cell)
	if c.occupant != 0:
		return "格子被工厂占用: %s" % str(cell)
	if c.has_line():
		return "格子已有线路（%s）: %s" % [String(c.line_kind), str(cell)]
	return ""


## 四向单位向量判定：接受 Vector2i / Vector2 / [dx, dy]（指令协议与 UI 共用形态）。
func _is_axis_dir(v) -> bool:
	var d = _as_cell(v)
	return d != null and absi(d.x) + absi(d.y) == 1


## 坐标/方向归一化：Vector2i / Vector2 / [x, y] → Vector2i；非法返回 null。
## 与 CommandSystem._cell_value 同构（指令层仍保留自己的入队归一，合并留终审分诊）。
func _as_cell(v):
	if v is Vector2i:
		return v
	if v is Vector2:
		return Vector2i(int(v.x), int(v.y))
	if v is Array and v.size() >= 2 \
			and (v[0] is int or v[0] is float) and (v[1] is int or v[1] is float):
		return Vector2i(int(v[0]), int(v[1]))
	return null


func tick(world, _dt: float) -> void:
	if world.grid == null:
		return
	for cell in world.grid.cells:
		var c = world.grid.cells[cell]
		if c.occupant != 0 and not world.is_alive(c.occupant):
			c.occupant = 0
