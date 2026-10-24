shader_type canvas_item;

// Захватываем то, что находится на экране под этим ColorRect
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

const int MAX_COLORS = 64;
uniform vec3 palette[MAX_COLORS];
uniform int palette_size = 16;

uniform int dither_mode = 2; 
uniform bool auto_strength = true;
uniform float dither_strength = 0.4;
uniform float pattern_scale = 1.0;

// НОВОЕ: Сила экранного шума (ставим по умолчанию 0.03)
uniform float noise_amount : hint_range(0.0, 0.5) = 0.03;

// Матрицы Байера
const float BAYER2[4] = float[4](0.0, 2.0, 3.0, 1.0);
const float BAYER4[16] = float[16](
    0.0,  8.0,  2.0, 10.0,
    12.0, 4.0, 14.0,  6.0,
    3.0, 11.0,  1.0,  9.0,
    15.0, 7.0, 13.0,  5.0
);
const float BAYER8[64] = float[64](
    0.0, 32.0,  8.0, 40.0,  2.0, 34.0, 10.0, 42.0,
    48.0, 16.0, 56.0, 24.0, 50.0, 18.0, 58.0, 26.0,
    12.0, 44.0,  4.0, 36.0, 14.0, 46.0,  6.0, 38.0,
    60.0, 28.0, 52.0, 20.0, 62.0, 30.0, 54.0, 22.0,
    3.0, 35.0, 11.0, 43.0,  1.0, 33.0,  9.0, 41.0,
    51.0, 19.0, 59.0, 27.0, 49.0, 17.0, 57.0, 25.0,
    15.0, 47.0,  7.0, 39.0, 13.0, 45.0,  5.0, 37.0,
    63.0, 31.0, 55.0, 23.0, 61.0, 29.0, 53.0, 21.0
);

float bayer_offset(ivec2 p, int mode) {
    if (mode == 1) return (BAYER2[(p.y & 1) * 2 + (p.x & 1)] + 0.5) / 4.0 - 0.5;
    else if (mode == 2) return (BAYER4[(p.y & 3) * 4 + (p.x & 3)] + 0.5) / 16.0 - 0.5;
    else if (mode == 3) return (BAYER8[(p.y & 7) * 8 + (p.x & 7)] + 0.5) / 64.0 - 0.5;
    return 0.0;
}

float ign(vec2 p) {
    return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

// НОВОЕ: Функция генерации случайного шума для каждого пикселя
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

vec3 quantize(vec3 c) {
    if (palette_size <= 0) return c;
    vec3 best = palette[0];
    float best_d = distance(c, best);
    for (int i = 1; i < MAX_COLORS; i++) {
        if (i >= palette_size) break;
        float d = distance(c, palette[i]);
        if (d < best_d) { best_d = d; best = palette[i]; }
    }
    return best;
}

void fragment() {
    // Берем цвет с экрана
    vec4 src = texture(screen_texture, SCREEN_UV);
    vec3 col = src.rgb;
    
    // Координаты пикселя для узора
    vec2 ip = floor(FRAGCOORD.xy / pattern_scale);

    float d = 0.0;
    if (dither_mode >= 1 && dither_mode <= 3) d = bayer_offset(ivec2(ip), dither_mode);
    else if (dither_mode == 4) d = ign(ip) - 0.5;

    float strength = auto_strength ? (1.0 / pow(max(float(palette_size), 1.0), 1.0 / 3.0)) : dither_strength;

    col += d * strength;

    // НОВОЕ: Добавляем случайный шум к цвету, чтобы разбить идеальные градиенты
    float n = hash(ip) - 0.5; 
    col += n * noise_amount;

    col = clamp(col, 0.0, 1.0);
    col = quantize(col);

    COLOR = vec4(col, src.a);
}