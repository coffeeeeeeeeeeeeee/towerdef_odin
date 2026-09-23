#version 330

// Shader de modelos reales (árboles importados, ver tree_models en
// rendering.odin) — a diferencia de lighting.vs, que asume TODO ya en
// espacio de mundo (comentario ahí: "no hay una matriz de modelo por
// objeto"), acá SÍ hace falta matModel/matNormal: los árboles se rotan
// (para corregir modelos exportados Z-up) y escalan por instancia vía
// DrawModelEx, y esa transformación solo llega al vertex shader a través
// de esas dos matrices — raylib las resuelve y sube solas por el nombre
// estándar ("matModel"/"matNormal"), igual que ya hace con "mvp".
layout(location = 0) in vec3 vertexPosition;
layout(location = 1) in vec2 vertexTexCoord;
layout(location = 2) in vec3 vertexNormal;
layout(location = 3) in vec4 vertexColor;

uniform mat4 mvp;
uniform mat4 matModel;
uniform mat4 matNormal;

uniform mat4 lightSpaceMatrix;

out vec3 fragNormal;
out vec2 fragTexCoord;
out vec4 fragColor;
out vec4 fragPosLightSpace;

void main() {
    vec4 worldPos = matModel * vec4(vertexPosition, 1.0);
    fragNormal = normalize((matNormal * vec4(vertexNormal, 0.0)).xyz);
    fragTexCoord = vertexTexCoord;
    fragColor = vertexColor;
    fragPosLightSpace = lightSpaceMatrix * worldPos;
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
