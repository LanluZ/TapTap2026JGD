class_name LogisticsSystem
extends System
## 物流模拟（传送带离散矿块；架构文档 §5 之外的模拟步，注册在 CommandSystem 之后）。
##
## 数据契约：矿块是纯 float，存在 GridMapData.Cell.belt_items（位置 ∈ [0,1)，沿
## Cell.line_dir 从本格入口 0.0 到出口 1.0）。本系统是唯一推进这些 float 的地方；
## 渲染是任务 7 的事，本文件不碰 Node/视觉。
##
## 每 tick 三步（顺序固定，保证确定性）：
##   ① 推进：每格从前往后，块向前走 SPEED*dt，受「前块位置 - MIN_GAP」与本格出口 1.0 限制；
##   ② 转移：位置到 1.0 的块按目标格规则处理——同 kind belt 插入（同向 0.0 / 异向 0.5，
##      落点 0.25 格内有块或容量满则等待）；对接建筑 → world.deliver_ore；其余（空地/
##      管道格/无出口）→ 块消失（掉落）；
##   ③ 注入：矿机本地缓冲有矿时，向「带起点 0.0 贴矿机、方向背向矿机」的 belt 注入，≤2 块/秒
##      （指向矿机的带不算出料口：会原路送回矿机自身，见 _inlets）。
##
## 规格取值（策划 2026-10-18）：带速 2.0 格/秒、最小间距 0.25 格、每格容量 4 块、
## 缓冲容量 4、注入 ≤2 块/秒。
##
## 已知上限（升级路径，不做）：
# ponytail: 闭环带（A→B→A）在同一 tick 内按格序推进 + 转移，极端几何下块可能来回抖动
# ponytail: （T12 的稳定满格是已验证的例外）；彻底解法 = 逐块全局排序推进（按位置排序后
# ponytail: 统一结算），成本是每 tick 一次全局排序，目前格子 ≤ 20×10 不值得。

const SPEED := 2.0 # 格/秒
const MIN_GAP := 0.25 # 同格最小间距（格）
const CELL_CAPACITY := 4 # 每格块数上限
const BUFFER_CAPACITY := 4 # 矿机/水泵本地缓冲容量
const INJECT_INTERVAL := 0.5 # 注入周期 = ≤2 块/秒
const INJECT_POS := 0.0 # 注入点 = 带起点
const SAME_DIR_POS := 0.0 # 同向链插入点
const CROSS_DIR_POS := 0.5 # 方向不一致（侧向/对头）插入点
const EPS := 0.0001

const KIND_BELT := &"belt"
const KIND_PIPE := &"pipe"
const RECIPE_MINE := &"mine_ore"

var _grid = null

## 矿机/水泵本地缓冲：entity_id -> int（0..BUFFER_CAPACITY）。
## 生产端扣减是任务 5：ProductionSystem 完工时调 add_buffer(id) 把矿塞进这里，
## 缓冲满则停产。本系统只负责在注入成功时减 1。
var buffers: Dictionary = {}

## 注入节拍：entity_id -> 距上次注入累计秒数（无矿时不计时）。
var _inject_timer: Dictionary = {}

## 合流 round-robin 指针：目标格 -> 上次成功插入的来源格。
var _merge_last: Dictionary = {}


func setup(world) -> void:
	_grid = world.grid
	world.logistics = self # 查询入口（后续任务：world.get_system("LogisticsSystem") 亦可）


func tick(world, dt: float) -> void:
	if world.grid == null:
		return
	var belts: Array = _belt_cells(world)
	for cell in belts:
		_advance(world.grid.get_cell(cell), dt)
	_transfer(world, belts)
	_inject(world, dt)
	_prune_buffers(world)


## 实体销毁（融合双亲）后清掉残留缓冲与节拍，避免字典无限增长。
func _prune_buffers(world) -> void:
	if buffers.is_empty():
		return
	for id in buffers.keys():
		if not world.is_alive(id):
			buffers.erase(id)
			_inject_timer.erase(id)


# ================================================================ 公开查询/缓冲接口

## 本地缓冲当前矿数（无记录 = 0）。
func buffer_of(entity_id: int) -> int:
	return int(buffers.get(entity_id, 0))


