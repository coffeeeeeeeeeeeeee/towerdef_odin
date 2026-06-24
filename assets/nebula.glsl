#version 330

// Original: https://x.com/XorDev/status/1975230424982183956

in vec2 fragTexCoord;
in vec4 fragColor;
out vec4 finalColor;

uniform float u_time;
uniform vec2  u_resolution;

void main() {
    vec2  r = u_resolution;
    float t = u_time;
    vec4  o = vec4(0.0);

    float i = 0.0, z = 0.0, d = 0.0, h = 0.0;

    for (; i++ < 50.0; o += vec4(3.0, z, i, 1.0) / d) {
        // Ray direction: centered screen coords + depth bias from gl_FragCoord.z
        vec3 p = z * normalize(gl_FragCoord.rgb * 2.0 - r.xyy);
        vec3 a = vec3(0.0, 1.0, 0.0);  // vec3 a; a.y++
        p.z += 7.0;

        // Trigonometric SDF distortion
        h = length(p) - t;
        a = mix(dot(a, p) * a, p, sin(h)) + cos(h) * cross(a, p);

        // Inner FBM-like loop — 9 sin/round iterations accumulating into a
        for (d = 0.0; d++ < 9.0; a += sin(round(a * d) - t).zxy / d);

        // March ray by SDF-approximated step
        z += d = 0.1 * length(a.xz);
    }

    // Tonemap: tanh compresses large accumulated values into [0,1]
    o = tanh(o / 10000.0);

    finalColor = o;
}
