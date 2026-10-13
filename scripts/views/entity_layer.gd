class_name EntityLayer
extends Node2D
## 表现层（架构文档 §1）：逻辑实体 → 视图节点（工厂 FactoryView 部件拼装 / 敌人与射弹 Sprite 占位）。只读世界，不写。

const Placeholder := preload("res://icon.svg")

var world
var _sprites: Dictionary = {} # entity_id -> Node2D（Sprite2D 或 FactoryView）


func setup(w) -> void:
	world = w
	world.entity_destroyed.connect(_on_entity_destroyed)


func _process(_dt: float) -> void:
	if world == null:
		return
	for id in world.entity_ids():
		if not _sprites.has(id):
			_spawn(id)
	for id in _sprites:
		var pos = EntityLocator.position(world, id)
		if pos != null:
			(_sprites[id] as Node2D).position = pos


func _spawn(id: int) -> void:
	var s: Node2D
	if world.has_component(id, &"Factory") and not world.has_component(id, &"PathFollower"):
		# DNA 外形：按基因组拼装部件（底座+炮管/烟囱/信标/料箱/天线），正式素材后换贴图
		var fv := FactoryView.new()
		fv.setup(world, id)
		s = fv
	else:
		var spr := Sprite2D.new()
		spr.texture = Placeholder
		# 占位区分：敌人（沿路径）偏小偏红，射弹最小
		if world.has_component(id, &"PathFollower"):
			spr.scale = Vector2(0.35, 0.35)
			spr.modulate = Color(1.0, 0.6, 0.6)
		elif world.has_component(id, &"Projectile"):
			spr.scale = Vector2(0.15, 0.15)
			spr.modulate = Color(0.7, 0.7, 0.7)
		else:
			spr.scale = Vector2(0.7, 0.7)
		s = spr
	var pos = EntityLocator.position(world, id)
	if pos != null:
		s.position = pos
	add_child(s)
	_sprites[id] = s


func _on_entity_destroyed(id: int) -> void:
	if _sprites.has(id):
		(_sprites[id] as Node2D).queue_free()
		_sprites.erase(id)
