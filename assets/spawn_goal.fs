#version 330

// Marca de spawn/goal — disco relleno con pulso suave de intensidad, en
// vez del cilindro plano de color sólido que había antes. El color (verde
// spawn / rojo goal) viaja por vértice, igual que range_disc — este shader
// no distingue spawn de goal, es puramente el color el que cambia.
in vec2 fragTexCoord;
in vec4 fragColor;

uniform float pulseTime;

out vec4 finalColor;

void main() {
    vec2 uv = fragTexCoord * 2.0 - 1.0;
    float d = length(uv);

    // Disco relleno con borde suave — banda de antialiasing angosta en
    // d=1, no un difuminado ancho como range_disc (que crece desde el
    // centro). Acá el relleno es parejo de punta a punta, es una marca de
    // lugar, no un radio de efecto.
    float alpha = 1.0 - smoothstep(0.85, 1.0, d);

    // Pulso de intensidad, no de presencia — nunca llega a apagarse del
    // todo, solo respira entre "vivo" y "más vivo".
    float pulse = 0.75 + 0.25 * sin(pulseTime);
    alpha *= pulse;

    finalColor = vec4(fragColor.rgb, alpha * fragColor.a);
}
