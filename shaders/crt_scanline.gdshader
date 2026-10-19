shader_type canvas_item;
render_mode blend_mix, unshaded;

// CRT 整屏滤镜：扫描线 + 圆角黑边（显像管外壳）+ 鱼眼（桶形畸变）。
// 鱼眼必须重采样整屏，故本 shader 输出不透明整屏画面（触发一次 backbuffer copy），不是纯叠加。
// 由 autoload CrtOverlay 挂在最上层 CanvasLayer 的全屏 ColorRect 上，覆盖整屏（含 UI）。
// 尺寸类参数（条纹、黑边）按渲染像素（stretch 逻辑分辨率 1600x900）计，随窗口整体缩放，不会忽密忽疏。

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;

// 视口逻辑尺寸（像素），由 crt_overlay.gd 在尺寸变化时写入；用于把黑边像素换算成 UV
uniform vec2 screen_size = vec2(1600.0, 900.0);

// —— 扫描线 ——
uniform float line_spacing : hint_range(2.0, 16.0) = 5.0;   // 条纹周期（像素）：每 N 行重复一次（当前由脚本覆盖为 5.0）
uniform float line_width : hint_range(0.5, 16.0) = 2.0;     // 一个周期内暗线占的宽度（像素）
uniform float line_alpha : hint_range(0.0, 1.0) = 0.25;     // 暗线不透明度（0 = 关闭）
uniform vec3 line_color : source_color = vec3(0.0, 0.0, 0.0);
uniform float edge_softness : hint_range(0.0, 2.0) = 1.0;   // 暗线边缘羽化宽度（像素）

// —— 鱼眼（桶形畸变）——
uniform float fisheye : hint_range(0.0, 1.0) = 0.04;        // 0 = 关闭；0.3 以上明显（脚本按常量覆盖）

// —— CRT 黑边（画面四周一圈黑框，显像管外壳）——
uniform float border_size : hint_range(0.0, 200.0) = 12.0;    // 黑边宽度（像素，0 = 无黑边，脚本按常量覆盖）
uniform float border_radius : hint_range(0.0, 400.0) = 56.0;  // 内框圆角半径（像素）
uniform float border_softness : hint_range(0.0, 60.0) = 12.0; // 黑边内侧羽化（像素）
uniform float border_alpha : hint_range(0.0, 1.0) = 1.0;      // 黑边不透明度

void fragment() {
	// 桶形畸变：以屏幕中心为原点，按半径平方向外扩张采样点
	vec2 centered = SCREEN_UV - 0.5;
	vec2 uv = 0.5 + centered * (1.0 + fisheye * 2.0 * dot(centered, centered));
	vec3 col = texture(screen_tex, clamp(uv, vec2(0.0), vec2(1.0))).rgb;

	// 扫描线
	float spacing = max(line_spacing, 1.0);
	float width = clamp(line_width, 0.0, spacing);
	// FRAGCOORD = 渲染目标绝对像素坐标，整屏连续，不受本节点位置影响
	float phase = mod(FRAGCOORD.y, spacing);
	// phase 落在 [0, width) 为暗线，边界做 edge_softness 羽化，避免硬锯齿
	float mask = 1.0 - smoothstep(width - edge_softness * 0.5, width + edge_softness * 0.5, phase);
	col = mix(col, line_color, mask * line_alpha);

	// 圆角矩形 SDF：d < 0 在画面内，d > 0 落在黑边里
	// 用 UV × screen_size 换到逻辑像素坐标（SCREEN_PIXEL_SIZE 在本 shader 里不可靠，由脚本传 screen_size）
	vec2 half_px = 0.5 * screen_size;
	vec2 p = UV * screen_size - half_px;
	vec2 box = half_px - vec2(border_size);
	float rad = min(border_radius, max(min(box.x, box.y), 0.0));
	vec2 q = abs(p) - box + vec2(rad);
	float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - rad;
	float soft = max(border_softness, 0.001);
	float black = smoothstep(-soft, soft, d) * border_alpha;
	col = mix(col, vec3(0.0), black);

	COLOR = vec4(col, 1.0);
}
