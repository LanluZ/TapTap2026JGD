class_name FactoryView
extends Node2D
## 工厂表现视图（DNA 外形，美术需求表 §2）：按实体基因组拼装部件子图层。
## 部件 = 表达出的组件：攻击座→旋转炮管、生产座→烟囱、光环座→信标+半径圈、
## 缓冲座→料箱、冗余座→天线（不表达组件但可见，让同源子代长得不一样）。
## 当前为矢量占位绘制；正式素材到位后按 parts_for 的 kind/allele 换贴图，
## 映射结构不变（美术按 allele 命名部件文件即可）。

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


## 炮管子图层：绕自身原点（格心）旋转，朝向目标（FactoryView._process 驱动）。
class Barrel extends Node2D:
	var length: float = 22.0
	var width: float = 4.0
	var color: Color = Color.WHITE

	func _draw() -> void:
		draw_rect(Rect2(0.0, -width * 0.5, length, width), color)
		draw_circle(Vector2(length, 0.0), width * 0.8, color.darkened(0.25))


func setup(w, eid: int) -> void:
	world = w
	entity_id = eid
	if w != null and w.grid != null:
		_cell = float(w.grid.cell_size)
	var fac = w.get_component(eid, &"Factory")
	if fac == null:
		push_warning("[工厂视图] 实体 %d 无 Factory 组件" % eid)
		return
	_parts = parts_for(fac.genome, w.config.genes)
	var atk = w.get_component(eid, &"Attack")
	if atk != null:
		_attack_range = atk.range
		_barrel = Barrel.new()
		_barrel.length = _cell * (0.42 if String(atk.projectile) == "ore_shot" else 0.5)
		_barrel.width = _cell * (0.06 if String(atk.projectile) == "ore_shot" else 0.12)
		_barrel.color = color_of(_allele_of("barrel"))
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
		var allele := str((g as Dictionary).get("allele", ""))
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


## 等位基因 → 部件颜色；未收录的等位基因按名字哈希给稳定色（新等位基因零改动可见）。
static func color_of(allele: String) -> Color:
	if ALLELE_COLORS.has(allele):
		return ALLELE_COLORS[allele]
	return Color.from_hsv(float(allele.hash() % 360) / 360.0, 0.5, 0.9)


func _process(_dt: float) -> void:
	if world == null or _barrel == null or not world.is_alive(entity_id):
		return
	# 炮管朝向射程内最近敌人；无敌情时默认朝上（占位表现，规则在 TargetingSystem #7）
	var origin := global_position
	var best := origin + Vector2(0.0, -1.0)
	var best_d := _attack_range
	for id in world.query(&"PathFollower"):
		var ep = EntityLocator.position(world, id)
		if ep == null:
			continue
		var d: float = origin.distance_to(ep)
		if d <= best_d:
			best_d = d
			best = ep
	_barrel.look_at(best)


func _draw() -> void:
	var s := _cell * 0.7 # 底座边长（≈占位期 0.7× 缩放的既有观感）
	draw_rect(Rect2(-s * 0.5, -s * 0.5, s, s), COLOR_BASE)
	draw_rect(Rect2(-s * 0.5, -s * 0.5, s, s), Color(0.2, 0.24, 0.28), false, 2.0)
	var antenna_i := 0
	for p in _parts:
		var allele := str(p["allele"])
		var color := color_of(allele)
		match str(p["kind"]):
			"chimney": # 生产设施：右上角烟囱
				var w0 := s * 0.18
				draw_rect(Rect2(s * 0.16, -s * 0.5 - s * 0.22, w0, s * 0.24), color)
				draw_rect(Rect2(s * 0.16, -s * 0.5 - s * 0.22, w0, s * 0.24), Color(0.2, 0.2, 0.24), false, 1.5)
			"crate": # 缓冲：左下料箱
				var cs := s * 0.3
				draw_rect(Rect2(-s * 0.5, s * 0.5 - cs, cs, cs), color)
				draw_rect(Rect2(-s * 0.5, s * 0.5 - cs, cs, cs), Color(0.2, 0.2, 0.24), false, 1.5)
			"beacon": # 光环装置：顶部信标
				draw_circle(Vector2(0.0, -s * 0.5), s * 0.12, color)
				draw_circle(Vector2(0.0, -s * 0.5), s * 0.12, Color(0.2, 0.2, 0.24), false, 1.5)
			"aura_ring": # 光环半径指示（美术需求表 §8）
				draw_arc(Vector2.ZERO, float(p["radius"]), 0.0, TAU, 48, Color(color, 0.45), 2.0)
			"antenna": # 冗余基因天线：沿底座上沿排开
				var ax := (-0.3 + 0.2 * antenna_i) * s
				draw_line(Vector2(ax, -s * 0.5), Vector2(ax, -s * 0.5 - s * 0.25), color, 2.0)
				draw_circle(Vector2(ax, -s * 0.5 - s * 0.25), s * 0.05, color)
				antenna_i += 1


func _allele_of(kind: String) -> String:
	for p in _parts:
		if str(p["kind"]) == kind:
			return str(p["allele"])
	return ""
