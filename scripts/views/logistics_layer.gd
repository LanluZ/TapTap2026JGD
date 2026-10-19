class_name LogisticsLayer
extends Node2D
## 物流渲染层（任务 7）：管道 / 传送带的接线 + 方向箭头 + 传送带上的矿块 + 拒收闪红。
##
## 挂 EntityLayer 下（与场地同一变换），每帧从 GridMapData 读线状态、从
## LogisticsSystem 写的 Cell.belt_items 读块位。**只读世界**：块位唯一推进者是
## LogisticsSystem，本层不改任何 Cell 字段、不推进模拟。
##
## 视觉契约（审查 R3）：方向箭头是规则的可视化，不是装饰——反向拖（建筑→泵）会让
## 受料端断水，玩家只能靠箭头判断「这条线往哪送」。所以箭头每格都画、且高对比度。
##
## **接线契约（拐弯拼接）**：每格不是「入口边 → 出口边」的孤立线段，而是按邻居的真实
## 连接画到边中点，让相邻格的端点精确重合、拐弯处不断开：
##   传送带（有向）上游 = 邻居 N 满足 N + N.dir == 本格（与 LogisticsSystem 的 target
##     判定同一条公式），画 N 边中点 → 格心 → 出口边中点；无上游时退化为入口 → 出口。
##   管道（无向，见 _flood_pipes）上游 = 所有相邻 pipe 格，四个方向全连 → L/T/十字天然闭合。
##
## 对外（headless 可断言，见 tests/logistics_test.gd T26/T28）：
##   line_items(world) → [{cell, kind, dir, items, in_dirs, links}] 只读快照（升序，先 y 后 x）
##   ore_pos(cell, dir, t, cs) → 块位的世界坐标（无拐弯退化形，T26 契约）
##   path_pos(cell, dir, in_dir, t, cs) → 含拐弯的块位（t=0 入口、0.5 格心、1 出口）
##   edge_point(cell, off, cs) → 本格朝 off 方向的边中点（相邻格的拼接点）

const KIND_BELT := &"belt"
const KIND_PIPE := &"pipe"

const Art = preload("res://scripts/views/art_registry.gd")

## 线宽（相对格宽）。比首版（0.76 / 0.34）收窄一档：格子之间留出缝隙，
## 拐弯圆角不至于把整格糊满，多个箭头也读得清。
const BELT_W_RATIO := 0.62
const PIPE_W_RATIO := 0.26
## 带身描边宽度（像素）：先画「线宽 + 描边」的边框色，再压带面。
const BELT_OUTLINE_PX := 3.0
## 带上矿块用资源图标（art_registry.RES_ICON.ore），边长相对格宽。
## 0.30 格 ≈ 19px @64：在 0.62 格的带面里居中留边，间距下限 0.25 格时只轻微叠压。
const ORE_W_RATIO := 0.30

## 四向邻居（固定顺序 = 合流主入边的选择顺序，保证渲染确定性）。
const NEIGHBORS := [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]

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
var _ore_tex: Texture2D = null # 资源图标 ore（TEX 缺失时回退纯色块）


func setup(w) -> void:
	_world = w
	if w == null:
		return
	if w.grid != null:
		_cell = float(w.grid.cell_size)
	_ore_tex = Art.tex(str(Art.RES_ICON.get("ore", "")))
	# 24×24 像素图标缩到 ~19px：nearest 保锐利，linear 会糊掉描边
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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


# ================================================================ 只读快照

## 只读渲染快照：只含有线格（升序，与 LogisticsSystem 结算序一致）。
## items 仅 belt 有内容（Array[float] 位置副本），管道恒空；外部拿到的都是副本。
## in_dirs / links 是本帧的接线方向（本格指向邻居的单位向量）：
##   belt.in_dirs = 上游格（谁把我当前进的）；belt.links = 出口 + 上游（绘制用）
##   pipe.links   = 所有相邻 pipe 格（无向连通，绘制用）；pipe.in_dirs 恒空
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
		var ins: Array = []
		var links: Array = []
		if cell.line_kind == KIND_BELT:
			for v in cell.belt_items:
				items.append(float(v))
			ins = in_dirs(world, c)
			if cell.line_dir != Vector2i.ZERO:
				links.append(cell.line_dir)
			for off in ins:
				if not links.has(off):
					links.append(off)
		else:
			links = pipe_links(world, c)
		out.append({"cell": c, "kind": cell.line_kind, "dir": cell.line_dir,
			"items": items, "in_dirs": ins, "links": links})
	return out


## belt 的上游方向（本格指向邻居的单位向量，顺序 = NEIGHBORS，保证确定性）。
## 判据与 LogisticsSystem 的 target = cell + line_dir 严格同一条公式：
## 邻居 N 指向本格 ⇔ N + N.dir == 本格。
static func in_dirs(world, cell: Vector2i) -> Array:
	var out: Array = []
	if world == null or world.grid == null:
		return out
	var me = world.grid.get_cell(cell)
	if me == null or me.line_kind != KIND_BELT:
		return out
	for off in NEIGHBORS:
		var n = world.grid.get_cell(cell + off)
		if n != null and n.line_kind == KIND_BELT and cell + off + n.line_dir == cell:
			out.append(off)
	return out


