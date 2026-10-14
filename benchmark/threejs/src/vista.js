import * as THREE from 'three';
import { FOG, GLSL_COMMON } from './shaderlib.js';

// Three native Meowa atlas bands follow separate distant world-space rings.
// This preserves parallax and surrounds the camera when its horizontal angle changes.
export function buildVista(world, atlas) {
  const group = new THREE.Group();
  group.name = 'Mountain valley';
  group.position.set((world.minX + world.maxX) / 2, 0, (world.minZ + world.maxZ) / 2);
  const layers = [
    { radius: 60, bottom: -30, height: 50, repeat: 2, rect: [0, 0, 1024, 258], haze: 0.18, rotation: -0.7 },
    { radius: 110, bottom: -40, height: 60, repeat: 3, rect: [0, 278, 1024, 241], haze: 0.27, rotation: 0 },
    { radius: 200, bottom: -60, height: 85, repeat: 3, rect: [0, 540, 1024, 228], haze: 0.46, rotation: 0.8 },
  ];
  for (const layer of layers) {
    const [x, y, width, height] = layer.rect;
    const material = new THREE.ShaderMaterial({
      side: THREE.DoubleSide, fog: false,
      uniforms: {
        uAtlas: { value: atlas }, uRect: { value: new THREE.Vector4(x / 1024, 1 - (y + height) / 768, width / 1024, height / 768) },
        uFog: { value: FOG.color }, uRock: { value: new THREE.Color(0.028, 0.03, 0.042) },
        uHaze: { value: layer.haze }, uHazeScale: { value: 1 },
        uBrightness: { value: 1 }, uWindows: { value: 1.5 },
        uRepeat: { value: layer.repeat },
      },
      vertexShader: `varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`,
      fragmentShader: `
        uniform sampler2D uAtlas; uniform vec4 uRect;
        uniform vec3 uFog, uRock; uniform float uHaze, uHazeScale, uBrightness, uWindows, uRepeat;
        varying vec2 vUv;
        ${GLSL_COMMON}
        void main(){
          vec2 localUv = vec2(fract(vUv.x * uRepeat), vUv.y);
          vec4 art = texPixelTile(uAtlas, localUv, uRect.xy, uRect.zw, vec2(1024.0, 768.0), vUv * vec2(uRepeat, 1.0) * uRect.zw);
          if (art.a < 0.4) discard;
          vec3 c = art.rgb * uRock / vec3(0.028, 0.03, 0.042) * uBrightness;
          float warm = smoothstep(1.3, 2.0, art.r / max(art.b, 0.005)) * smoothstep(0.05, 0.18, art.r);
          c *= mix(1.0, uWindows, warm);
          float low = 1.0 - smoothstep(0.06, 0.55, vUv.y);
          float haze = clamp((uHaze + low * 0.55) * uHazeScale, 0.0, 0.96);
          c = mix(c, uFog * vec3(0.9, 0.92, 1.1), haze);
          gl_FragColor = vec4(c, 1.0);
        }`,
    });
    const geometry = new THREE.CylinderGeometry(layer.radius, layer.radius, layer.height, 128, 1, true);
    geometry.translate(0, layer.bottom + layer.height / 2, 0);
    const mesh = new THREE.Mesh(geometry, material);
    mesh.rotation.y = layer.rotation;
    group.add(mesh);
  }
  const defaults = { vistaHeight: 0, vistaDistance: 1, vistaBrightness: 1, vistaWindows: 1.5 };
  const fields = [
    ['vistaHeight', '远景高度', -20, 20, 0.5], ['vistaDistance', '远景距离比例', 0.65, 1.8, 0.01],
    ['vistaBrightness', '远景亮度', 0.3, 2, 0.01], ['vistaWindows', '远处宗门灯火', 0, 3, 0.01],
  ];
  function apply(settings) {
    group.position.y = settings.vistaHeight;
    group.scale.set(settings.vistaDistance, 1, settings.vistaDistance);
    for (const mountain of group.children) {
      mountain.material.uniforms.uBrightness.value = settings.vistaBrightness;
      mountain.material.uniforms.uWindows.value = settings.vistaWindows;
    }
  }
  return { group, defaults, fields, apply };
}