## 缓冲是否已满（任务 5 停产的判据）。
func buffer_full(entity_id: int) -> bool:
	return buffer_of(entity_id) >= BUFFER_CAPACITY


## 生产端入缓冲（任务 5 调用）：返回实际进入的数量（受 BUFFER_CAPACITY 截断）。
func add_buffer(entity_id: int, amount: int = 1) -> int:
	var cur := buffer_of(entity_id)
	var n: int = clampi(cur + maxi(amount, 0), 0, BUFFER_CAPACITY) - cur
	if n > 0:
		buffers[entity_id] = cur + n
	return n


## 取走缓冲（调试/测试用，正常路径由注入自己扣）。
func take_buffer(entity_id: int, amount: int = 1) -> int:
	var cur := buffer_of(entity_id)
	var n: int = mini(maxi(amount, 0), cur)
	if n > 0:
		buffers[entity_id] = cur - n
		if cur - n == 0:
			buffers.erase(entity_id)
	return n


# ================================================================ ① 推进

## 单格推进：从最前块（位置最大）往后处理，每块最多走到 SPEED*dt 与「前块 - MIN_GAP」的较小值。
## 最前块上限 1.0（到 1.0 即待转移，由 ② 处理；不越过本格）。
func _advance(c, dt: float) -> void:
	if c == null or c.belt_items.is_empty():
		return
	c.belt_items.sort()
	var step: float = SPEED * dt
	var n: int = c.belt_items.size()
	for i in range(n - 1, -1, -1):
		var limit: float = 1.0
		if i < n - 1:
			limit = float(c.belt_items[i + 1]) - MIN_GAP
		var np: float = minf(float(c.belt_items[i]) + step, limit)
		if np > float(c.belt_items[i]):
			c.belt_items[i] = np


# ================================================================ ② 转移

func _transfer(world, belts: Array) -> void:
	# 收集意向：目标格 -> [来源格...]
	var groups: Dictionary = {}
	for cell in belts:
		var c = world.grid.get_cell(cell)
		if c == null or c.belt_items.is_empty():
			continue
		if float(c.belt_items[c.belt_items.size() - 1]) < 1.0 - EPS:
			continue
		var target: Vector2i = cell + c.line_dir
		if not groups.has(target):
			groups[target] = []
		(groups[target] as Array).append(cell)
	var targets: Array = groups.keys()
	targets.sort_custom(_cell_less)
	for target in targets:
		var sources: Array = groups[target]
		sources.sort_custom(_cell_less)
		for src in _rotate(sources, target):
			_transfer_one(world, src, target)


## 合流公平性：同一目标格的多个来源按上次赢家之后开始轮转（round-robin）。
func _rotate(sources: Array, target: Vector2i) -> Array:
	if sources.size() <= 1:
		return sources
	var start: int = 0
	if _merge_last.has(target):
		var idx: int = sources.find(_merge_last[target])
		if idx >= 0:
			start = (idx + 1) % sources.size()
	var out: Array = []
	for i in sources.size():
		out.append(sources[(start + i) % sources.size()])
	return out


## 单块转移：插入目标带 / 交付建筑 / 掉落消失。
func _transfer_one(world, src: Vector2i, target: Vector2i) -> void:
	var sc = world.grid.get_cell(src)
	if sc == null or sc.belt_items.is_empty():
		return
	if float(sc.belt_items[sc.belt_items.size() - 1]) < 1.0 - EPS:
		return # 本 tick 已被前面的来源处理过（或位置回退），不重复转移
	var tc = world.grid.get_cell(target)
	if tc != null and tc.line_kind == KIND_BELT:
		var pos: float = SAME_DIR_POS if tc.line_dir == sc.line_dir else CROSS_DIR_POS
		if _insert(target, pos):
			sc.belt_items.pop_back()
			_merge_last[target] = src
		return # 落点被占 / 容量满 → 块留在端头等待（位置已钉在 1.0）
	var occupant: int = 0 if tc == null else int(tc.occupant)
	if occupant != 0 and world.is_alive(occupant):
		# 对接判定：线端头格 + 输送方向指向的建筑格（建筑无朝向字段，占用者即对接方）。
		# deliver_ore 返回 false = 建筑暂不接收（任务 6 弹药满）→ 块留在端头等待。
		if world.deliver_ore(occupant):
			sc.belt_items.pop_back()
			_merge_last[target] = src
		return
	# 空地 / 管道格 / 无线路出口：矿块掉落消失（不与管道交换、不回收）。
	sc.belt_items.pop_back()
	_merge_last[target] = src


