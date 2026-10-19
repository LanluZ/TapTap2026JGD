extends RefCounted
## 场景：无（表现层共享常量表）。作用：美术素材 id → res:// 路径注册表（docs/美术需求表.md 交付素材）。
## 表现层（entity_layer / factory_view / field_layer / hud / card_face）统一查本表取贴图，
## 换素材只改本表路径，不动各视图逻辑。tex() 带加载失败警告与兜底，不伪造贴图。

const ROOT := "res://art/art/"

# ---------------------------------------------------------------- 敌人（data/enemies.json）
## scale = 48px 贴图相对 64 逻辑格的显示倍率（体型差异靠它体现）。
const ENEMY := {
	"slime": { "frames": [ROOT + "怪物/slime1.png", ROOT + "怪物/slime2.png", ROOT + "怪物/slime3.png"], "scale": 0.85 },
	"golem": { "frames": [ROOT + "怪物/golem1.png", ROOT + "怪物/golem2.png"], "scale": 1.0 },
	"bat": { "frames": [ROOT + "怪物/bat1.png", ROOT + "怪物/bat2.png"], "scale": 0.7 },
	"swarm": { "frames": [ROOT + "怪物/swarm.png"], "scale": 0.6 },
	"moth": { "frames": [ROOT + "怪物/moth1.png", ROOT + "怪物/moth2.png"], "scale": 0.75, "alpha": 0.9 },
	"slime_king": { "frames": [ROOT + "怪物/slime king1.png", ROOT + "怪物/slime king2.png", ROOT + "怪物/slime king3.png"], "scale": 1.25 },
}
const ANIM_FPS := 4.0 # 帧动画速度（待机/移动共用）

# ---------------------------------------------------------------- 射弹（factories.json projectiles）
## ore_heavy 无独立素材：复用矿石弹，放大+压暗区分。
const PROJECTILE := {
	"ore_shot": { "tex": ROOT + "射弹/ore shot.png", "scale": 0.6, "modulate": Color(1, 1, 1) },
	"ore_heavy": { "tex": ROOT + "射弹/ore shot.png", "scale": 0.95, "modulate": Color(0.78, 0.72, 0.66) },
}

# ---------------------------------------------------------------- 工厂部件（scripts/views/factory_view.gd）
const PARTS := {
	"base": ROOT + "工厂部件/base.png",
	"barrel_light": ROOT + "工厂部件/shot light.png", # 纯炮管（炮口朝上），旋转子图层用；（+base 合成版不用
	"barrel_heavy": ROOT + "工厂部件/shot heavy.png",
	"beacon": ROOT + "工厂部件/beacon.png",
	"crate": ROOT + "工厂部件/crate.png",
	"antenna": ROOT + "工厂部件/antenna.png",
}
## 生产烟囱按等位基因取色（美术需求表 §2：发电黄/供水蓝/采矿褐/合成紫）；未收录等位基因回落纯色烟囱。
const CHIMNEY := {
	"generate_power": ROOT + "工厂部件/chimney yellow.png",
	"pump_water": ROOT + "工厂部件/chimney blue.png",
	"mine_ore": ROOT + "工厂部件/chimney brown.png",
	"synth_special": ROOT + "工厂部件/chimney purple.png",
}
const CHIMNEY_FALLBACK := ROOT + "工厂部件/chimney.png"

# ---------------------------------------------------------------- 地块（data/levels.json，用户指定分配）
const TILES := {
	"path": ROOT + "地块/groud.png", # 路径格
	"buildable": ROOT + "地块/lawn.png", # 可建造格
	"slow": ROOT + "地块/panel.png", # 减速带（tile_types.id → 同名贴图，未收录的地块类型不绘制）
	# 冰面（两块减速带邻接合成物）：暂无专属素材，复用减速带贴图 + 淡蓝着色区分（FIELD_TINT）
	"ice_field": ROOT + "地块/panel.png",
}
## 地块着色（复用贴图的临时区分手段）：未收录的 tile_type 不着色。
const TILE_TINT := {
	"ice_field": Color(0.62, 0.85, 1.0),
}

# ---------------------------------------------------------------- 资源图标（data/resources.json，HUD 资源条）
const RES_ICON := {
	"parts": ROOT + "资源图标/parts.png",
	"power": ROOT + "资源图标/power.png",
	"water": ROOT + "资源图标/water.png",
	"ore": ROOT + "资源图标/ore.png",
	"special_material": ROOT + "资源图标/special material.png",
}

# ---------------------------------------------------------------- 卡面（data/cards.json，60×84 整卡图）
## 无素材的卡（card_gun_turret_heavy / card_signal_tower / card_command_post）不在表内 → 卡面回退纯文字。
const CARD := {
	"card_generator": ROOT + "card/card generator.png",
	"card_pump": ROOT + "card/card pump.png",
	"card_miner": ROOT + "card/card miner.png",
	"card_assembler": ROOT + "card/card assembler.png",
	"card_gun_turret": ROOT + "card/card gun turret.png",
	"card_frost_beacon": ROOT + "card/card frost beacon.png",
	"card_slow_tile": ROOT + "card/cared slow tile.png", # 素材文件名原样拼写（cared），按磁盘字面引用
}


## 按路径取贴图（load 自带资源缓存）；失败只警告一次并返回 null，调用方自行兜底。
static func tex(path: String) -> Texture2D:
	if path.is_empty():
		return null
	var t: Texture2D = load(path)
	if t == null:
		push_warning("[素材] 加载失败: " + path)
	return t
