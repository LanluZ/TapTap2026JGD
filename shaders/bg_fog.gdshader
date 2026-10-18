shader_type canvas_item;
render_mode blend_mix;

// ============================================================
//  背景云雾 Shader — 深色底 · 整屏视差云海
//  场景：res://scenes/main.tscn（WorldBG 之上的底层云雾层）
//  源自 2026-you-si-bi-she 项目 cloud_sea.gdshader 的改造版:
//   ① smootherstep / bilinear / fBm(6八度) / 域扭曲 / 三层视差
//   ② 配色反转: 深底上云雾比底色亮 (mist), 密处微降加深立体感
//   ③ height_bias 纵向密度衰减 (顶稀底密)
//   ④ 输出 alpha 压低, 只作底层氛围不抢内容
// ============================================================

// ======== 像素化 ========
uniform float pixel_size : hint_range(0.0, 8.0, 0.5) = 1.5;

// ======== 云层基础 ========
uniform float cloud_scale : hint_range(0.5, 4.0) = 1.6;
uniform float cloud_speed : hint_range(0.0, 1.0) = 0.05;
uniform float cloud_density : hint_range(0.0, 2.0) = 1.0;
uniform vec2 wind_dir = vec2(0.6, 0.05);

// ======== 三层视差深度 ========
uniform float far_depth : hint_range(0.01, 0.5) = 0.08;
uniform float mid_depth : hint_range(0.1, 1.0) = 0.35;
uniform float near_depth : hint_range(0.3, 2.0) = 0.8;

// ======== 水墨风格化 ========
uniform float contrast : hint_range(1.0, 4.0) = 1.6;
uniform float posterize_steps : hint_range(2.0, 8.0) = 3.0;
uniform float ink_edge : hint_range(0.0, 1.0) = 0.25;

// ======== 云团 / 烟雾 ========
uniform float circle_amount : hint_range(0.0, 1.0) = 0.3;
uniform float puff_amount : hint_range(0.0, 1.0) = 0.35;

// ======== 雾专属 ========
uniform vec3 mist_color : source_color = vec3(0.40, 0.45, 0.50);  // 雾色 (比深底亮)
uniform float ink_darkness : hint_range(0.0, 1.0) = 0.45;         // 密处变暗量 (立体感)
uniform float height_bias : hint_range(-1.0, 1.0) = 0.35;         // >0 顶稀底密
uniform float min_alpha : hint_range(0.0, 1.0) = 0.03;            // 雾淡处保底透明度
uniform float opacity : hint_range(0.0, 1.0) = 0.6;

uniform float time_scale : hint_range(0.0, 2.0) = 1.0;

// ============================================================
//  基础数学模块
// ============================================================
float smootherstep(float t) {
    t = clamp(t, 0.0, 1.0);
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

float bilinear_interp(vec2 f, float a, float b, float c, float d) {
    float u = smootherstep(f.x);
    float v = smootherstep(f.y);
    return mix(mix(a, b, u), mix(c, d, u), v);
}

float hash(vec2 p) {
    p = fract(p * vec2(443.8975, 397.2973));
    p += dot(p, p + 19.19);
    return fract(p.x * p.y);
}

float value_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return bilinear_interp(f, a, b, c, d);
}

float fbm(vec2 p) {
    float val = 0.0;
    float amp = 0.5;
    float freq = 1.0;
    for (int i = 0; i < 6; i++) {
        val += amp * value_noise(p * freq);
        freq *= 2.0;
        amp *= 0.5;
    }
    return val;
}

// 域扭曲 fBm — 流体质感, 扭曲系数调低让流动更柔
float fbm_warped(vec2 p, float t) {
    vec2 q = vec2(
        fbm(p + vec2(0.0, 0.0) + t * 0.02),
        fbm(p + vec2(5.2, 1.3) + t * 0.015)
    );
    vec2 r = vec2(
        fbm(p + 3.0 * q + vec2(1.7, 9.2) + t * 0.01),
        fbm(p + 3.0 * q + vec2(8.3, 2.8) + t * 0.012)
    );
    return fbm(p + 2.2 * r);
}

vec2 parallax_offset(vec2 uv, float depth, float t) {
    float speed = depth * 0.5 + 0.15;
    return uv + wind_dir * t * cloud_speed * speed;
}

float circle_sdf(vec2 uv, vec2 center, float radius) {
    float d = length(uv - center);
    return 1.0 - smootherstep(clamp(d / radius, 0.0, 1.0));
}

float parabola_cloud(vec2 uv, vec2 center, float width, float height, float thick) {
    vec2 p = uv - center;
    float xn = p.x / width;
    float mask = 1.0 - smootherstep(clamp(abs(xn), 0.0, 1.0));
    float arch = height * (1.0 - xn * xn);
    float d = abs(p.y - arch);
    float shape = 1.0 - smoothstep(0.0, thick, d);
    return shape * mask;
}

