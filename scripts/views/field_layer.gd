class_name FieldLayer
extends Node2D
## 场地地块层（美术需求表 §3）：把关卡格子画成贴图——可建造格 lawn、路径格 groud、
## 已放置地块（tile_type）盖 panel。挂 EntityLayer 下（同场地缩放变换），画在实体下层。
## 贴图查 art_registry.gd TILES；未注册的 tile_type 不绘制（不伪造外观）。

const Art = preload("res://scripts/views/art_registry.gd")

var _world
var _tex_path: Dictionary = {} # "path"/"buildable"/<tile_type> -> Texture2D
var _tile_fp := "" # 地块指纹（放置新地块后重绘）


func setup(w) -> void:
	_world = w
	for key in Art.TILES:
		_tex_path[str(key)] = Art.tex(str(Art.TILES[key]))
	queue_redraw()


func _process(_dt: float) -> void:
	if _world == null or _world.grid == null:
		return
	var fp := _tile_fingerprint()
	if fp != _tile_fp:
		_tile_fp = fp
		queue_redraw()


## 已放置地块指纹：坐标+类型拼串，变化即有放置/移除。
func _tile_fingerprint() -> String:
	var parts: Array = []
	for c in _world.grid.cells:
		var cell = _world.grid.cells[c]
		if cell.tile_type != &"":
			parts.append("%s:%s" % [c, cell.tile_type])
	parts.sort()
	return "|".join(parts)


func _draw() -> void:
	if _world == null or _world.grid == null:
		return
	var cs: float = _world.grid.cell_size
	var tex_path: Texture2D = _tex_path.get("path", null)
	var tex_build: Texture2D = _tex_path.get("buildable", null)
	for c in _world.grid.cells:
		var cell = _world.grid.cells[c]
		var rect := Rect2(Vector2(c.x * cs, c.y * cs), Vector2(cs, cs))
		if cell.buildable:
			if tex_build != null:
				draw_texture_rect(tex_build, rect, false)
		elif tex_path != null: # 路径格：grid 里非 buildable 即路径（关卡标注 §6）
			draw_texture_rect(tex_path, rect, false)
		if cell.tile_type != &"":
			var ttex: Texture2D = _tex_path.get(str(cell.tile_type), null)
			if ttex != null:
				draw_texture_rect(ttex, rect, false)
