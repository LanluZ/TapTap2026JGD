shader_type canvas_item;
render_mode blend_mix, unshaded;

// 主菜单远景背景（scenes/menu.tscn 的 背景1）：周期性水波扭曲。
// 一条横向波带从画面底部升起、扫过整幅、从顶部离场，带内像素按正弦做水平位移，
// 像隔着一层水看后面的城市；扫完静默 ripple_gap 秒再来一次。
// 只改采样位置、不改颜色——远景本身是偏冷的柔和画面，加高光会抢 Logo 的注意力。
// 位移只在 UV.x 方向；左右边缘按 ripple_edge 衰减，否则越界采样会被 clamp 到边缘像素拉出竖丝。
// UV.y 的 0 在贴图顶部、1 在底部，所以波带中心是从 1+w 走到 -w（两头都在画面外，出场/离场无需淡出）。

uniform float ripple_cycle : hint_range(0.5, 20.0) = 4.0;   // 一次从底扫到顶的时长（秒）
uniform float ripple_gap : hint_range(0.0, 30.0) = 6.0;     // 两次波纹之间的静默时长（秒）
uniform float ripple_amp : hint_range(0.0, 0.04) = 0.009;   // 波峰处的水平位移（UV，0.009 ≈ 贴图宽的 1.8%）
uniform float ripple_width : hint_range(0.02, 0.5) = 0.16;  // 波带半宽（UV.y）
uniform float ripple_bands : hint_range(0.5, 8.0) = 2.5;    // 带内横纹条数
uniform float ripple_wobble : hint_range(0.0, 8.0) = 1.6;   // 横纹自身的相位流动速度
uniform float ripple_edge : hint_range(0.001, 0.15) = 0.03; // 左右边缘衰减宽度（UV.x）
uniform float ripple_phase = 0.0;                           // 相位偏移（秒），让以后多层背景错开

// 顶点色（Sprite2D 的 modulate）单独取出来：Godot 4 里 fragment 内建的 COLOR 已是「贴图 × 顶点色」，
// 直接乘 texture() 会把贴图平方、整层发暗（实测中心像素 0.114/0.326/0.502 → 0.012/0.106/0.251）。
varying vec4 v_modulate;


void vertex() {
	v_modulate = COLOR;
}


void fragment() {
	float cycle = max(ripple_cycle, 0.05);
	float period = cycle + max(ripple_gap, 0.0);
	float prog = clamp(mod(TIME + ripple_phase, period) / cycle, 0.0, 1.0);

	float w = max(ripple_width, 0.01);
	float center = (1.0 + w) - prog * (1.0 + 2.0 * w);
	float dy = UV.y - center;
	float band = smoothstep(w, 0.0, abs(dy));   // 波带中心 1、边界 0

	float e = max(ripple_edge, 1e-4);
	float fade = smoothstep(0.0, e, UV.x) * smoothstep(0.0, e, 1.0 - UV.x);
	float ripple = sin(dy / w * ripple_bands * 3.14159 + TIME * ripple_wobble);

	vec2 uv = UV;
	uv.x += ripple * band * fade * ripple_amp;
	COLOR = texture(TEXTURE, uv) * v_modulate;
}
