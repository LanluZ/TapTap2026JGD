extends RefCounted
## 拖拽画线的纯几何工具（无 Node 依赖，headless 可单测）。
##
## 契约约束：一条 place_line 把**同一个 dir 写给整条 cells**（指令协议），因此拖拽只能
## 产出单轴直链——斜拖取主轴、不改道；否则整条线的输送方向会与几何自相矛盾
## （反向拖 = 箭头指向与拖拽方向一致，玩家靠箭头自查受料端，见审查 R3）。
## 格序跟随拖拽方向（起点 → 终点），上层按需保留「从泵侧拖出」的语义。

## 单次拖拽最多格数（网格 ≤ 20×10；上限只防异常拖拽产生超长指令）。
const MAX_CELLS := 64


## 起点格 + 终点格 → 单轴直链格集（含两端，格序 = 拖拽方向）。
## 主轴取 |dx| >= |dy| → x，否则 y（对角等长时走 x，结果确定）。
static func line_cells(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var d := line_dir(a, b)
	if d == Vector2i.ZERO:
		out.append(a) # 原地点击：单格（方向由上层回退，见 line_draw_overlay）
		return out
	var steps: int = absi(b.x - a.x) if d.y == 0 else absi(b.y - a.y)
	steps = mini(steps, MAX_CELLS - 1)
	for i in steps + 1:
		out.append(a + d * i)
	return out


## 起点格 + 终点格 → 四向单位方向（原地点击返回 ZERO）。
static func line_dir(a: Vector2i, b: Vector2i) -> Vector2i:
	var dx := b.x - a.x
	var dy := b.y - a.y
	if dx == 0 and dy == 0:
		return Vector2i.ZERO
	if absi(dx) >= absi(dy):
		return Vector2i(signi(dx), 0)
	return Vector2i(0, signi(dy))


## 单格朝向判定：按下点 → 松开点的像素位移取主轴（同格拖拽用，判定规则与
## line_dir 对格位移的主轴判定一致）。位移小于 deadzone（纯点击/手抖）返回
## ZERO，上层回退上次拖拽方向。
static func pixel_dir(press: Vector2, release: Vector2, deadzone: float = 4.0) -> Vector2i:
	var delta := release - press
	if absf(delta.x) < deadzone and absf(delta.y) < deadzone:
		return Vector2i.ZERO
	if absf(delta.x) >= absf(delta.y):
		return Vector2i(signi(int(delta.x)), 0)
	return Vector2i(0, signi(int(delta.y)))


## 矩形框选作用域：起点格 + 终点格 → 两角围出的矩形内全部格（含两端，行优先）。
## 拆除工具对「一片线」的唯一几何来源：单击（a == b）自然退化为单格。
static func rect_cells(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var x0 := mini(a.x, b.x)
	var x1 := maxi(a.x, b.x)
	var y0 := mini(a.y, b.y)
	var y1 := maxi(a.y, b.y)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			out.append(Vector2i(x, y))
	return out
