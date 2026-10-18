class_name LogisticsLayer
extends Node2D
## 物流渲染层（任务 7）：管道 / 传送带的方向箭头 + 传送带上的矿块小方块 + 拒收闪红。
##
## 挂 EntityLayer 下（与场地同一变换），每帧从 GridMapData 读线状态、从
## LogisticsSystem 写的 Cell.belt_items 读块位。**只读世界**：块位唯一推进者是
## LogisticsSystem，本层不改任何 Cell 字段、不推进模拟。
##
## 视觉契约（审查 R3）：方向箭头是规则的可视化，不是装饰——反向拖（建筑→泵）会让
## 受料端断水，玩家只能靠箭头判断「这条线往哪送」。所以箭头每格都画、且高对比度。
##
## 对外（headless 可断言，见 tests/logistics_test.gd T26）：
##   line_items(world) → [{cell, kind, dir, items}] 只读快照（升序，先 y 后 x）
##   ore_pos(cell, dir, t, cs) → 块位 t ∈ [0,1] 的世界坐标

const KIND_BELT := &"belt"
const KIND_PIPE := &"pipe"

## 纯矢量配色（无管道/传送带美术素材，颜色只做区分；不伪造贴图外观）
const COLOR_PIPE := Color(0.36, 0.55, 0.78, 0.95)
const COLOR_PIPE_FLOW := Color(0.62, 0.86, 1.0, 1.0)
const COLOR_BELT := Color(0.24, 0.22, 0.2, 0.95)
const COLOR_BELT_EDGE := Color(0.52, 0.45, 0.34, 1.0)
const COLOR_BELT_FLOW := Color(0.98, 0.8, 0.35, 1.0)
const COLOR_ORE := Color(0.86, 0.64, 0.32, 1.0)
const COLOR_ORE_EDGE := Color(0.42, 0.27, 0.1, 1.0)
const COLOR_REJECT := Color(0.92, 0.25, 0.2, 1.0)

## 拒收闪红时长（秒）：ore_rejected 是边沿信号，收到 = 该建筑刚进入拒收态
const REJECT_FLASH_TIME := 0.35

var _world
var _cell := 64.0
var _flash: Dictionary = {} # Vector2i -> 剩余秒数


func setup(w) -> void:
	_world = w
	if w == null:
		return
	if w.grid != null:
		_cell = float(w.grid.cell_size)
	if not w.ore_rejected.is_connected(_on_ore_rejected):
		w.ore_rejected.connect(_on_ore_rejected)
	queue_redraw()


## 拒收反馈：该实体所在格闪红一次（首版不区分 full / no_feed，两者都是「送不进去」）。
## 边沿信号 → 不会 10Hz 常亮；块被收下后由 world 侧清快照，下次拒收再触发。
func _on_ore_rejected(entity_id: int, _reason: String) -> void:
	if _world == null:
		return
	var gp = _world.get_component(entity_id, &"GridPosition")
	if gp == null:
		return
	_flash[gp.cell] = REJECT_FLASH_TIME


func _process(dt: float) -> void:
	if _world == null or _world.grid == null:
		return
	if not _flash.is_empty():
		for cell in _flash.keys():
			var t: float = float(_flash[cell]) - dt
			if t <= 0.0:
				_flash.erase(cell)
			else:
				_flash[cell] = t
	queue_redraw() # 块位由物流系统每 tick 推进（2 格/秒），必须每帧重绘


## 只读渲染快照：只含有线格（升序，与 LogisticsSystem 结算序一致）。
## items 仅 belt 有内容（Array[float] 位置副本），管道恒空；外部拿到的都是副本。
static func line_items(world) -> Array:
	var out: Array = []
	if world == null or world.grid == null:
		return out
	var cells: Array = []
	for c in world.grid.cells:
		var cell = world.grid.cells[c]
		if cell != null and cell.has_line():
			cells.append(c)
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x)
	for c in cells:
		var cell = world.grid.get_cell(c)
		var items: Array = []
		if cell.line_kind == KIND_BELT:
			for v in cell.belt_items:
				items.append(float(v))
		out.append({"cell": c, "kind": cell.line_kind, "dir": cell.line_dir, "items": items})
	return out