## 插入判定（落点 0.25 格内无块 ∧ 未满 4 块）；成功写入并保持升序。
func _insert(cell: Vector2i, pos: float) -> bool:
	var c = _grid.get_cell(cell)
	if c == null or c.line_kind != KIND_BELT:
		return false
	if c.belt_items.size() >= CELL_CAPACITY:
		return false
	for v in c.belt_items:
		if absf(float(v) - pos) < MIN_GAP - EPS:
			return false
	c.belt_items.append(pos)
	c.belt_items.sort()
	return true


# ================================================================ ③ 矿机注入

## 矿机（Production.recipe_id == mine_ore）缓冲有矿 → 向对接带起点注入。
## 节拍：每 INJECT_INTERVAL 秒最多一块（≤2 块/秒）；落点被占时下 tick 重试。
func _inject(world, dt: float) -> void:
	for id in world.query(&"Production"):
		if not world.is_alive(id):
			continue
		var prod = world.get_component(id, &"Production")
		if prod == null or prod.recipe_id != RECIPE_MINE:
			continue # 水泵→管道是任务 4（连通后排水），在此之外
		if buffer_of(id) <= 0:
			continue # 无矿不计时，避免缓冲区空转攒节拍
		var inlets: Array = _inlets(world, id)
		if inlets.is_empty():
			continue
		var t: float = float(_inject_timer.get(id, 0.0)) + dt
		if t < INJECT_INTERVAL - EPS:
			_inject_timer[id] = t
			continue
		var injected := false
		for cell in inlets:
			if _insert(cell, INJECT_POS):
				take_buffer(id, 1)
				injected = true
				break
		if injected:
			_inject_timer[id] = 0.0 # 成功即清零：不保留 t - INJECT_INTERVAL 的 dt 残值
		else:
			_inject_timer[id] = INJECT_INTERVAL # 落点被占：节拍已走满，下 tick 立即重试


## 与实体相邻、且**带起点（0.0 侧）贴该建筑、输送方向背向建筑**的 belt 格（升序，结果确定性）。
## 几何（正典，唯一注入口）：本格 - bc.line_dir == 建筑格 ⇒ 带格位于「建筑格 + dir」，
## 带起点 0.0 正贴建筑，矿从建筑旁上带后朝 1.0 背离建筑走。
## 「带终点贴建筑」（本格 + bc.line_dir == 建筑格，即 dir 指向建筑）**不是**注入口：
## 注入 0.0 后矿 0.5 秒就走到 1.0，目标格正是注入者自身 → world.deliver_ore(自己)，
## 构成矿机自馈回路（设计裁定禁止）。交付方向由 ② 的 target = cell + line_dir 落到建筑格负责，
## 注入侧只认背向形态。垂直相邻（既非起点也非终点）同样不算对接。
func _inlets(world, entity_id: int) -> Array:
	var gp = world.get_component(entity_id, &"GridPosition")
	if gp == null:
		return []
	var cell: Vector2i = gp.cell
	var out: Array = []
	for off in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]:
		var b: Vector2i = cell + off
		var bc = world.grid.get_cell(b)
		if bc == null or bc.line_kind != KIND_BELT:
			continue
		if b - bc.line_dir == cell:
			out.append(b)
	out.sort_custom(_cell_less)
	return out


# ================================================================ 工具

## 全带格（升序：先 y 后 x）——迭代顺序固定，保证同 tick 结算可复现。
func _belt_cells(world) -> Array:
	var out: Array = []
	for cell in world.grid.cells:
		var c = world.grid.cells[cell]
		if c.line_kind == KIND_BELT:
			out.append(cell)
	out.sort_custom(_cell_less)
	return out


func _cell_less(a: Vector2i, b: Vector2i) -> bool:
	if a.y != b.y:
		return a.y < b.y
	return a.x < b.x
