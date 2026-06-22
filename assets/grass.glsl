#version 330

// Grass shader — raymarched grass field adapted from the provided Shadertoy.
//
// Original: first-person raymarcher with PCG hash + SDF blade walls.
// Adaptation:
//   - Camera anchored to mapPos (grass fixed to tile grid, not scrolling).
//   - iTime camera movement replaced with per-blade wind sway.
//   - Iterations capped at 128 (rays reach ground in ~5 steps; 128 is generous).
//   - Shadertoy variables mapped: FC→gl_FragCoord, r→u_resolution, t→u_time.

in vec2 fragTexCoord;
in vec4 fragColor;
out vec4 finalColor;

uniform vec2  u_resolution;
uniform vec2  u_camera_offset;
uniform float u_zoom;
uniform float u_time;
uniform float u_alpha;
uniform float u_density;
uniform vec4  u_grass_color;

// ── PCG hash (from original shader) ─────────────────────────────────────────

uint pcg_hash(uint x) {
    x = x * 747796405u + 2891336453u;
    x = ((x >> ((x >> 28u) + 4u)) ^ x) * 277803737u;
    x = (x >> 22u) ^ x;
    return x;
}

float hash21(vec2 p) {
    uvec2 q = uvec2(ivec2(floor(p)));
    uint  n = q.x * 1664525u + q.y * 1013904223u;
    return float(pcg_hash(n)) * (1.0 / 4294967295.0);
}

float hash31(vec3 p) {
    uvec3 q = uvec3(ivec3(floor(p)));
    uint  n = q.x * 1664525u + q.y * 1013904223u + q.z * 69069u;
    return float(pcg_hash(n)) * (1.0 / 4294967295.0);
}

float valueNoise(vec2 p) {
    vec2 point = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(point);
    float b = hash21(point + vec2(1.0, 0.0));
    float c = hash21(point + vec2(0.0, 1.0));
    float d = hash21(point + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// ── SDF map (original logic, wind added) ────────────────────────────────────
// Ground plane at y = -1.  Grass blades: thin walls at every integer x,z
// (after the ×100 scaling in the call site).  Each blade gets a random
// height from hash21(p.xz).  Wind displaces p.x by a sine wave per blade.

float map(vec3 p) {
    if (p.y > -0.99) {
        return p.y + 1.0;
    }
    return min(
        p.y + 1.0 + hash21(p.xz) * 0.06,
        min(
            min(fract(p.x) / 50.0 + 0.01,  0.01 - fract(p.x) / 50.0 + 0.01),
            min(fract(p.z) / 50.0 + 0.01,  0.01 - fract(p.z) / 50.0 + 0.01)
        )
    );
}

// ─────────────────────────────────────────────────────────────────────────────

void main() {
    // Screen → Raylib coords → map-anchored reference pixels
    vec2 screenPos = vec2(gl_FragCoord.x, u_resolution.y - gl_FragCoord.y);
    vec2 mapPos    = (screenPos - u_camera_offset) / u_zoom;

    // Scale map position to grass world: u_density controls blade frequency.
    // density=1 → 1 grass-world-unit = 128 px; density=2 → 64 px.
    vec2 gPos = mapPos * (u_density / 128.0);

    // Camera anchored to the map tile — no scrolling.
    // Looking forward (+z) and slightly down, replicating the original's feel.
    vec3 ro = vec3(gPos.x, 0.25, gPos.y);
    vec3 rd = normalize(vec3(0.0, -0.4, 1.0));

    float t = 0.0;
    vec4  col = vec4(0.0);
    bool  hit = false;

    for (int i = 0; i < 128; i++) {
        vec3 p = ro + rd * t;

        // Wind sway: each blade column gets an independent phase.
        // Displacement grows linearly from 0 at ground (y=-1) to max at tip.
        float bladeX = floor(p.x * 100.0);
        float bladeZ = floor(p.z * 100.0);
        float windPhase = hash21(vec2(bladeX, bladeZ));
        float wind = sin(u_time * 1.5 + windPhase * 6.2832) * 0.07
                     * max(0.0, p.y + 1.0);   // zero at root, full at tip
        vec3 pw = vec3(p.x + wind, p.y, p.z);

        // Original call site: scale xz by 100, displace y by valueNoise
        float d = map(vec3(
            pw.x * 50.0,
            pw.y - valueNoise(pw.xz / 7.0) * 0.5,
            pw.z * 50.0
        ));

        t += d;

        if (d < 0.01) {
            // Shade: height-based light (original: 1.5 + p.y)
            float lightY = clamp(1.5 + p.y, 0.0, 1.5);
            float rnd    = hash21(vec2(bladeX, bladeZ) * 40.0);

            vec3 baseCol  = u_grass_color.rgb * 0.35;
            vec3 tipCol   = u_grass_color.rgb * 1.60 + vec3(0.06, 0.10, 0.0);
            vec3 bladeCol = mix(baseCol, tipCol, lightY * rnd * 0.1 + lightY * 0.4);

            col = vec4(bladeCol, u_alpha);
            hit = true;
            break;
        }

        if (t > 10.0) break;
    }

    if (!hit) { finalColor = vec4(0.0); return; }

    finalColor = col * fragColor;
}