float smoke_envelope(vec2 uv, float t) {
    float accum = 0.0;
    for (int i = 0; i < 6; i++) {
        float fi = float(i);
        vec2 seed = vec2(fi * 7.13, fi * 13.37);
        vec2 center = vec2(
            hash(seed + vec2(10.0, 20.0)) * 1.4 - 0.2,
            hash(seed + vec2(30.0, 40.0)) * 0.5 + 0.1 + fi * 0.1
        );
        center.x += sin(t * 0.15 + fi * 2.1) * 0.12;
        center.y += cos(t * 0.12 + fi * 1.7) * 0.06;
        float size = 0.06 + 0.03 * sin(t * 0.8 + fi * 1.3);
        float d = length(uv - center);
        float k = 10.0;
        float x = d / size;
        float envelope = x * exp(-x * k) * k / exp(1.0);
        float vis = hash(seed + vec2(50.0, 60.0)) * 0.5 + 0.5;
        accum += envelope * vis;
    }
    return accum * puff_amount;
}

float cloud_layer(vec2 uv, float depth, float t, float scale_mult) {
    vec2 offset_uv = parallax_offset(uv, depth, t);
    vec2 p = offset_uv * cloud_scale * scale_mult;
    float density = fbm_warped(p + depth * 20.0, t);
    // 纵向分布交给 height_bias 统一控制
    density = pow(density, 1.5);
    return density;
}

// ============================================================
//  片元着色器
// ============================================================
void fragment() {
    float t = TIME * time_scale;
    vec2 uv = UV;

    if (pixel_size > 0.0) {
        float px = pixel_size / 256.0;
        uv = floor(uv / px) * px;
    }

    // ======== 三层视差云海 ========
    float far_c  = cloud_layer(uv, far_depth,  t * 0.3, 0.6);
    float mid_c  = cloud_layer(uv, mid_depth,  t * 0.8, 1.2);
    float near_c = cloud_layer(uv, near_depth, t * 1.5, 2.0);

    // ======== 云脊 / 云团 / 烟雾 ========
    float arches = 0.0;
    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        vec2 seed = vec2(fi * 5.73, fi * 9.91);
        vec2 center = vec2(
            hash(seed + vec2(100.0, 110.0)) * 0.7 + 0.15,
            hash(seed + vec2(120.0, 130.0)) * 0.25 + 0.1
        );
        float w = hash(seed + vec2(140.0, 150.0)) * 0.2 + 0.1;
        float h = hash(seed + vec2(160.0, 170.0)) * 0.15 + 0.05;
        float th = hash(seed + vec2(180.0, 190.0)) * 0.04 + 0.02;
        arches += parabola_cloud(uv, center, w, h, th);
    }
    arches *= 0.3;

    float circles = 0.0;
    for (int i = 0; i < 8; i++) {
        float fi = float(i);
        vec2 seed = vec2(fi * 3.17, fi * 7.53);
        vec2 center = vec2(
            hash(seed + vec2(200.0, 210.0)) * 0.85 + 0.07,
            hash(seed + vec2(220.0, 230.0)) * 0.4 + 0.05
        );
        float r = hash(seed + vec2(240.0, 250.0)) * 0.06 + 0.02;
        center += vec2(
            sin(t * 0.15 + fi * 1.1) * 0.03,
            cos(t * 0.1 + fi * 1.5) * 0.015
        );
        circles = max(circles, circle_sdf(uv, center, r));
    }
    circles *= circle_amount;

    float smoke = smoke_envelope(uv, t);

    // ======== 合成总密度 ========
    float density = 0.0;
    density += far_c  * 0.15;
    density += mid_c  * 0.35;
    density += near_c * 0.50;
    density += arches * 0.3;
    density += circles * 0.5;
    density = clamp(density, 0.0, 1.0);
    density = pow(density, 1.0 / max(cloud_density, 0.001));
    density = clamp(density + smoke * 0.15, 0.0, 1.0);

    // ======== 纵向密度衰减: 顶稀底密 (uv.y=0 顶, uv.y=1 底) ========
    float hmask = mix(1.0 - height_bias, 1.0 + height_bias, uv.y);
    density *= clamp(hmask, 0.0, 2.0);

    // ======== 水墨风格化 ========
    float layers = floor(density * posterize_steps) / posterize_steps;
    float final_val = pow(layers, 1.0 / contrast);
    final_val = clamp(final_val, 0.0, 1.0);

    if (ink_edge > 0.0) {
        vec2 st = vec2(0.003, 0.0);
        float dx = cloud_layer(uv + st, mid_depth, t, 1.2) - cloud_layer(uv - st, mid_depth, t, 1.2);
        float dy = cloud_layer(uv + st.yx, mid_depth, t, 1.2) - cloud_layer(uv - st.yx, mid_depth, t, 1.2);
        float edge = length(vec2(dx, dy));
        edge = smootherstep(clamp(edge * 4.0, 0.0, 1.0));
        final_val = clamp(final_val + edge * ink_edge * 0.3, 0.0, 1.0);
    }

    // ======== 深底雾输出: 雾比底亮, 密处微降加深立体感 ========
    vec3 mist = mix(mist_color, mist_color * (1.0 - ink_darkness), final_val);

    // alpha: 雾淡处保底 min_alpha, 最浓处也不遮死底色
    float alpha = opacity * mix(min_alpha, 0.8, final_val);
    COLOR = vec4(mist, alpha);
}
