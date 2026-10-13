class_name Game
extends Node
## 接线层：逻辑世界（Bootstrap 组装的 ECS）↔ 关卡 UI（main_ui.gd 契约）。
## 只做双向搬运，不含游戏规则：规则全在 scripts/systems/，UI 全在 scripts/ui/。
##
## 挂载：main.tscn 根节点 Main(main_ui.gd) 的子节点 Game。
## 子节点 _ready 先于父节点执行，这里注入真实数据后 UI 的 auto_mock 自动让位。

@export var level_id: StringName = &"level_1"

## preload 而非 class_name：headless/首启类缓存未含新脚本时也能解析
const BootstrapScript = preload("res://scripts/bootstrap.gd")

## 配置 id → UI 资源条 key（策划案 §4：零件/特殊材料/电力/水/矿）
const UI_RESOURCE_KEYS := {
	&"parts": "parts",
	&"special_material": "special",
	&"power": "power",
	&"water": "water",
	&"ore": "ore",
}
const UI_ICONS := {
	"card_generator": "⚡", "card_pump": "💧", "card_miner": "⛏",
	"card_assembler": "🔧", "card_gun_turret": "🔫", "card_frost_beacon": "❄",
	"card_slow_tile": "🛣",
}

var world: World
var config: GameConfig
var ui: Control

var _grid_sys: GridSystem
var _card_sys: CardSystem
var _receipts: Array = []
var _last_hand_ids: Array = []
var _last_res: Dictionary = {}
var _last_wave: int = -1
var _enemy_cap: int = 0
var _wave_total: int = 0
var _over := false


func _ready() -> void:
	ui = get_parent()
	config = GameConfig.load_all()
	if config == null:
		_push_receipt("!", "配置加载失败，无法开始关卡")
		set_physics_process(false)
		return
	if not config.levels.has(level_id):
		_push_receipt("!", "未定义关卡: " + String(level_id))
		set_physics_process(false)
		return
	world = BootstrapScript.build_world(config, level_id)
	if world == null:
		_push_receipt("!", "关卡世界构建失败: " + String(level_id))
		set_physics_process(false)
		return
	var layer := get_node_or_null("../EntityLayer")
	if layer != null and layer.has_method("setup"):
		layer.setup(world) # 表现层占位图（scripts/views/）
	_grid_sys = world.get_system("GridSystem")
	_card_sys = world.get_system("CardSystem")
	var level: Dictionary = config.get_level(level_id)
	_enemy_cap = int(level["enemy_cap"])
	_wave_total = int((level["objective"] as Dictionary).get("waves", 0))
	_connect_world()
	ui.card_selected.connect(_on_card_selected)
	ui.card_played.connect(_on_card_played)
	ui.placement_cancelled.connect(_on_placement_cancelled)
	_init_ui()
	_push_receipt("·", "关卡「%s」开始：撑过 %d 波" % [level.get("name", level_id), _wave_total])


func _physics_process(delta: float) -> void:
	if world == null:
		return
	if world.state.is_playing() and not _over:
		world.tick(delta)
	_sync_ui()


# ---------------------------------------------------------------- 注入方向：逻辑 → UI

func _init_ui() -> void:
	# PlacementOverlay 满屏且局部坐标 = 屏幕坐标（无相机），逻辑网格原点 (0,0) 直接对齐
	var cs := int(world.grid.cell_size)
	ui.set_grid_geometry(Vector2.ZERO, Vector2i(cs, cs), world.grid.cells.keys())
	ui.set_hand_max(_card_sys.deck.hand_max)
	ui.set_wave_info(0, _wave_total)
	ui.set_library_cards(_pool_ui_cards())
	_sync_res()
	_sync_hand()
	_sync_hud()


func _sync_ui() -> void:
	_sync_res()
	_sync_hand()
	_sync_hud()


func _sync_res() -> void:
	var out := {}
	for rid in UI_RESOURCE_KEYS:
		out[UI_RESOURCE_KEYS[rid]] = world.state.get_amount(rid)
	if out != _last_res:
		_last_res = out
		ui.set_resources(out)


func _sync_hand() -> void:
	var hand: Array = _card_sys.deck.hand
	if hand == _last_hand_ids:
		return
	_last_hand_ids = hand.duplicate()
	var out := []
	for cid in hand:
		var d := _ui_card_of(cid)
		if not d.is_empty():
			out.append(d)
	ui.set_hand(out)


