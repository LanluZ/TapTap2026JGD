shader_type canvas_item;
render_mode blend_mix, unshaded;

// CRT 扫描线条纹：纯叠加暗线，不采样屏幕纹理（无需 BackBufferCopy，开销可忽略）。
// 由 autoload CrtOverlay 挂在最上层 CanvasLayer 的全屏 ColorRect 上，覆盖整屏（含 UI）。
// 条纹按渲染目标像素（stretch 逻辑分辨率 1600x900）计算，随窗口整体缩放，不会随窗口尺寸变化而忽密忽疏。

uniform float line_spacing : hint_range(2.0, 16.0) = 4.0;   // 条纹周期（像素）：每 N 行重复一次
uniform float line_width : hint_range(0.5, 16.0) = 2.0;     // 一个周期内暗线占的宽度（像素）
uniform float line_alpha : hint_range(0.0, 1.0) = 0.35;     // 暗线不透明度（0 = 关闭）
uniform vec3 line_color : source_color = vec3(0.0, 0.0, 0.0);
uniform float edge_softness : hint_range(0.0, 2.0) = 1.0;   // 暗线边缘羽化宽度（像素）

void fragment() {
	float spacing = max(line_spacing, 1.0);
	float width = clamp(line_width, 0.0, spacing);
	// FRAGCOORD = 渲染目标绝对像素坐标，整屏连续，不受本节点位置影响
	float phase = mod(FRAGCOORD.y, spacing);
	// phase 落在 [0, width) 为暗线，边界做 edge_softness 羽化，避免硬锯齿
	float mask = 1.0 - smoothstep(width - edge_softness * 0.5, width + edge_softness * 0.5, phase);
	COLOR = vec4(line_color, mask * line_alpha);
}
