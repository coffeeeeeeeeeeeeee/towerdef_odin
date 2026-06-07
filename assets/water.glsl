#version 330

in vec2 fragTexCoord;
in vec4 fragColor;
out vec4 finalColor;

uniform sampler2D texture0;
uniform vec2 texelSize;   // (1/screenW, 1/screenH)
uniform vec4 waterColor;  // base water color
uniform vec4 edgeColor;   // darker edge/shadow color

void main() {
    // Separable box blur — horizontal samples stored in sum
    // We do a full 2D box in one pass (radius 5 = 11x11 = 121 samples)
    // Affordable at typical resolutions for a small game
    float sum = 0.0;
    int R = 5;
    float total = float((2*R+1) * (2*R+1));

    for (int x = -R; x <= R; x++) {
        for (int y = -R; y <= R; y++) {
            vec2 offset = vec2(float(x), float(y)) * texelSize;
            sum += texture(texture0, fragTexCoord + offset).r;
        }
    }
    sum /= total;

    // Threshold: sharp enough to look clean, soft enough to anti-alias
    float alpha = smoothstep(0.38, 0.62, sum);

    // Inner glow: pixels near the threshold edge get the edge color
    float edge = smoothstep(0.38, 0.62, sum) - smoothstep(0.50, 0.62, sum);
    vec4 color = mix(waterColor, edgeColor, edge * 0.5);

    finalColor = color * alpha;
}