## pipe 的接线方向：所有相邻的同 kind 格（管道无向，见 LogisticsSystem._flood_pipes）。
## 不查 line_dir —— 管道方向只用于「受料端」判定，不影响连通。
static func pipe_links(world, cell: Vector2i) -> Array:
	var out: Array = []
	if world == null or world.grid == null:
		return out
	var me = world.grid.get_cell(cell)
	if me == null or me.line_kind != KIND_PIPE:
		return out
	for off in NEIGHBORS:
		var n = world.grid.get_cell(cell + off)
		if n != null and n.line_kind == KIND_PIPE:
			out.append(off)
	return out


# ================================================================ 几何（纯函数，headless 可测）

## 本格朝 off 方向的边中点（off 为四向单位向量；ZERO = 格心）。
## 相邻两格的接线点是同一个世界坐标：edge_point(A, +d) == edge_point(A + d, -d)。
static func edge_point(cell: Vector2i, off: Vector2i, cs: float) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5) + Vector2(off) * 0.5) * cs


## 块位 → 世界坐标（含拐弯）：t ∈ [0,1] 沿「入边中点 → 格心 → 出口边中点」走。
## 拐弯格的两段各长 0.5 格 ⇒ 参数即弧长比例，块不会在拐角变速；t=0.5 恰是格心，
## 与 LogisticsSystem 的 CROSS_DIR_POS（异向插入点 = 0.5）对应。
## in_dir == ZERO 或 in_dir == -dir（直线）时退化为线性插值。
static func path_pos(cell: Vector2i, dir: Vector2i, in_dir: Vector2i, t: float, cs: float) -> Vector2:
	var tt := clampf(t, 0.0, 1.0)
	var entry_dir: Vector2i = -dir if in_dir == Vector2i.ZERO else in_dir
	var entry := edge_point(cell, entry_dir, cs)
	var center := edge_point(cell, Vector2i.ZERO, cs)
	var exit_p := edge_point(cell, dir, cs)
	if in_dir == Vector2i.ZERO or in_dir == -dir:
		return entry.lerp(exit_p, tt)
	if tt <= 0.5:
		return entry.lerp(center, tt * 2.0)
	return center.lerp(exit_p, (tt - 0.5) * 2.0)


## 块位 → 世界坐标：入口 = 格心 - dir*半格（本格 0.0 侧），t ∈ [0,1] 沿 dir 到出口。
## 与 LogisticsSystem 的「0.0 = 本格入口、1.0 = 出口」契约逐字对应。
## 拐弯格用 path_pos（本函数是「入边 = -dir」的退化形，保留给外部契约与 T26）。
static func ore_pos(cell: Vector2i, dir: Vector2i, t: float, cs: float) -> Vector2:
	return path_pos(cell, dir, -dir, t, cs)


## 折线圆角化：把每个内拐点替换成半径 r 的二次贝塞尔倒角（steps 段采样）。
## draw_polyline 在 90° 拐角处只做平均法线，外侧会留一个 w/2 的缺口；
## 倒角后拐角变成弯头，粗线不会露出底色。返回的点集只用于绘制，不改块位参数。
static func round_path(pts: PackedVector2Array, r: float, steps: int = 6) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var out := PackedVector2Array([pts[0]])
	for i in range(1, pts.size() - 1):
		var p: Vector2 = pts[i]
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i + 1]
		var d1: Vector2 = a - p
		var d2: Vector2 = b - p
		if d1.length_squared() < 0.0001 or d2.length_squared() < 0.0001:
			out.append(p)
			continue
		d1 = d1.normalized()
		d2 = d2.normalized()
		var rr: float = minf(r, minf(a.distance_to(p), b.distance_to(p)) * 0.5)
		var t1: Vector2 = p + d1 * rr
		var t2: Vector2 = p + d2 * rr
		for s in steps + 1:
			var u := float(s) / float(steps)
			out.append(t1.lerp(p, u).lerp(p.lerp(t2, u), u))
	out.append(pts[pts.size() - 1])
	return out


# ================================================================ 绘制

func _draw() -> void:
	if _world == null or _world.grid == null:
		return
	var cs := _cell
	for item in line_items(_world):
		if item["kind"] == KIND_PIPE:
			_draw_pipe(item, cs)
		else:
			_draw_belt(item, cs)
		var main_in: Vector2i = _main_in(item)
		for t in (item["items"] as Array):
			_draw_ore(path_pos(item["cell"], item["dir"], main_in, float(t), cs), cs)
	# 拒收闪红：格子描边由亮到灭，只在刚进入拒收态的一小段时间可见
	for cell in _flash:
		var a: float = clampf(float(_flash[cell]) / REJECT_FLASH_TIME, 0.0, 1.0)
		draw_rect(Rect2(Vector2(cell) * cs, Vector2(cs, cs)), Color(COLOR_REJECT, 0.9 * a), false, 3.0)


