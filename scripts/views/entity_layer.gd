class_name EntityLayer
extends Node2D
## 表现层（架构文档 §1）：逻辑实体 → 视图节点（工厂 FactoryView 部件拼装 / 敌人帧动画+血条 / 射弹贴图）。只读世界，不写。
## 贴图查 scripts/views/art_registry.gd；敌人类型取 Enemy.etype，射弹取 Projectile.proj_id。

const Placeholder := preload("res://icon.svg")
const FactoryViewScript := preload("res://scripts/views/factory_view.gd")
const Art := preload("res://scripts/views/art_registry.gd")

var world
var _sprites: Dictionary = {} # entity_id -> Node2D（AnimatedSprite2D / Sprite2D / FactoryView）


## 敌人血量条（§1.2③ 表现层同步）：挂敌人精灵子节点——位置随精灵动、销毁随精灵走，零额外同步。
## 尺寸取精灵 get_rect() 局部坐标（48px 贴图/占位图通吃），随精灵 scale 缩放＝条宽自动对齐体型，免按类型配偏移。
class HpBar extends Node2D:
	const COLOR_BG := Color(0.184, 0.122, 0.216, 1.0) # 同 UiStyle.COLOR_BAR_BG
	const COLOR_FULL := Color(0.635, 0.824, 1.0) # 满血 Sky Blue
	const COLOR_EMPTY := Color(1.0, 0.686, 0.8) # 残血 Blush Pop

	var world
	var entity_id: int = 0
	var bar_w: float = 48.0 # 条宽（精灵局部坐标）
	var bar_h: float = 7.0
	var _ratio: float = -1.0 # 当前 hp/max_hp（-1 = 尚未绘制）

	func setup(w, eid: int) -> void:
		world = w
		entity_id = eid
		_refresh()

	func _process(_dt: float) -> void:
		if world != null and world.is_alive(entity_id):
			_refresh()

	## 值变了才重绘；无 Health/无上限按 0 处理（不伪造满血）。
	func _refresh() -> void:
		var r := _hp_ratio()
		if not is_equal_approx(r, _ratio):
			_ratio = r
			queue_redraw()

	func _hp_ratio() -> float:
		var hpc = world.get_component(entity_id, &"Health")
		if hpc == null or float(hpc.max_hp) <= 0.0:
			return 0.0
		return clampf(float(hpc.hp) / float(hpc.max_hp), 0.0, 1.0)

	func _draw() -> void:
		var rect := Rect2(-bar_w * 0.5, -bar_h * 0.5, bar_w, bar_h)
		draw_rect(rect, COLOR_BG)
		if _ratio > 0.0:
			# 血量越多越绿、越少越红
			draw_rect(Rect2(rect.position, Vector2(bar_w * _ratio, bar_h)),
				COLOR_FULL.lerp(COLOR_EMPTY, 1.0 - _ratio))


func setup(w) -> void:
	world = w
	world.entity_destroyed.connect(_on_entity_destroyed)


func _process(_dt: float) -> void:
	if world == null:
		return
	for id in world.entity_ids():
		if not _sprites.has(id):
			_spawn(id)
	var anim_speed := _anim_speed()
	for id in _sprites:
		var node: Node2D = _sprites[id] as Node2D
		var pos = EntityLocator.position(world, id)
		if pos != null:
			node.position = pos
		# 帧动画跟游戏时间走：2 倍速 ×2；暂停/结算冻结时 0（speed_scale=0 停帧且保留进度）
		if node is AnimatedSprite2D:
			(node as AnimatedSprite2D).speed_scale = anim_speed


## 敌人帧动画的时间倍率：逻辑层未在跑（暂停按钮 / 胜负结算）→ 0，否则 = 玩家当前倍速。
func _anim_speed() -> float:
	var st = world.state
	if st == null:
		return 1.0
	if not st.is_playing() or not st.waves_running:
		return 0.0
	return float(st.speed)


