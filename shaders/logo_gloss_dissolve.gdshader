shader_type canvas_item;
render_mode blend_mix, unshaded;

// 主菜单 Logo：对角光泽扫过 + 边缘破损消融（浮动/旋转由 scripts/menu_camera.gd 驱动，着色器只改像素）。
// 光泽方向固定为「左下 → 右上」：沿 (1,1) 对角线推进的软光带。贴图宽高比从 TEXTURE_PIXEL_SIZE 取，
// 1126x230 这种超宽贴图上斜光仍是视觉 45°，不会因为 UV 拉伸变成一条很平的斜线。
// 破损消融用 fbm 噪声，图形边界先烂、内部只掉少量碎块，消融边界染暖色；噪声缓慢漂移 = 边在烧。
// 白字没有向上的亮度余量，所以光泽做成「整体压暗 + 光带还原全亮并偏暖」——像金属字被光扫过。

uniform vec4 base_color : source_color = vec4(1.0);                    // 底色（乘在贴图上）
uniform vec4 gloss_color : source_color = vec4(1.0, 0.90, 0.72, 1.0);  // 光带的暖色
uniform float gloss_strength : hint_range(0.0, 1.0) = 0.55;            // 光带把底色推向 gloss_color 的比例
uniform float gloss_width : hint_range(0.02, 0.8) = 0.2;               // 光带半宽（归一化对角线单位）
uniform float gloss_cycle : hint_range(0.5, 20.0) = 7.0;               // 一次扫过的周期（秒）
uniform float gloss_pause : hint_range(0.0, 0.9) = 0.4;                // 周期中光带停在画面外的比例，避免连续闪
uniform float gloss_shade : hint_range(0.0, 0.6) = 0.16;               // 光带外的基础压暗量

uniform float dissolve_amount : hint_range(0.0, 1.0) = 0.05;           // 破损程度（0 = 完整）
uniform float dissolve_breath : hint_range(0.0, 0.5) = 0.05;           // 破损量的缓慢起伏
uniform float dissolve_scale : hint_range(1.0, 40.0) = 9.0;            // 噪声密度（越大碎块越细）
uniform float dissolve_boil : hint_range(0.0, 2.0) = 0.01;              // 噪声漂移速度
uniform vec4 burn_color : source_color = vec4(1.0, 0.62, 0.28, 1.0);   // 消融边界的暖色
uniform float burn_strength : hint_range(0.0, 2.0) = 0.85;             // 边界染色强度


float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// 3 倍频 fbm，值域大致 0..1（均值 ~0.5）
float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		v += vnoise(p) * amp;
		p = p * 2.07 + vec2(13.0, 27.0);
		amp *= 0.5;
	}
	return v / 0.875;
}


void fragment() {
	// COLOR 进 fragment 时已是「贴图 × 顶点色（modulate）」，直接用，不再重采一次
	vec4 col = COLOR;

	float aspect = TEXTURE_PIXEL_SIZE.y / max(TEXTURE_PIXEL_SIZE.x, 1e-6);
	vec2 q = (UV - 0.5) * vec2(aspect, 1.0);   // 等比空间，原点在贴图中心

	// ---------------- 破损消融 ----------------
	float amount = clamp(dissolve_amount + sin(TIME * 0.5) * dissolve_breath, 0.0, 1.0);

	// 图形边界判定：8 邻域、6 纹素半径的平均盖度。完全被图形包住的内部≈1，靠边≈0；
	// 半径取大是为了让「细笔画整条都算边界」（笔画本身只有十几像素宽），细处先被吃掉。
	vec2 r = TEXTURE_PIXEL_SIZE * 6.0;
	float a_blur = (
		texture(TEXTURE, UV + vec2(r.x, 0.0)).a + texture(TEXTURE, UV - vec2(r.x, 0.0)).a
		+ texture(TEXTURE, UV + vec2(0.0, r.y)).a + texture(TEXTURE, UV - vec2(0.0, r.y)).a
		+ texture(TEXTURE, UV + r).a + texture(TEXTURE, UV - r).a
		+ texture(TEXTURE, UV + vec2(r.x, -r.y)).a + texture(TEXTURE, UV + vec2(-r.x, r.y)).a
	) * 0.125;
	float edge = 1.0 - smoothstep(0.75, 1.0, a_blur);

	vec2 drift = vec2(TIME * 0.03, -TIME * 0.021) * dissolve_boil * 6.0;
	float n = fbm(q * dissolve_scale + drift);

	float cut = 0.17 + 0.42 * amount;          // 阈值基线（默认 amount≈0.13 → 吃掉约 1 成面积）
	float thr = cut + edge * amount * 1.4;     // 边界阈值更高 → 边先烂，内部只掉碎块
	float keep = smoothstep(thr, thr + 0.03, n);
	float rim = (1.0 - smoothstep(0.0, 0.05, n - thr)) * keep;   // 消融边界内侧的暖光

	// ---------------- 对角光泽（左下 → 右上） ----------------
	float d = (q.x + q.y) / ((aspect + 1.0) * 0.5);   // 左下角 = -1，右上角 = +1
	float travel = clamp((fract(TIME / gloss_cycle) - gloss_pause) / max(1.0 - gloss_pause, 0.001), 0.0, 1.0);
	float center = mix(-1.45, 1.45, smoothstep(0.0, 1.0, travel));
	float dd = d - center;
	float w = max(gloss_width, 0.02);
	float core = exp(-(dd * dd) / (2.0 * w * w * 0.28));
	float halo = exp(-(dd * dd) / (2.0 * (w * 2.2) * (w * 2.2) * 0.28));

	vec3 rgb = col.rgb * base_color.rgb;
	float lum = mix(1.0 - gloss_shade, 1.0, halo);              // 光带外压暗、带内还原
	rgb = mix(rgb * lum, gloss_color.rgb * lum, clamp(core * gloss_strength, 0.0, 1.0));

	// 消融边界：白字上加不亮，改成染暖色（+ 少量提亮），橙边在蓝底上很明显
	float glow = clamp(rim * burn_strength, 0.0, 1.0);
	rgb = mix(rgb, burn_color.rgb, glow * 0.9);
	rgb += burn_color.rgb * rim * 0.2;

	COLOR = vec4(rgb, col.a * keep);
}
