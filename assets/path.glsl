#version 330

// Blur+threshold del camino: misma técnica que la Fase 1 de water.glsl
// (box blur -> smoothstep en el punto medio) para redondear la máscara
// binaria de tiles de camino en un trazo suave, sin escalones de grilla.

in vec2 fragTexCoord;
in vec4 fragColor;
out vec4 finalColor;

uniform sampler2D texture0;
uniform vec2  texelSize;   // (1/maskW, 1/maskH)
uniform vec4  pathColor;   // relleno del camino
uniform vec4  edgeColor;   // borde/sombra del camino

void main() {
    // Box blur al 50% (radio fijo) sobre la máscara binaria.
    float sum   = 0.0;
    int   R     = 5;
    float total = float((2*R+1) * (2*R+1));
    for (int x = -R; x <= R; x++) {
        for (int y = -R; y <= R; y++) {
            sum += texture(texture0, fragTexCoord + vec2(float(x), float(y)) * texelSize).r;
        }
    }
    sum /= total;

    // Encontrar el centro de los valores blureados (threshold en 0.5) para
    // recuperar un borde nítido pero suavizado a partir del blur.
    float alpha = smoothstep(0.38, 0.62, sum);
    if (alpha < 0.001) { finalColor = vec4(0.0); return; }

    float edge = smoothstep(0.38, 0.62, sum) - smoothstep(0.50, 0.62, sum);

    vec4 color = mix(pathColor, edgeColor, edge * 0.5);
    finalColor = color * alpha;
}
