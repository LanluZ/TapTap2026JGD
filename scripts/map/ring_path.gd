class_name RingPath
extends RefCounted
## 环形路径（§6）：关卡顶点数组 → 折线段 + 累计弧长表。
## PathFollower.distance 按弧长取点，fposmod 天然支持循环。


var id: StringName = &""
var points: PackedVector2Array = PackedVector2Array()
var total_length: float = 0.0
var _seg_start: PackedFloat32Array = PackedFloat32Array() # 各段起点弧长
var _seg_len: PackedFloat32Array = PackedFloat32Array() # 各段长度


func is_ready() -> bool:
	return total_length > 0.0


## raw_points: JSON 顶点数组（[x, y] 或 Vector2），按闭合环处理（末点→首点）。
## 顶点数与重复点问题由 GameConfig 预先校验；这里防御性报错。
func build(path_id: StringName, raw_points: Array) -> bool:
	id = path_id
	points = PackedVector2Array()
	for p in raw_points:
		if p is Vector2:
			points.append(p)
		elif p is Array and p.size() >= 2:
			points.append(Vector2(float(p[0]), float(p[1])))
		else:
			push_error("RingPath[%s]: 顶点格式错误: %s" % [String(path_id), str(p)])
			return false
	if points.size() < 3:
		push_error("RingPath[%s]: 顶点数 %d < 3" % [String(path_id), points.size()])
		return false
	_seg_start = PackedFloat32Array()
	_seg_len = PackedFloat32Array()
	total_length = 0.0
	var n := points.size()
	for i in n:
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % n]
		var l: float = a.distance_to(b)
		if l <= 0.0:
			push_error("RingPath[%s]: 第 %d 个顶点与下一个顶点重合" % [String(path_id), i])
			return false
		_seg_start.append(total_length)
		_seg_len.append(l)
		total_length += l
	return total_length > 0.0


## 弧长取世界坐标（自动环形回绕）。
func point_at(distance: float) -> Vector2:
	if total_length <= 0.0 or points.is_empty():
		return Vector2.ZERO
	var d: float = fposmod(distance, total_length)
	var count := _seg_start.size()
	for i in count:
		if d <= _seg_start[i] + _seg_len[i] or i == count - 1:
			var t: float = 0.0
			if _seg_len[i] > 0.0:
				t = clampf((d - _seg_start[i]) / _seg_len[i], 0.0, 1.0)
			var a: Vector2 = points[i]
			var b: Vector2 = points[(i + 1) % points.size()]
			return a.lerp(b, t)
	return points[points.size() - 1]
