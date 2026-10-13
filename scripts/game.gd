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
const GenomeScript = preload("res://scripts/dna/genome.gd")

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
var _fusion_on := false
var _fusion_sel: Array = [] # 融合已选格（Vector2i，最多 2）
var _last_fusion_cells: Array = [] # 上次注入的工厂格高亮集合


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
	ui.fusion_toggled.connect(_on_fusion_toggled)
	ui.fusion_confirmed.connect(_on_fusion_confirmed)
	ui.factory_cell_clicked.connect(_on_factory_cell_clicked)
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
	_sync_fusion_preview()


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


# ---------------------------------------------------------------- 融合（DNA 系统）

func _on_fusion_toggled(on: bool) -> void:
	_fusion_on = on
	_fusion_sel.clear()
	_last_fusion_cells = []
	if not on:
		ui.set_placement_preview([])
	_sync_fusion_preview(true)


func _on_factory_cell_clicked(cell: Vector2i) -> void:
	var c = world.grid.get_cell(cell)
	var eid: int = c.occupant if c != null else 0
	if eid == 0 or not world.has_component(eid, &"Factory"):
		_push_receipt("!", "格子 %s 上没有可融合的工厂" % str(cell))
		return
	var idx := _fusion_sel.find(cell)
	if idx >= 0:
		_fusion_sel.remove_at(idx)
	else:
		if _fusion_sel.size() >= 2:
			_fusion_sel.pop_front()
		_fusion_sel.append(cell)
	ui.set_fusion_selection(_fusion_sel.size())
	_sync_fusion_preview(true)


func _on_fusion_confirmed(seed: int) -> void:
	if _fusion_sel.size() != 2:
		_push_receipt("!", "先点选 2 个已放置的工厂再确定（已选 %d）" % _fusion_sel.size())
		return
	var ids: Array = []
	for cell in _fusion_sel:
		var c = world.grid.get_cell(cell)
		ids.append(c.occupant if c != null else 0)
	world.push_command({ "type": "fuse", "a": ids[0], "b": ids[1], "seed": seed })
	_fusion_sel.clear()
	ui.set_fusion_selection(0)
	_push_receipt("🧬", "减数分裂启动（种子 %d）……子代卡将入手" % seed)


## 融合模式下把工厂所在格注入放置预览层高亮；集合变化才重注入，避免每帧重绘。
func _sync_fusion_preview(force: bool = false) -> void:
	if not _fusion_on or world == null:
		return
	var cells: Array = []
	for cell in world.grid.cells:
		var c = world.grid.cells[cell]
		if c.occupant != 0 and world.has_component(c.occupant, &"Factory"):
			cells.append(cell)
	if force or cells != _last_fusion_cells:
		_last_fusion_cells = cells
		ui.set_placement_preview(cells)


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
	var cost: Dictionary = cfg["cost"]
	var cost_parts := []
	for rid in cost:
		cost_parts.append("%s×%d" % [rid, int(cost[rid])])
	var desc := "费用: " + (", ".join(cost_parts) if not cost_parts.is_empty() else "无")
	var dna := ""
	var dna_ui := {}
	var display_name := str(cfg.get("name", cid))
	if kind == "factory":
		# 基因组挂在蓝图上（cards.json 条目没有 genome），按 effect.blueprint_id 查
		var bp: Dictionary = config.get_blueprint(StringName(str(eff.get("blueprint_id", ""))))
		if bp.has("genome"):
			# 表型命名（策划案 15.6）：卡面显示名 = 基因组解码出的能力组合名
			display_name = GenomeScript.phenotype_name(bp["genome"], config.genes)
			desc += "\n" + GenomeScript.effect_text(bp["genome"], config.genes, config)
			dna = GenomeScript.sequence_text(bp["genome"], config.genes)
			dna_ui = _build_dna_ui(display_name, bp["genome"], dna)
	else:
		# 地块卡也有 DNA：地块基因 = 地形规则（减速倍率等，levels.json tile_types）
		var ttype := StringName(str(eff.get("tile_type", "")))
		var level: Dictionary = config.get_level(level_id)
		var tmult := float((level.get("tile_types", {}) as Dictionary).get(ttype, {}).get("speed_mult", 1.0))
		desc += "\n放置地块: %s（敌人速度×%.1f）" % [ttype, tmult]
		dna = "1. tile_type: %s（敌人速度×%.1f）" % [ttype, tmult]
		dna_ui = { "title": display_name, "bases": ["·"], "locus_names": ["地块"],
			"rules": ["地块基因：%s — 放置后改变地形规则（敌人速度×%.1f）" % [ttype, tmult]], "debug": dna }
	var icon := str(UI_ICONS.get(String(cid), "🧬" if String(cid).begins_with("card_fusion_") else "▢"))
	return {
		"id": String(cid),
		"name": display_name,
		"kind": kind,
		"icon": icon,
		"desc": desc,
		"dna": dna, # 调试视图原始序列
		"dna_ui": dna_ui, # 玩家检视载荷（dna_inspector 预制体契约：title/bases/locus_names/rules/debug）
	}


## 碱基链 + 座名 + 规则 → DNA 检视载荷；规则里的数字全部来自 genes.json，零硬编码。
func _build_dna_ui(title: String, genome: Array, debug_text: String) -> Dictionary:
	var loci: Array = config.genes.get("loci", [])
	var locus_names := []
	for l in loci:
		locus_names.append(str((l as Dictionary).get("name", (l as Dictionary).get("id", ""))))
	var g: Dictionary = config.genes
	var mut: Dictionary = g.get("mutation", {})
	var rules := [
		"配对：A–T、C–G 互补成对，每个基因座成双存在",
		"配子：融合时每座以 %d%% 概率保留一条链" % int(round(float(g.get("gamete_keep", 0.5)) * 100.0)),
		"互换：%d%% 概率双亲链整段交换" % int(round(float(g.get("crossover", 0.5)) * 100.0)),
		"突变：每座 %d%%（冗余座 %d%%）；数值 ±%d%%，功能座换同组基因" % [
			int(round(float(mut.get("rate", 0.05)) * 100.0)),
			int(round(float(mut.get("redundant_rate", 0.2)) * 100.0)),
			int(round(float(mut.get("drift", 0.15)) * 100.0))],
	]
	return { "title": title, "bases": GenomeScript.base_letters(genome, config.genes),
		"locus_names": locus_names, "rules": rules, "debug": debug_text }


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
