extends SceneTree
## 放置幽灵预览验证（headless，非视觉）：
##   ① FactoryView.setup_blueprint：有攻击座的蓝图 → 装配炮管 + _preview_range = express 的 Attack.range；
##      无攻击座的蓝图 → 无炮管、_preview_range = 0（不画射程圈）
##   ② 接线：选中工厂卡 → 幽灵装配；鼠标悬停可放格 → 幽灵可见且在该格中心（世界坐标）；
##      悬停非可放格 / 取消放置 → 隐藏；选中地块卡 → 不装配
## 运行：godot --headless --path <项目目录> -s res://tests/placement_ghost_test.gd
## 退出码：0 = 全部通过；非 0 = 失败项数。不做视觉观感结论。

const BootstrapScript = preload("res://scripts/bootstrap.gd")
const GenomeScript = preload("res://scripts/dna/genome.gd")
const FactoryViewScript = preload("res://scripts/views/factory_view.gd")

var _checks: int = 0
var _failures: int = 0
var _ui = null
var _frames := 0
var _done := false


func _init() -> void:
	_test_setup_blueprint()
	# main.tscn 里的 main_ui.gd 引用自动加载单例（SceneTransition 等），必须等自动加载就位后再加载场景；
	# 放 _init 里会编译失败（Identifier not found），故推迟到首帧前的 deferred 拍。
	call_deferred("_instantiate_scene")


func _instantiate_scene() -> void:
	var packed = load("res://scenes/main.tscn")
	_ok(packed is PackedScene, "main.tscn 可加载")
	if packed is PackedScene:
		_ui = (packed as PackedScene).instantiate()
		root.add_child(_ui)


## 场景要等 deferred 实例化 + 几个逻辑帧（Game/UI 的 _ready 与场地几何排期）后才可断言
func _process(_dt: float) -> bool:
	if _done:
		return true
	_frames += 1
	if _ui == null:
		if _frames > 60:
			_failures += 1
			printerr("  [FAIL] main.tscn 未在 60 帧内实例化")
			quit(_failures)
			_done = true
			return true
		return false
	if _frames < 3: # 等 _init_ui 的 call_deferred 场地几何排期落地（overlay 才有格尺寸）
		return false
	_test_ghost_wiring(_ui)
	_ui = null
	_done = true
	print("======== 放置幽灵: %d/%d 通过，%d 失败 ========" % [_checks - _failures, _checks, _failures])
	quit(_failures)
	return true


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("  [PASS] " + label)
	else:
		_failures += 1
		printerr("  [FAIL] " + label)


# ---------------------------------------------------------------- ① 蓝图装配