## 块位 → 世界坐标：入口 = 格心 - dir*半格（本格 0.0 侧），t ∈ [0,1] 沿 dir 到出口。
## 与 LogisticsSystem 的「0.0 = 本格入口、1.0 = 出口」契约逐字对应。
static func ore_pos(cell: Vector2i, dir: Vector2i, t: float, cs: float) -> Vector2:
	var center := (Vector2(cell) + Vector2(0.5, 0.5)) * cs
	return center - Vector2(dir) * cs * 0.5 + Vector2(dir) * clampf(t, 0.0, 1.0) * cs


func _draw() -> void:
	if _world == null or _world.grid == null:
		return
	var cs := _cell
	for item in line_items(_world):
		var cell: Vector2i = item["cell"]
		var dir: Vector2i = item["dir"]
		var origin := Vector2(cell) * cs
		if item["kind"] == KIND_PIPE:
			_draw_pipe(origin, dir, cs)
		else:
			_draw_belt(origin, dir, cs)
		for t in (item["items"] as Array):
			_draw_ore(ore_pos(cell, dir, float(t), cs), cs)
	# 拒收闪红：格子描边由亮到灭，只在刚进入拒收态的一小段时间可见
	for cell in _flash:
		var a: float = clampf(float(_flash[cell]) / REJECT_FLASH_TIME, 0.0, 1.0)
		draw_rect(Rect2(Vector2(cell) * cs, Vector2(cs, cs)), Color(COLOR_REJECT, 0.9 * a), false, 3.0)


## 管道：管身 + 流向箭头（箭头高对比度，R3 要求清晰可见）。
func _draw_pipe(origin: Vector2, dir: Vector2i, cs: float) -> void:
	var d := Vector2(dir)
	var start := origin + Vector2(cs, cs) * 0.5 - d * cs * 0.5
	var end := start + d * cs
	draw_line(start, end, COLOR_PIPE, cs * 0.34)
	var tip := start + d * cs * 0.76
	var back := tip - d * cs * 0.22
	var side := Vector2(-d.y, d.x) * cs * 0.17
	draw_colored_polygon(PackedVector2Array([tip, back + side, back - side]), COLOR_PIPE_FLOW)


## 传送带：深色带面 + 双侧边条 + 两道 V 形 chevron（方向箭头）。
func _draw_belt(origin: Vector2, dir: Vector2i, cs: float) -> void:
	var d := Vector2(dir)
	var start := origin + Vector2(cs, cs) * 0.5 - d * cs * 0.5
	var end := start + d * cs
	draw_line(start, end, COLOR_BELT, cs * 0.76)
	var edge := Vector2(-d.y, d.x) * cs * 0.38
	draw_line(start + edge, end + edge, COLOR_BELT_EDGE, 2.0)
	draw_line(start - edge, end - edge, COLOR_BELT_EDGE, 2.0)
	for k in [0.36, 0.66]:
		var p := start + d * cs * float(k)
		var back := p - d * cs * 0.18
		var side := Vector2(-d.y, d.x) * cs * 0.2
		draw_line(p, back + side, COLOR_BELT_FLOW, 3.0)
		draw_line(p, back - side, COLOR_BELT_FLOW, 3.0)


## 矿块：小方块（颜色区分），中心落在块位上。
func _draw_ore(pos: Vector2, cs: float) -> void:
	var half := cs * 0.11
	var rect := Rect2(pos - Vector2(half, half), Vector2(half * 2.0, half * 2.0))
	draw_rect(rect, COLOR_ORE, true)
	draw_rect(rect, COLOR_ORE_EDGE, false, 1.5)
