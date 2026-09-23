#version 330

// Disco relleno para rango/AoE de torres, estado de enemigos y pulsos de
// hielo — reemplaza al viejo draw_ground_ring (un anillo sin relleno,
// DrawCircle3D). Acá el relleno crece desde el centro (casi transparente)
// hacia el borde, con un corte nítido exactamente en el radio — lo
// opuesto a un glow típico (que se difumina hacia los dos lados del
// borde). Ver draw_range_disc_3d en rendering.odin.
in vec2 fragTexCoord;
in vec4 fragColor;

out vec4 finalColor;

void main() {
    vec2 uv = fragTexCoord * 2.0 - 1.0;
    float d = length(uv);

    // Difuminado hacia el centro: casi transparente en d=0, crece hacia
    // el borde.
    float alpha = pow(clamp(d, 0.0, 1.0), 1.6);

    // Realce angosto pegado al borde — que se sienta definido, no solo
    // el final de un degradé.
    float rim = smoothstep(0.82, 0.97, d) * 0.5;
    alpha = clamp(alpha + rim, 0.0, 1.0);

    // Corte nítido en d=1 (el radio real) — banda de antialiasing muy
    // angosta, no un difuminado ancho como un glow típico.
    alpha *= 1.0 - smoothstep(0.97, 1.0, d);

    finalColor = vec4(fragColor.rgb, alpha * fragColor.a);
}
