#version 330

in vec2 fragTexCoord;
in vec4 fragColor;
out vec4 finalColor;

uniform vec2  u_resolution;
uniform float u_time;
uniform float u_opacity;        // pre-computed from zoom on CPU side
uniform vec2  u_camera_offset;  // app.camera_offset en pixeles — para parallax

// ── Noise helpers ─────────────────────────────────────────────────────────────
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash(i),                  hash(i + vec2(1.0, 0.0)), f.x),
        mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x),
        f.y
    );
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 5; i++) {
        v += a * vnoise(p);
        p  = p * 2.1 + vec2(1.7, 9.2);
        a *= 0.5;
    }
    return v;
}

void main() {
    if (u_opacity <= 0.001) {
        finalColor = vec4(0.0);
        return;
    }

    // Use gl_FragCoord for true screen-space UVs (fragTexCoord is unreliable
    // when drawing a rectangle with Raylib's internal 1x1 white texture)
    vec2 uv = gl_FragCoord.xy / u_resolution;
    uv.y    = 1.0 - uv.y;                         // flip Y to match screen space
    uv.x   *= u_resolution.x / u_resolution.y;    // aspect-correct
    vec2 p  = uv * 2.8;

    // Parallax: las nubes "siguen" al camera offset pero al 35% — sensación de
    // capa lejana detrás del mapa. Cuando hacés zoom o resize y el grid se
    // recentra, las nubes se desplazan menos que el mapa.
    // 2.8 mantiene la consistencia con el factor de escala de p.
    const float PARALLAX_FACTOR = 0.35;
    vec2 parallax = (u_camera_offset / u_resolution) * 2.8 * PARALLAX_FACTOR;
    p += parallax;

    // Slow horizontal + slight vertical drift
    p += vec2(u_time * 0.025, u_time * 0.008);

    float f = fbm(p);

    // Threshold — puffs appear above 0.50, fully solid above 0.65
    float cloud = smoothstep(0.50, 0.65, f);

    // Soft vignette so clouds fade near screen edges
    vec2  centered = (gl_FragCoord.xy / u_resolution) * 2.0 - 1.0;
    float vignette = 1.0 - smoothstep(0.55, 1.0, length(centered));

    // Multiplicador global de opacidad — antes 0.55, ahora 0.85 para nubes más densas.
    float alpha = cloud * u_opacity * 0.85 * vignette;
    finalColor  = vec4(1.0, 1.0, 1.0, alpha);
}
