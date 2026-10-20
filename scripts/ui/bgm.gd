extends Node
## 全局 BGM 单例（autoload 名 Bgm）：title.ogg 全程无缝循环（菜单/游戏中/结算跨场景不断）。
##
## 循环点来自文件元数据（导入后在 stream.tags 里可见）：
##   LOOPSTART=1675826、LOOPLENGTH=3351095（48kHz 单位为帧）→ 起点 34.913s，终点 104.728s，
##   末尾约 35s 尾奏不进循环。
## Godot 4.7 的 Ogg 循环只有 loop + loop_offset（起点），终点靠"beat_count 拍 × 60/bpm"定义，
## 所以 bpm 用 LOOP_END 反推（bpm/beat_count 在本项目里只作时间换算用，不做节拍同步）。
## 循环点在运行时写到流上而不是改 .import：手改 .import 不保证触发重导入，代码里写死常量可被测试断言。

const TRACK := "res://sounds/title.ogg"
const RATE := 48000.0
const LOOP_START_FRAMES := 1675826
const LOOP_END_FRAMES := 5026921 # LOOPSTART + LOOPLENGTH
const BEATS_FOR_END := 100 # 任意整数，只参与 bpm 反推

var _player: AudioStreamPlayer


func _ready() -> void:
	var stream := load(TRACK) as AudioStreamOggVorbis
	if stream == null:
		push_warning("[BGM] 无法加载: " + TRACK)
		return
	stream.loop = true
	stream.loop_offset = LOOP_START_FRAMES / RATE
	stream.beat_count = BEATS_FOR_END
	stream.bpm = BEATS_FOR_END * 60.0 / (LOOP_END_FRAMES / RATE)
	_player = AudioStreamPlayer.new()
	_player.name = "BgmPlayer"
	_player.stream = stream
	add_child(_player)
	_player.play()