func _test_setup_blueprint() -> void:
	print("== ① setup_blueprint 蓝图装配 ==")
	var config = GameConfig.load_all()
	_ok(config != null, "配置加载")
	if config == null:
		return
	var w = BootstrapScript.build_world(config, &"level_1")
	_ok(w != null, "世界构建")
	if w == null:
		return
	# 独立口径判有无攻击座：座0 = attack_type（genes.json 座序），与 express 分别断言、互为交叉
	var with_atk: Dictionary = {}
	var without_atk: Dictionary = {}
	for bid in config.blueprints:
		var bp: Dictionary = config.blueprints[bid]
		if not bp.has("genome"):
			continue
		var g: Array = bp["genome"]
		if g.is_empty():
			continue
		if g[0] != null:
			if with_atk.is_empty():
				with_atk = { "id": String(bid), "genome": g }
		elif without_atk.is_empty():
			without_atk = { "id": String(bid), "genome": g }
	_ok(not with_atk.is_empty(), "找到带攻击座的蓝图")
	_ok(not without_atk.is_empty(), "找到无攻击座的蓝图")
	if with_atk.is_empty() or without_atk.is_empty():
		return

	var want := _range_of(config, with_atk["genome"])
	var atk_ghost = FactoryViewScript.new()
	atk_ghost.setup_blueprint(w, with_atk["genome"], want)
	_ok(float(atk_ghost.get("_preview_range")) > 0.0,
		"攻击蓝图 _preview_range > 0（%s = %s 世界单位）" % [with_atk["id"], str(atk_ghost.get("_preview_range"))])
	_ok(atk_ghost.get_children().size() == 1,
		"攻击蓝图装配 1 个炮管子图层（实际 %d）" % atk_ghost.get_children().size())
	_ok(not (atk_ghost.get("_parts") as Array).is_empty(), "攻击蓝图部件表非空")
	# 射程圈与落地规格同源：express 出来的 Attack.range 必须等于画圈半径
	_ok(is_equal_approx(float(atk_ghost.get("_preview_range")), want),
		"射程圈半径 = express 的 Attack.range（%s）" % str(want))
	# 真实工厂口径不被污染：幽灵不碰 _attack_range
	_ok(is_equal_approx(float(atk_ghost.get("_attack_range")), 0.0), "幽灵 _attack_range 保持 0（非真实工厂）")

	# 重复装配（换工厂卡重选）不累积炮管子图层
	atk_ghost.setup_blueprint(w, with_atk["genome"], want)
	atk_ghost.setup_blueprint(w, with_atk["genome"], want)
	_ok(atk_ghost.get_children().size() == 1,
		"重复装配后仍只有 1 个炮管（实际 %d）" % atk_ghost.get_children().size())

	var plain_ghost = FactoryViewScript.new()
	plain_ghost.setup_blueprint(w, without_atk["genome"], _range_of(config, without_atk["genome"]))
	_ok(is_equal_approx(float(plain_ghost.get("_preview_range")), 0.0),
		"无攻击蓝图 _preview_range = 0（不画圈）")
	_ok(plain_ghost.get_children().is_empty(), "无攻击蓝图不装配炮管")


## 蓝图射程（世界单位）：与 Game._attack_range_of 同源
func _range_of(config, genome: Array) -> float:
	var specs: Array = GenomeScript.express(genome, config.genes, "", "")
	for s in specs:
		if str(s.get("type", "")) == "Attack":
			return float(s.get("range", 0.0))
	return 0.0


# ---------------------------------------------------------------- ② 接线

