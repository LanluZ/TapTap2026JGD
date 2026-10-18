class_name GridMapData
extends RefCounted
## 建造网格（§4/§6）：Dictionary[Vector2i, Cell]。
## 地块（减速带等）不是实体，存在 cells[cell].tile_type，由移动逻辑读取（§4）。
## 路径穿过（path_cells）与可建造（buildable_cells）均由关卡 JSON 标注。


class Cell extends RefCounted:
	var buildable: bool = false # 关卡标注：可否放置工厂
	var tile_type: StringName = &"" # "" = 普通地形
	var occupant: int = 0 # 占用者实体 id；0 = 空

	## —— 线路（管道/传送带）附着 ——
	## 一格最多一条线：kind 决定语义，dir 是输送方向（四向单位向量）。
	## belt_items 仅 belt 使用：矿块位置 ∈ [0,1)，沿 line_dir 从本格入口到出口。
	var line_kind: StringName = &"" # "" = 无线 / "pipe" / "belt"
	var line_dir: Vector2i = Vector2i.ZERO
	var belt_items: Array[float] = []


	func set_line(kind: StringName, dir: Vector2i) -> void:
		line_kind = kind
		line_dir = dir


	func remove_line() -> void:
		line_kind = &""
		line_dir = Vector2i.ZERO
		belt_items.clear()


	func has_line() -> bool:
		return line_kind != &""


var cell_size: float = 64.0 # 世界单位/格（levels.json cell_size）
var cells: Dictionary = {} # Vector2i -> Cell


func setup(size: float) -> void:
	cell_size = size


func ensure_cell(c: Vector2i) -> Cell:
	if not cells.has(c):
		cells[c] = Cell.new()
	return cells[c]


func get_cell(c: Vector2i) -> Cell:
	return cells.get(c, null)


func set_buildable(c: Vector2i) -> void:
	ensure_cell(c).buildable = true


## 工厂放置合法性（数据层；指令校验入口在 GridSystem.can_build）。
## 一格式一物：有线路的格也不能再放工厂（与「线上不放工厂」对称）。
func is_buildable(c: Vector2i) -> bool:
	var cell: Cell = get_cell(c)
	return cell != null and cell.buildable and cell.occupant == 0 and not cell.has_line()


func occupy(c: Vector2i, entity_id: int) -> void:
	ensure_cell(c).occupant = entity_id


func clear_occupant(c: Vector2i) -> void:
	var cell: Cell = get_cell(c)
	if cell != null:
		cell.occupant = 0


func set_tile(c: Vector2i, tile_type: StringName) -> void:
	ensure_cell(c).tile_type = tile_type


## 线路读写（数据层薄封装；放置合法性校验在 GridSystem.can_place_line）。
func set_line(c: Vector2i, kind: StringName, dir: Vector2i) -> void:
	ensure_cell(c).set_line(kind, dir)


func remove_line(c: Vector2i) -> void:
	var cell: Cell = get_cell(c)
	if cell != null:
		cell.remove_line()


func has_line(c: Vector2i) -> bool:
	var cell: Cell = get_cell(c)
	return cell != null and cell.has_line()


## 世界坐标 → 格子（坐标系原点在 (0,0) 格左上角）。
func world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / cell_size), floori(p.y / cell_size))


## 格子中心 → 世界坐标（工厂出生/索敌的统一位置）。
func cell_to_world(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * cell_size
