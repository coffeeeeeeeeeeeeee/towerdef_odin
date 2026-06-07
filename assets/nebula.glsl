#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

out vec4 finalColor;

uniform float u_time;
uniform vec2  u_resolution;

// ── Noise primitives ─────────────────────────────────────────────────────────

float hash(vec2 p) {
    p = fract(p * vec2(127.1, 311.7));
    p += dot(p, p + 19.19);
    return fract(p.x * p.y);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash(i),             hash(i + vec2(1,0)), u.x),
        mix(hash(i + vec2(0,1)), hash(i + vec2(1,1)), u.x),
        u.y
    );
}

// 5-octave FBM with rotation between octaves
float fbm(vec2 p) {
    float v = 0.0, amp = 0.5;
    mat2 rot = mat2(0.8, -0.6, 0.6, 0.8);
    for (int i = 0; i < 5; i++) {
        v   += amp * noise(p);
        amp *= 0.5;
        p    = rot * p * 2.1;
    }
    return v;
}

// ── Animated palette ──────────────────────────────────────────────────────────
// Four named colors that cycle over time, blended per-pixel by density.
// phase_* are slow independent sine waves so each color drifts at its own rate.

vec3 nebula_color(float density, float time) {
    density = clamp(density, 0.0, 1.0);

    // Base colors
    vec3 void_black    = vec3(0.01, 0.01, 0.04);
    vec3 midnight_blue = vec3(0.04, 0.06, 0.30);
    vec3 ocean_blue    = vec3(0.00, 0.40, 0.75);
    vec3 sky_cyan      = vec3(0.00, 0.75, 0.90);
    vec3 violet        = vec3(0.35, 0.05, 0.70);
    vec3 magenta       = vec3(0.80, 0.05, 0.55);
    vec3 icy_white     = vec3(0.75, 0.92, 1.00);

    // Subtle tint oscillation — dominant color stays, accent drifts in gently.
    // Amplitude capped at 0.25 so the base hue always wins.
    float s1 = sin(time * 0.11)        * 0.20 + 0.10; // dark zone:   blue dominant, violet tints in
    float s2 = sin(time * 0.07 + 1.3)  * 0.22 + 0.08; // mid zone:    ocean dominant, magenta tints in
    float s3 = sin(time * 0.13 + 2.7)  * 0.18 + 0.06; // upper zone:  cyan dominant, violet tints in
    float s4 = sin(time * 0.09 + 0.5)  * 0.15 + 0.05; // bright zone: icy white dominant, cyan tints in

    vec3 dark   = mix(midnight_blue, violet,   s1);
    vec3 mid_lo = mix(ocean_blue,    magenta,  s2);
    vec3 mid_hi = mix(sky_cyan,      violet,   s3);
    vec3 bright = mix(icy_white,     sky_cyan, s4);

    // Build ramp: void → dark → mid_lo → mid_hi → bright
    vec3 col;
    if (density < 0.20) col = mix(void_black, dark,   density / 0.20);
    else if (density < 0.45) col = mix(dark,   mid_lo, (density - 0.20) / 0.25);
    else if (density < 0.72) col = mix(mid_lo, mid_hi, (density - 0.45) / 0.27);
    else                     col = mix(mid_hi, bright, (density - 0.72) / 0.28);

    return col;
}

// ── Main ─────────────────────────────────────────────────────────────────────
void main() {
    vec2 uv = gl_FragCoord.xy / u_resolution;
    uv.y = 1.0 - uv.y;

    float aspect = u_resolution.x / u_resolution.y;
    vec2  p = (uv - 0.5) * vec2(aspect, 1.0);

    float t = u_time * 0.08;

    // Layer 1 — large galactic arm, slow clockwise spin
    float a1 = t * 0.55;
    mat2  r1 = mat2(cos(a1), -sin(a1), sin(a1), cos(a1));
    vec2  p1 = r1 * p * 1.8;
    vec2  w1 = vec2(fbm(p1), fbm(p1 + vec2(5.2, 1.3)));
    float n1 = fbm(p1 + 2.2 * w1);

    // Layer 2 — filaments, counter-spin
    float a2 = -t * 0.38 + 1.0;
    mat2  r2 = mat2(cos(a2), -sin(a2), sin(a2), cos(a2));
    vec2  p2 = r2 * p * 3.4 + vec2(0.5, 0.3);
    vec2  w2 = vec2(fbm(p2 + vec2(1.7, 9.2)), fbm(p2 + vec2(8.3, 2.8)));
    float n2 = fbm(p2 + 1.6 * w2);

    // Layer 3 — fine texture / star clusters
    float a3 = t * 0.25 + 2.5;
    mat2  r3 = mat2(cos(a3), -sin(a3), sin(a3), cos(a3));
    vec2  p3 = r3 * p * 6.2 + vec2(-0.3, 0.8);
    float n3 = fbm(p3);

    float density = n1 * 0.55 + n2 * 0.30 + n3 * 0.15;

    // Vignette
    float vig = 1.0 - smoothstep(0.30, 0.90, length(p * 0.85));
    density  *= vig;

    density = pow(clamp(density, 0.0, 1.0), 1.7);

    // Pass raw time so the palette can animate independently of density
    vec3 col = nebula_color(density, u_time);

    // Star sparkle
    float sparkle = pow(max(0.0, noise(p * 130.0 + t * 0.4) - 0.93), 3.0) * 5.0;
    col += sparkle * vec3(0.65, 0.88, 1.00);

    finalColor = vec4(col, 1.0);
}
