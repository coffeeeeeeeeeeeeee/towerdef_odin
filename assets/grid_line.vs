#version 330

// Passthrough — mismo patrón que range_disc.vs/glow_ring.vs. Locations
// explícitas porque draw_grid_line_ribbon_3d dibuja en modo inmediato de
// rlgl (un quad angosto por segmento de grilla, no DrawLine3D — ver la
// nota grande en draw_grid_line_ribbon_3d en rendering.odin sobre por qué
// hace falta geometría real). vertexNormal no se usa (la cinta es plana).
layout(location = 0) in vec3 vertexPosition;
layout(location = 1) in vec2 vertexTexCoord;
layout(location = 2) in vec3 vertexNormal;
layout(location = 3) in vec4 vertexColor;

uniform mat4 mvp;

out vec3 fragWorldPos;
out vec4 fragColor;
// U de vertexTexCoord: 0 en una punta del segmento, 1 en la otra (así lo
// arma draw_grid_line_ribbon_3d) — es la posición TANGENCIAL a lo largo
// de la línea, la que usa grid_line.fs para el desvanecido hacia las
// puntas de cada segmento (no hacia el borde del mapa).
out float fragLineT;

void main() {
    fragWorldPos = vertexPosition;
    fragColor = vertexColor;
    fragLineT = vertexTexCoord.x;
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
