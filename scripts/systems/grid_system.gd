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


func tick(world, _dt: float) -> void:
	if world.grid == null:
		return
	for cell in world.grid.cells:
		var c = world.grid.cells[cell]
		if c.occupant != 0 and not world.is_alive(c.occupant):
			c.occupant = 0
