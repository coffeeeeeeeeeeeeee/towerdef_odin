#version 330

// Mismo cálculo que el viejo assets/glow_circle.glsl (2D, borrado en la
// migración a 3D) — anillo con falloff gaussiano centrado en d=0.45 del UV
// [-1,1], más un glow exterior tenue. El color/alpha vienen de fragColor
// (tinte por-partícula + fade-out por vida, ya resueltos en Odin antes de
// dibujar — ver draw_glow_ring_3d), no hay uniform de tinte separado.
in vec2 fragTexCoord;
in vec4 fragColor;

out vec4 finalColor;

void main() {
    vec2 uv = fragTexCoord * 2.0 - 1.0;
    float d = length(uv);

    float ring_d = 0.45;
    float ring  = exp(-pow(d - ring_d, 2.0) * 180.0);
    float outer = exp(-pow(d - ring_d, 2.0) * 30.0) * 0.18;

    float intensity = ring + outer;
    float alpha = clamp(intensity, 0.0, 1.0);

    finalColor = vec4(fragColor.rgb, alpha * fragColor.a);
}
