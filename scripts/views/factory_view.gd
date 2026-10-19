class_name FactoryView
extends Node2D

const GenomeScript = preload("res://scripts/dna/genome.gd")
const Art = preload("res://scripts/views/art_registry.gd")
## 工厂表现视图（DNA 外形，美术需求表 §2）：按实体基因组拼装部件子图层。
## 部件 = 表达出的组件：攻击座→旋转炮管、生产座→烟囱、光环座→信标+半径圈、
## 缓冲座→料箱、冗余座→天线（不表达组件但可见，让同源子代长得不一样）。
## 贴图查 art_registry.gd（§2 素材按部件 kind/allele 命名），映射结构不变。

const ALLELE_COLORS := {
	"shot_light": Color(0.85, 0.85, 0.92),
	"shot_heavy": Color(0.45, 0.45, 0.52),
	"generate_power": Color(1.0, 0.85, 0.2),
	"pump_water": Color(0.35, 0.65, 1.0),
	"mine_ore": Color(0.72, 0.52, 0.32),
	"synth_special": Color(0.82, 0.42, 0.92),
	"slow_field": Color(0.55, 0.88, 1.0),
	"damage_up": Color(1.0, 0.58, 0.22),
	"s": Color(0.62, 0.52, 0.42),
	"m": Color(0.72, 0.62, 0.52),
	"l": Color(0.82, 0.72, 0.62),
}
const COLOR_BASE := Color(0.52, 0.58, 0.64)

var world
var entity_id: int = 0
var _parts: Array = [] # parts_for 输出：[{kind, allele, ...}]
var _barrel: Barrel = null
var _attack_range: float = 0.0
var _cell: float = 64.0
var _base_tex: Texture2D = null


## 炮管子图层：绕自身原点（格心）旋转，朝向目标（FactoryView._process 驱动）。
## 素材炮口朝上（-Y），绘制时 +90° 旋转把炮口转到 +X（look_at 的目标方向）。
class Barrel extends Node2D:
	var texture: Texture2D = null
	var size: float = 28.0

	func _draw() -> void:
		if texture == null:
			# 兜底：矢量细矩形（贴图缺失时不伪造外观，但炮管可见性不能丢）
			draw_rect(Rect2(0.0, -size * 0.12, size, size * 0.24), Color(0.85, 0.85, 0.9))
			return
		draw_set_transform(Vector2.ZERO, PI * 0.5, Vector2.ONE)
		draw_texture_rect(texture, Rect2(-size * 0.5, -size, size, size), false)


func setup(w, eid: int) -> void:
	world = w
	entity_id = eid
	if w != null and w.grid != null:
		_cell = float(w.grid.cell_size)
	var fac = w.get_component(eid, &"Factory")
	if fac == null:
		push_warning("[工厂视图] 实体 %d 无 Factory 组件" % eid)
		return
	_base_tex = Art.tex(str(Art.PARTS["base"]))
	_parts = parts_for(fac.genome, w.config.genes)
	var atk = w.get_component(eid, &"Attack")
	if atk != null:
		_attack_range = atk.range
		_barrel = Barrel.new()
		var allele := _allele_of("barrel")
		var heavy := allele == "shot_heavy"
		_barrel.texture = Art.tex(str(Art.PARTS["barrel_heavy" if heavy else "barrel_light"]))
		_barrel.size = _cell * (0.5 if heavy else 0.42)
		add_child(_barrel)
	queue_redraw()


## 基因组 → 部件描述数组（纯函数，可 headless 单测）。
## kind: barrel / chimney / crate / beacon / aura_ring / antenna。
static func parts_for(genome: Array, genes: Dictionary) -> Array:
	var loci: Array = genes.get("loci", [])
	var out: Array = []
	for i in genome.size():
		var g = genome[i]
		if g == null or i >= loci.size():
			continue
		var kind := str((loci[i] as Dictionary).get("kind", ""))
		var allele := GenomeScript.allele_at(g, i, genes)
		if allele.is_empty():
			continue
		match kind:
			"attack":
				out.append({ "kind": "barrel", "allele": allele })
			"production":
				out.append({ "kind": "chimney", "allele": allele })
			"aura":
				out.append({ "kind": "beacon", "allele": allele })
				var params: Dictionary = (g as Dictionary).get("params", {})
				out.append({ "kind": "aura_ring", "allele": allele,
					"radius": float(params.get("radius", 130.0)) })
			"buffer":
				out.append({ "kind": "crate", "allele": allele })
			"redundant":
				out.append({ "kind": "antenna", "allele": allele })
	return out


