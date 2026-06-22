#version 330

// Grass overlay shader — Plain & Forest biomes.
// Draws a procedural grass texture (noise-based color variation) with a
// subtle wind effect (slow oscillation anchored to map position).
//
// Coordinates are derived from gl_FragCoord, anchored to the map grid so
// the pattern doesn't slide when the camera pans or zooms.
// The DrawRectangle call on the CPU side clips the shader to the map area.

in vec2 fragTexCoord;
in vec4 fragColor;
out vec4 finalColor;

uniform vec2  u_resolution;    // screen size in pixels
uniform vec2  u_camera_offset; // map top-left in screen pixels (Raylib Y-down)
uniform float u_zoom;          // current zoom factor
uniform float u_time;          // GetTime() for wind animation
uniform float u_alpha;         // per-biome max overlay alpha  [0..1]
uniform float u_density;       // per-biome noise scale (1.0 = ~1 patch per tile)
uniform vec4  u_grass_color;   // per-biome tint color (RGB used; A ignored)

// ── Noise helpers (value noise + FBM) ────────────────────────────────────────

float hash21(vec2 p) {
    p  = fract(p * vec2(234.34, 435.345));
    p += dot(p, p + 34.23);
    return fract(p.x * p.y);
}

float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);          // smoothstep interpolation
    return mix(
        mix(hash21(i),               hash21(i + vec2(1, 0)), f.x),
        mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), f.x),
        f.y
    );
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * vnoise(p);
        p   = p * 2.1 + vec2(1.7, 9.2);
        a  *= 0.5;
    }
    return v;
}

// ─────────────────────────────────────────────────────────────────────────────

void main() {
    // Convert from OpenGL screen coords (Y=0 at bottom) to Raylib screen coords
    // (Y=0 at top), then subtract the camera offset to get map-local pixels.
    // Dividing by zoom gives reference-pixel coordinates independent of zoom level.
    vec2 screenPos = vec2(gl_FragCoord.x, u_resolution.y - gl_FragCoord.y);
    vec2 mapPos    = (screenPos - u_camera_offset) / u_zoom;

    // Noise UV: 1 noise unit ≈ 1 tile at density 1.0.
    // CELL_SIZE reference = 32px → multiply by (1/32) * u_density.
    vec2 noiseUV = mapPos * 0.03125 * u_density;  // 0.03125 = 1/32

    // Base grass texture: two FBM layers mixed for micro + macro variation.
    float base   = fbm(noiseUV);
    float detail = vnoise(noiseUV * 2.5 + vec2(5.3, 1.7));
    float n      = mix(base, detail, 0.30);

    // Wind: slow horizontal wave sweeping across the map.
    // Phase offset varies by map position → natural look, not a uniform pulse.
    float wind = sin(u_time * 0.7 + noiseUV.x * 3.5 + noiseUV.y * 1.2) * 0.05;
    n = clamp(n + wind, 0.0, 1.0);

    // Map noise to alpha: tighter band → more coverage, more visible.
    float grass = smoothstep(0.25, 0.65, n);
    float alpha = grass * u_alpha;

    finalColor = vec4(u_grass_color.rgb, alpha) * fragColor;
}
