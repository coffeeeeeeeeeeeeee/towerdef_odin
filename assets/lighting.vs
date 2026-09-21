#version 330

// Locations explícitas — obligatorio para que el modo inmediato de rlgl
// (DrawCube/DrawCylinder/DrawSphere de torres, árboles, obstáculos, ...)
// alimente los atributos correctos: ese camino escribe por posición fija
// (0/1/2/3), sin consultar el shader por nombre como sí hace DrawModel/
// DrawMesh con la malla del terreno. Sin esto, el compilador puede asignarle
// a vertexNormal una location distinta a la 2 y el shader termina leyendo
// datos que no son la normal — se traduce en "sin iluminación" (plano) en
// formas dibujadas en modo inmediato.
layout(location = 0) in vec3 vertexPosition;
layout(location = 1) in vec2 vertexTexCoord;
layout(location = 2) in vec3 vertexNormal;
layout(location = 3) in vec4 vertexColor;

uniform mat4 mvp;

// Camino "embossed": texture0 es la misma máscara de camino supersampleada
// que usa el fragment shader para pintar pathColor (ver terrain_cache_ensure
// y _path_strip_mask, R = profundidad [0,1]) — acá se reusa para hundir el
// terreno. texture1 es la máscara de agua: un tile de camino sobre agua es
// un puente y no debe hundirse (el agua ya tiene su propia altura especial,
// ver render_bridge_3d). useTerrainMask apaga todo esto para
// formas inmediatas (torres/enemigos/...) que comparten este shader — igual
// que ya hace el fragment shader con pathColor.
uniform sampler2D texture0;
uniform sampler2D texture1;
uniform float useTerrainMask;
uniform float pathEmbossDepth;
uniform vec2  pathMaskTexel;

// Sombra proyectada real — matriz vista×proyección ortográfica del sol
// (ver shadow_light_matrix en rendering.odin). Se calcula con la posición
// YA desplazada por el hundimiento del camino de arriba, para que la
// sombra que cae sobre un tile de camino no quede desalineada del tallado
// visible.
uniform mat4 lightSpaceMatrix;
out vec4 fragPosLightSpace;

out vec3 fragNormal;
out vec4 fragColor;
out vec2 fragTexCoord;

// Todo lo que este proyecto dibuja en 3D ya está en coordenadas de mundo
// absolutas — no hay una matriz de modelo por objeto ni rotación vía la pila
// de rlgl (ni la malla de terreno ni las formas inmediatas de torres/
// enemigos la usan), así que vertexPosition/vertexNormal ya son world-space
// y no hace falta matModel/matNormal.
void main() {
    vec3 pos = vertexPosition;
    vec3 n = normalize(vertexNormal);

    if (useTerrainMask > 0.5) {
        float waterMask = texture(texture1, vertexTexCoord).r;
        float bridgeGuard = 1.0 - waterMask;
        float pathMask = texture(texture0, vertexTexCoord).r;
        pos.y -= pathMask * pathEmbossDepth * bridgeGuard;

        // Normal perturbada por diferencia central de la máscara — sin esto
        // el hundimiento se ve "pintado" (mismo shading que el terreno
        // plano) en vez de tallado: las paredes de la franja necesitan
        // recibir luz distinta al piso.
        float mL = texture(texture0, vertexTexCoord - vec2(pathMaskTexel.x, 0.0)).r;
        float mR = texture(texture0, vertexTexCoord + vec2(pathMaskTexel.x, 0.0)).r;
        float mD = texture(texture0, vertexTexCoord - vec2(0.0, pathMaskTexel.y)).r;
        float mU = texture(texture0, vertexTexCoord + vec2(0.0, pathMaskTexel.y)).r;
        // deltaY = -mask*depth, así que el gradiente de altura es
        // -(mR-mL)*depth en x — la normal de un heightfield es
        // (-dY/dx, 1, -dY/dz), o sea acá se SUMA (mR-mL)*depth, no se resta.
        float dHdx = (mR - mL) * pathEmbossDepth * bridgeGuard;
        float dHdz = (mU - mD) * pathEmbossDepth * bridgeGuard;
        n = normalize(n + vec3(dHdx, 0.0, dHdz));
    }

    fragNormal = n;
    fragColor = vertexColor;
    fragTexCoord = vertexTexCoord;
    fragPosLightSpace = lightSpaceMatrix * vec4(pos, 1.0);
    gl_Position = mvp * vec4(pos, 1.0);
}