## 等位基因 → 部件颜色（光环圈/兜底用）；未收录的等位基因按名字哈希给稳定色（新等位基因零改动可见）。
static func color_of(allele: String) -> Color:
	if ALLELE_COLORS.has(allele):
		return ALLELE_COLORS[allele]
	return Color.from_hsv(float(allele.hash() % 360) / 360.0, 0.5, 0.9)


func _process(_dt: float) -> void:
	if world == null or _barrel == null or not world.is_alive(entity_id):
		return
	# 炮管朝向射程内最近敌人；无敌情时默认朝上（规则在 TargetingSystem #7）。
	# 全程在**逻辑坐标**里算：本节点是 EntityLayer（含缩放/平移）的子节点，global_position
	# 是屏幕空间，与敌人坐标不同源，混用会让距离与朝向一起错（曾致炮管朝上/下不转）。
	var origin = EntityLocator.position(world, entity_id)
	if origin == null:
		return
	var best: Vector2 = origin + Vector2(0.0, -1.0)
	var best_d: float = _attack_range
	for id in world.query(&"PathFollower"):
		var ep = EntityLocator.position(world, id)
		if ep == null:
			continue
		var d: float = origin.distance_to(ep)
		if d <= best_d:
			best_d = d
			best = ep
	var aim: Vector2 = best - origin
	if aim.length() > 0.001:
		_barrel.rotation = aim.angle()


func _draw() -> void:
	var s := _cell * 0.7 # 底座边长（≈占位期 0.7× 缩放的既有观感）
	if _base_tex != null:
		draw_texture_rect(_base_tex, Rect2(-s * 0.5, -s * 0.5, s, s), false)
	else:
		# 贴图缺失兜底：保留矢量底座，不伪造
		draw_rect(Rect2(-s * 0.5, -s * 0.5, s, s), COLOR_BASE)
		draw_rect(Rect2(-s * 0.5, -s * 0.5, s, s), Color(0.2, 0.24, 0.28), false, 2.0)
	var antenna_i := 0
	for p in _parts:
		var allele := str(p["allele"])
		match str(p["kind"]):
			"chimney": # 生产设施：右上角烟囱（贴图按等位基因取色，见 Art.CHIMNEY）
				var ctex: Texture2D = Art.tex(str(Art.CHIMNEY.get(allele, Art.CHIMNEY_FALLBACK)))
				if ctex != null:
					var ps := s * 0.45
					draw_texture_rect(ctex, Rect2(s * 0.12, -s * 0.72, ps, ps), false)
			"crate": # 缓冲：左下料箱（s/m/l 档位缩放贴图）
				var btex: Texture2D = Art.tex(str(Art.PARTS["crate"]))
				if btex != null:
					var cscale: float = { "s": 0.28, "m": 0.36, "l": 0.44 }.get(allele, 0.36)
					var cs := s * cscale
					draw_texture_rect(btex, Rect2(-s * 0.5, s * 0.5 - cs, cs, cs), false)
			"beacon": # 光环装置：顶部信标
				var etex: Texture2D = Art.tex(str(Art.PARTS["beacon"]))
				if etex != null:
					var es := s * 0.34
					draw_texture_rect(etex, Rect2(-es * 0.5, -s * 0.5 - es * 0.6, es, es), false)
			"aura_ring": # 光环半径指示（美术需求表 §8，保留矢量弧）
				draw_arc(Vector2.ZERO, float(p["radius"]), 0.0, TAU, 48, Color(color_of(allele), 0.45), 2.0)
			"antenna": # 冗余基因天线：沿底座上沿排开
				var atex: Texture2D = Art.tex(str(Art.PARTS["antenna"]))
				if atex != null:
					var ax := (-0.3 + 0.2 * antenna_i) * s
					var asz := s * 0.3
					draw_texture_rect(atex, Rect2(ax - asz * 0.5, -s * 0.5 - asz, asz, asz), false)
				antenna_i += 1


func _allele_of(kind: String) -> String:
	for p in _parts:
		if str(p["kind"]) == kind:
			return str(p["allele"])
	return ""
