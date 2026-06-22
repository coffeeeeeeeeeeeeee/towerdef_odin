#version 330

in vec2 fragTexCoord;
in vec4 fragColor;
out vec4 finalColor;

uniform sampler2D texture0;
uniform vec2  texelSize;        // (1/screenW, 1/screenH)
uniform vec4  waterColor;       // base water tint
uniform vec4  edgeColor;        // border/shadow color
uniform float u_time;
uniform vec2  u_camera_offset;  // map origin in screen px (Raylib coords, y-down)
uniform float u_zoom;

// ── Simplex noise (original, verbatim) ───────────────────────────────────────

vec4 mod289(vec4 x) {
    return x - floor(x / 289.0) * 289.0;
}
vec4 permute(vec4 x) {
    return mod289((x * 34.0 + 1.0) * x);
}
vec4 snoise(vec3 v) {
    const vec2 C = vec2(1.0 / 6.0, 1.0 / 3.0);
    vec3 i  = floor(v + dot(v, vec3(C.y)));
    vec3 x0 = v - i + dot(i, vec3(C.x));
    vec3 g  = step(x0.yzx, x0.xyz);
    vec3 l  = 1.0 - g;
    vec3 i1 = min(g.xyz, l.zxy);
    vec3 i2 = max(g.xyz, l.zxy);
    vec3 x1 = x0 - i1 + C.x;
    vec3 x2 = x0 - i2 + C.y;
    vec3 x3 = x0 - 0.5;
    vec4 p =
      permute(permute(permute(i.z + vec4(0.0, i1.z, i2.z, 1.0))
                            + i.y + vec4(0.0, i1.y, i2.y, 1.0))
                            + i.x + vec4(0.0, i1.x, i2.x, 1.0));
    vec4 j  = p - 49.0 * floor(p / 49.0);
    vec4 x_ = floor(j / 7.0);
    vec4 y_ = floor(j - 7.0 * x_);
    vec4 x  = (x_ * 2.0 + 0.5) / 7.0 - 1.0;
    vec4 y  = (y_ * 2.0 + 0.5) / 7.0 - 1.0;
    vec4 h  = 1.0 - abs(x) - abs(y);
    vec4 b0 = vec4(x.xy, y.xy);
    vec4 b1 = vec4(x.zw, y.zw);
    vec4 s0 = floor(b0) * 2.0 + 1.0;
    vec4 s1 = floor(b1) * 2.0 + 1.0;
    vec4 sh = -step(h, vec4(0.0));
    vec4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
    vec4 a1 = b1.xzyw + s1.xzyw * sh.zzww;
    vec3 g0 = vec3(a0.xy, h.x);
    vec3 g1 = vec3(a0.zw, h.y);
    vec3 g2 = vec3(a1.xy, h.z);
    vec3 g3 = vec3(a1.zw, h.w);
    vec4 m  = max(0.6 - vec4(dot(x0,x0), dot(x1,x1), dot(x2,x2), dot(x3,x3)), 0.0);
    vec4 m2 = m * m;
    vec4 m3 = m2 * m;
    vec4 m4 = m2 * m2;
    vec3 grad =
      -6.0 * m3.x * x0 * dot(x0, g0) + m4.x * g0 +
      -6.0 * m3.y * x1 * dot(x1, g1) + m4.y * g1 +
      -6.0 * m3.z * x2 * dot(x2, g2) + m4.z * g2 +
      -6.0 * m3.w * x3 * dot(x3, g3) + m4.w * g3;
    vec4 px = vec4(dot(x0,g0), dot(x1,g1), dot(x2,g2), dot(x3,g3));
    return 42.0 * vec4(grad, dot(m4, px));
}

float water_caustics(vec3 pos) {
    vec4 n = snoise(pos);
    pos -= 0.07 * n.xyz;
    pos *= 1.62;
    n = snoise(pos);
    pos -= 0.07 * n.xyz;
    n = snoise(pos);
    pos -= 0.07 * n.xyz;
    n = snoise(pos);
    return n.w;
}

// ─────────────────────────────────────────────────────────────────────────────

void main() {
    // ── Phase 1: box blur + threshold → rounded blob mask ────────────────────
    float sum   = 0.0;
    int   R     = 5;
    float total = float((2*R+1) * (2*R+1));
    for (int x = -R; x <= R; x++) {
        for (int y = -R; y <= R; y++) {
            sum += texture(texture0, fragTexCoord + vec2(float(x), float(y)) * texelSize).r;
        }
    }
    sum /= total;

    float alpha = smoothstep(0.38, 0.62, sum);
    if (alpha < 0.001) { finalColor = vec4(0.0); return; }

    float edge = smoothstep(0.38, 0.62, sum) - smoothstep(0.50, 0.62, sum);

    // ── Phase 2: world-anchored caustics ─────────────────────────────────────
    // Convert gl_FragCoord (y=0 at bottom, OpenGL) → world px (anchored to map).
    // Equivalent to the original (-iResolution + 2*fragCoord)/iResolution.y
    // but using world coordinates so the pattern moves with pan and zoom.
    float screenH   = 1.0 / texelSize.y;
    vec2  screenPos = vec2(gl_FragCoord.x, screenH - gl_FragCoord.y);  // flip y
    vec2  worldPos  = (screenPos - u_camera_offset) / u_zoom;
    // Normalizar por tamaño de tile (32 px = 1 metro) → p en unidades de tile.
    // Las cáusticas tienen la misma escala física independientemente de resolución o zoom.
    vec2  p         = worldPos / 32.0;

    // Para vista top-down usamos worldPos directamente como coordenada del noise.
    // Evita la singularidad de perspectiva del original (diseñado para p centrado en 0).
    vec3 pos = vec3(p.x, u_time * 0.75, p.y);
    pos *= 3.0;

    float w         = mix(water_caustics(pos), water_caustics(pos + 1.0), 0.5);
    float intensity = exp(w * 4.0 - 1.0);

    // ── Tint caustics with waterColor, darken edges ───────────────────────────
    vec4 causticColor = vec4(vec3(intensity), 1.0) * waterColor;
    vec4 color        = mix(causticColor, edgeColor, edge * 0.5);
    finalColor        = color * alpha;
}
