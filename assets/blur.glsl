#version 330

// Blur separable de 1 dimensión (tent filter — aproximación barata de un
// gaussiano). Se usa en 2 pasadas (horizontal, después vertical) para el
// efecto de vidrio esmerilado de la pantalla de Pausa. `direction` alterna
// entre (1,0) y (0,1) según la pasada.

in vec2 fragTexCoord;
in vec4 fragColor;
out vec4 finalColor;

uniform sampler2D texture0;
uniform vec2  texelSize;   // (1/ancho, 1/alto) de la textura muestreada
uniform vec2  direction;   // (1,0) pasada horizontal, (0,1) pasada vertical

const int R = 6;           // radio fijo del blur, en texels (hardcoded, igual que water.glsl)

void main() {
    vec4  sum   = vec4(0.0);
    float total = 0.0;

    for (int i = -R; i <= R; i++) {
        float w = 1.0 - abs(float(i)) / float(R + 1);
        vec2 offset = direction * texelSize * float(i);
        sum   += texture(texture0, fragTexCoord + offset) * w;
        total += w;
    }

    finalColor = (sum / total) * fragColor;
}