func _test_ghost_wiring(ui: Node) -> void:
	print("== ② 选卡/悬停/取消接线 ==")
	var game = ui.get_node_or_null("Game")
	var overlay = ui.get_node_or_null("PlacementOverlay")
	_ok(game != null and overlay != null, "Game 与 PlacementOverlay 节点在位")
	if game == null or overlay == null:
		return
	var ghost = game.get("_ghost")
	_ok(ghost != null, "幽灵节点已创建")
	if ghost == null:
		return
	_ok(not bool(ghost.visible), "初始隐藏")
	_ok(is_equal_approx(float(ghost.modulate.a), 0.6), "半透明 modulate.a = 0.6")

	# 选中工厂卡（走真实 UI 入口 → 转发 card_selected → Game 装配）
	var factory_card: Dictionary = game.call("_ui_card_of", "card_gun_turret")
	_ok(str(factory_card.get("kind", "")) == "factory", "card_gun_turret 是工厂卡")
	ui.call("_on_card_selected", factory_card)
	_ok(str(game.get("_ghost_card_id")) == "card_gun_turret", "幽灵已按该卡装配")
	_ok(float(ghost.get("_preview_range")) > 0, "枪塔幽灵带射程圈半径（攻击模组）")
	_ok(bool(overlay.call("is_active")), "放置预览层已激活")

	var valid: Dictionary = game.get("_valid_cells")
	_ok(not valid.is_empty(), "可放格集合非空（%d 格）" % valid.size())
	if valid.is_empty():
		return
	var cell: Vector2i = valid.keys()[0]

	# 悬停可放格 → 幽灵显示在该格中心
	_hover(overlay, cell)
	_ok(overlay.call("get_hover") == cell, "overlay.get_hover 返回悬停格 %s" % str(cell))
	game.call("_sync_ghost")
	_ok(bool(ghost.visible), "悬停可放格 → 幽灵可见")
	var w = game.get("world")
	_ok(ghost.position.is_equal_approx(w.grid.cell_to_world(cell)),
		"幽灵位置 = 格中心 %s（实际 %s）" % [str(w.grid.cell_to_world(cell)), str(ghost.position)])

	# 画面级对齐：main.tscn 无相机/CanvasLayer，两层同 canvas —— 幽灵全局坐标必须落在预览层那格矩形中心
	var cell_center: Vector2 = (overlay.call("cell_rect", cell) as Rect2).get_center()
	var ghost_pos: Vector2 = ghost.global_position
	var dev: float = ghost_pos.distance_to(cell_center)
	_ok(dev <= 1.0, "幽灵画面位置 = 预览层格中心 %s（偏差 %.2fpx，实际 %s）" % [str(cell_center), dev, str(ghost_pos)])

	# 两层格子变换必须同源（架构 §2b：不同源则实体与格线错位）：显示格宽 = 逻辑格 64 × EntityLayer 缩放
	var el = game.get("_entity_layer")
	var display_cell: float = float((overlay.get("_cell_size") as Vector2i).x)
	var k: float = float((el.scale as Vector2).x)
	var logic_cell: float = float(w.grid.cell_size)
	_ok(absf(logic_cell * k - display_cell) <= 1.0,
		"显示格宽同源（逻辑 %.0f × 缩放 %.4f = %.1f，预览层 %.0f）" % [logic_cell, k, logic_cell * k, display_cell])

	# 攻击模组射程换算：圈半径(屏幕) / 显示格宽 = DNA 射程 / 逻辑格宽（单位换算不串层）
	var screen_range: float = float(ghost.get("_preview_range")) * k
	var span: float = screen_range / display_cell
	var want_span: float = float(ghost.get("_preview_range")) / logic_cell
	_ok(absf(span - want_span) <= 0.01,
		"射程圈跨 %.2f 格 = DNA 射程/逻辑格 %.2f" % [span, want_span])

	# 悬停不可放格 → 隐藏（粉红高亮仍由放置预览层负责）
	var blocked := _first_blocked(w, valid)
	if blocked != Vector2i(-1, -1):
		_hover(overlay, blocked)
		game.call("_sync_ghost")
		_ok(not bool(ghost.visible), "悬停不可放格 %s → 幽灵隐藏" % str(blocked))
	else:
		_ok(true, "关卡内无可放格以外的格，跳过不可放格断言")

	# 取消放置 → 隐藏（overlay 一并失活）
	_hover(overlay, cell)
	ui.call("cancel_placement")
	game.call("_sync_ghost")
	_ok(not bool(ghost.visible), "取消放置 → 幽灵隐藏")
	_ok(not bool(overlay.call("is_active")), "取消放置 → 预览层失活")

	# 地块卡选中 → 不装配工厂幽灵
	var tile_card: Dictionary = game.call("_ui_card_of", "card_slow_tile")
	_ok(str(tile_card.get("kind", "")) == "tile", "card_slow_tile 是地块卡")
	ui.call("_on_card_selected", tile_card)
	_ok(str(game.get("_ghost_card_id")).is_empty(), "地块卡不装配幽灵")
	game.call("_sync_ghost")
	_ok(not bool(ghost.visible), "地块卡放置态幽灵仍隐藏")


## 给 overlay 喂一次鼠标移动（走真实 _gui_input 分支）
func _hover(overlay, cell: Vector2i) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = overlay.cell_rect(cell).get_center()
	overlay.call("_gui_input", ev)


## 网格里第一个不在可放集合的格（无 → (-1,-1)）
func _first_blocked(w, valid: Dictionary) -> Vector2i:
	for c in w.grid.cells:
		if not valid.has(c):
			return c
	return Vector2i(-1, -1)