func _sync_hud() -> void:
	ui.set_enemy_count(world.state.enemies_on_path, _enemy_cap)
	if world.state.waves_survived != _last_wave:
		_last_wave = world.state.waves_survived
		ui.set_wave_info(_last_wave, _wave_total)


# ---------------------------------------------------------------- 注入方向：UI → 逻辑

## 选中卡牌 → 计算该卡的可放格集合，交给放置预览层高亮
func _on_card_selected(card: Dictionary) -> void:
	var valid := _valid_cells_for(str(card.get("id", "")))
	ui.set_placement_preview(valid)


## 打出卡牌 → play_card 指令（CommandSystem #1 在下一逻辑帧消费）
func _on_card_played(card: Dictionary, cell: Vector2i) -> void:
	var idx := _hand_index_of(str(card.get("id", "")))
	if idx < 0:
		_push_receipt("!", "手牌中找不到卡: %s（可能已被打出）" % str(card.get("id", "")))
		return
	world.push_command({"type": "play_card", "card_index": idx, "cell": cell})


func _on_placement_cancelled() -> void:
	ui.set_placement_preview([])


# ---------------------------------------------------------------- 世界信号 → 回执

func _connect_world() -> void:
	world.command_rejected.connect(func(reason: String): _push_receipt("✗", reason))
	world.wave_completed.connect(func(_i: int):
		_push_receipt("波", "第 %d 波完成" % world.state.waves_survived))
	world.game_won.connect(func():
		_over = true
		_push_receipt("★", "胜利！撑过 %d 波" % world.state.waves_survived))
	world.game_lost.connect(func():
		_over = true
		_push_receipt("☠", "失败：路径敌人达到上限 %d" % _enemy_cap))


func _push_receipt(icon: String, text: String) -> void:
	_receipts.push_front({"icon": icon, "text": text})
	if _receipts.size() > 8:
		_receipts.resize(8)
	if ui != null and ui.has_method("set_receipts"):
		ui.set_receipts(_receipts)


# ---------------------------------------------------------------- 卡牌/格子工具

## 卡配置 → UI 卡面字典 {id,name,kind,icon,desc}（main_ui.gd §手牌 schema）
func _ui_card_of(cid) -> Dictionary:
	var cfg: Dictionary = config.get_card(StringName(cid))
	if cfg.is_empty():
		push_warning("[接线] 未定义卡牌: " + String(cid))
		return {}
	var eff: Dictionary = cfg["effect"]
	var kind := "factory" if str(eff.get("type", "")) == "place_factory" else "tile"
	var target := str(eff.get("blueprint_id", eff.get("tile_type", "")))
	var desc := "放置：%s" % target
	var cost: Dictionary = cfg["cost"]
	if not cost.is_empty():
		var parts := []
		for rid in cost:
			parts.append("%s×%d" % [rid, int(cost[rid])])
		desc += "\n费用: " + ", ".join(parts)
	return {
		"id": String(cid),
		"name": str(cfg.get("name", cid)),
		"kind": kind,
		"icon": str(UI_ICONS.get(String(cid), "▢")),
		"desc": desc,
	}


func _pool_ui_cards() -> Array:
	var out := []
	var level: Dictionary = config.get_level(level_id)
	for cid in level["card_pool"]:
		var d := _ui_card_of(cid)
		if not d.is_empty():
			out.append(d)
	return out


func _hand_index_of(cid: String) -> int:
	var hand: Array = _card_sys.deck.hand
	for i in hand.size():
		if String(hand[i]) == cid:
			return i
	return -1


## 该卡当前的可放格集合（合法性最终仍由逻辑层裁决，这里只做预览）
func _valid_cells_for(cid: String) -> Array:
	var cfg: Dictionary = config.get_card(StringName(cid))
	if cfg.is_empty():
		return []
	var eff: Dictionary = cfg["effect"]
	var out := []
	for cell in world.grid.cells:
		var ok := false
		match str(eff.get("type", "")):
			"place_factory":
				ok = _grid_sys.can_build(world, cell)
			"place_tile":
				ok = _grid_sys.can_place_tile(world, cell)
		if ok:
			out.append(cell)
	return out