func _spawn(id: int) -> void:
	var s: Node2D
	if world.has_component(id, &"Factory") and not world.has_component(id, &"PathFollower"):
		# DNA 外形：按基因组拼装部件（底座+炮管/烟囱/信标/料箱/天线），贴图查 Art.PARTS
		var fv := FactoryViewScript.new()
		fv.setup(world, id)
		s = fv
	elif world.has_component(id, &"Enemy"):
		s = _enemy_sprite(id)
	elif world.has_component(id, &"Projectile"):
		s = _projectile_sprite(id)
	else:
		# 无贴图可依的实体：沿用图标占位（0.7×），不伪造外观
		var spr := Sprite2D.new()
		spr.texture = Placeholder
		spr.scale = Vector2(0.7, 0.7)
		s = spr
	var pos = EntityLocator.position(world, id)
	if pos != null:
		s.position = pos
	add_child(s)
	_sprites[id] = s
	if world.has_component(id, &"Enemy") and world.has_component(id, &"Health"):
		_attach_hp_bar(id, s)


## 血量条定位：局部坐标压在精灵顶边上方（间隙 4 + 半条高），条宽取帧贴图宽 → 与体型等宽。
## AnimatedSprite2D 没有 get_rect()（Godot 4.7 实测），帧贴图尺寸单独取；帧动画帧恒居中绘制。
func _attach_hp_bar(id: int, spr: Node2D) -> void:
	var size := Vector2.ZERO
	var top := 0.0
	var cx := 0.0
	if spr is Sprite2D:
		var r := (spr as Sprite2D).get_rect()
		size = r.size
		top = r.position.y
		cx = r.get_center().x
	elif spr is AnimatedSprite2D:
		var a := spr as AnimatedSprite2D
		var t: Texture2D = a.sprite_frames.get_frame_texture(a.animation, a.frame)
		if t == null:
			return
		size = t.get_size()
		top = -size.y * 0.5
	else:
		return
	var bar := HpBar.new()
	bar.setup(world, id)
	bar.bar_w = size.x
	bar.position = Vector2(cx, top - 4.0 - bar.bar_h * 0.5)
	spr.add_child(bar)


## 敌人：按 etype 查注册表建帧动画（多帧=待机/移动循环，单帧=静图）；查不到类型回退占位图。
func _enemy_sprite(id: int) -> Node2D:
	var en = world.get_component(id, &"Enemy")
	var etype := String(en.etype) if en != null else ""
	var def = Art.ENEMY.get(etype, null)
	if def == null:
		push_warning("[表现层] 无敌人贴图注册: %s（回退占位）" % etype)
		var spr := Sprite2D.new()
		spr.texture = Placeholder
		spr.scale = Vector2(0.35, 0.35)
		spr.modulate = Color(1.0, 0.6, 0.6)
		return spr
	var frames := SpriteFrames.new()
	frames.add_animation(&"move")
	frames.set_animation_speed(&"move", Art.ANIM_FPS)
	frames.set_animation_loop(&"move", true)
	for p in (def["frames"] as Array):
		var t: Texture2D = Art.tex(str(p))
		if t != null:
			frames.add_frame(&"move", t)
	if frames.get_frame_count(&"move") == 0:
		push_error("[表现层] 敌人 %s 全部帧加载失败" % etype)
	var spr := AnimatedSprite2D.new()
	spr.sprite_frames = frames
	spr.scale = Vector2(float(def["scale"]), float(def["scale"]))
	spr.modulate = Color(1, 1, 1, float(def.get("alpha", 1.0)))
	spr.play(&"move")
	return spr


## 射弹：按 proj_id 查注册表（ore_heavy 复用矿石弹放大压暗，见 Art.PROJECTILE）；查不到回退占位图。
func _projectile_sprite(id: int) -> Node2D:
	var p = world.get_component(id, &"Projectile")
	var pid := String(p.proj_id) if p != null else ""
	var def = Art.PROJECTILE.get(pid, null)
	var spr := Sprite2D.new()
	if def == null:
		push_warning("[表现层] 无射弹贴图注册: %s（回退占位）" % pid)
		spr.texture = Placeholder
		spr.scale = Vector2(0.15, 0.15)
		spr.modulate = Color(0.7, 0.7, 0.7)
		return spr
	spr.texture = Art.tex(str(def["tex"]))
	spr.scale = Vector2(float(def["scale"]), float(def["scale"]))
	spr.modulate = def["modulate"]
	return spr


func _on_entity_destroyed(id: int) -> void:
	if _sprites.has(id):
		(_sprites[id] as Node2D).queue_free()
		_sprites.erase(id)