## 合流格的主入边（决定带身形状与块位路径）：直线优先，否则取第一个（NEIGHBORS 序）。
func _main_in(item: Dictionary) -> Vector2i:
	var ins: Array = item["in_dirs"]
	var dir: Vector2i = item["dir"]
	if ins.is_empty():
		return -dir
	if ins.has(-dir):
		return -dir
	return ins[0]


## 传送带：描边带面 + 拐角圆角 + 两道 chevron。
## 起点格画满整段（入口 → 出口），拐角格画折线（上游边 → 格心 → 出口），
## 合流格的其余上游各补一条到格心 —— 所有段都在边中点与邻格精确重合。
func _draw_belt(item: Dictionary, cs: float) -> void:
	var cell: Vector2i = item["cell"]
	var dir: Vector2i = item["dir"]
	var w := cs * BELT_W_RATIO
	var center := edge_point(cell, Vector2i.ZERO, cs)
	var out_p := edge_point(cell, dir, cs)
	var ins: Array = item["in_dirs"]
	var paths: Array = []
	if ins.is_empty():
		paths.append(PackedVector2Array([edge_point(cell, -dir, cs), out_p]))
	else:
		for off in ins:
			var ep := edge_point(cell, off, cs)
			if off == -dir:
				paths.append(PackedVector2Array([ep, out_p]))
			else:
				paths.append(PackedVector2Array([ep, center, out_p]))
	# 描边：先画宽一圈的边框色，再压带面（拐角处自动一致，不会像平行边条那样断开）
	# 拐角先倒角成弯头，否则 draw_polyline 的 90° 外角会缺口露底
	var r := cs * BELT_W_RATIO * 0.7
	for p in paths:
		draw_polyline(round_path(p, r), COLOR_BELT_EDGE, w + BELT_OUTLINE_PX, true)
	for p in paths:
		draw_polyline(round_path(p, r), COLOR_BELT, w, true)
	draw_circle(center, w * 0.5, COLOR_BELT) # 拐角内侧补圆，弯头里侧不空
	# chevron：沿主路径 t=0.42 / 0.72（拐角格上一个在入段、一个在出段，方向都朝前）
	var main_in := _main_in(item)
	for k in [0.42, 0.72]:
		var p: Vector2 = path_pos(cell, dir, main_in, float(k), cs)
		var tan: Vector2 = path_pos(cell, dir, main_in, float(k) + 0.03, cs) - p
		if tan.length_squared() < 0.0001:
			tan = Vector2(dir)
		tan = tan.normalized()
		var back := p - tan * cs * 0.14
		var side := Vector2(-tan.y, tan.x) * cs * 0.15
		draw_line(p, back + side, COLOR_BELT_FLOW, 2.5, true)
		draw_line(p, back - side, COLOR_BELT_FLOW, 2.5, true)


## 管道：向每个相邻管格伸到边中点（无向，L/T/十字天然闭合），格心补圆；
## 再在 dir 端画受料口箭头（规则可视化：dir 指向的那侧才是建筑接水端）。
func _draw_pipe(item: Dictionary, cs: float) -> void:
	var cell: Vector2i = item["cell"]
	var dir: Vector2i = item["dir"]
	var w := cs * PIPE_W_RATIO
	var center := edge_point(cell, Vector2i.ZERO, cs)
	var links: Array = item["links"]
	if links.is_empty():
		# 孤立管（或 dir 端断头）：沿 dir 画一小段管桩，仍能看出朝向
		draw_line(center - Vector2(dir) * cs * 0.22, center + Vector2(dir) * cs * 0.22, COLOR_PIPE, w)
	else:
		for off in links:
			draw_line(center, edge_point(cell, off, cs), COLOR_PIPE, w, true)
	draw_circle(center, w * 0.5, COLOR_PIPE)
	var tip: Vector2 = edge_point(cell, dir, cs) - Vector2(dir) * cs * 0.05
	var back: Vector2 = tip - Vector2(dir) * cs * 0.20
	var side := Vector2(-dir.y, dir.x) * cs * 0.115
	draw_colored_polygon(PackedVector2Array([tip, back + side, back - side]), COLOR_PIPE_FLOW)


## 矿块：资源图标 ore（与 HUD 资源栏同一素材），中心落在块位上。
## 素材缺失时回退纯色块（Art.tex 已 warn，不伪造贴图）。
func _draw_ore(pos: Vector2, cs: float) -> void:
	var side := cs * ORE_W_RATIO
	if _ore_tex != null:
		draw_texture_rect(_ore_tex, Rect2(pos - Vector2(side, side) * 0.5, Vector2(side, side)), false)
		return
	var half := side * 0.5
	var rect := Rect2(pos - Vector2(half, half), Vector2(side, side))
	draw_rect(rect, COLOR_ORE, true)
	draw_rect(rect, COLOR_ORE_EDGE, false, 1.5)
