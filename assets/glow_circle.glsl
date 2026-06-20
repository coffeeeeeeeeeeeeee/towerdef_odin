#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

uniform sampler2D texture0;
uniform vec4 colDiffuse;

out vec4 finalColor;

void main() {
    // Map UV to centered -1..+1 space
    vec2 uv = fragTexCoord * 2.0 - 1.0;
    float d  = length(uv);

    // Ring centered at d=0.45 (matches the quad sizing: quad_half = radius*2.2)
    float ring_d    = 0.45;
    float ring      = exp(-pow(d - ring_d, 2.0) * 180.0);

    // Very subtle outer glow — barely bleeds beyond the ring
    float outer     = exp(-pow(d - ring_d, 2.0) * 30.0) * 0.18;

    float intensity = ring + outer;
    float alpha     = clamp(intensity, 0.0, 1.0);

    vec4 tint = fragColor * colDiffuse;
    finalColor = vec4(tint.rgb, alpha * tint.a);
}
