import * as THREE from 'three';
import { setEmitters } from './shaderlib.js';
import { LIGHT_SCALE } from './lights.js';

// Keep physical lights, indirect fill, visible sources and atmospheric scattering in sync.
export function createPlazaLighting(lights, moon, moonDir, post) {
  const defaults = {
    keyAzimuth: Math.round(THREE.MathUtils.radToDeg(Math.atan2(moonDir.x, moonDir.z))),
    keyElevation: Math.round(THREE.MathUtils.radToDeg(Math.asin(-moonDir.y))),
    keyShadows: 1, lampStrength: 1, lampRange: 1, lampShadows: 1,
    lampColor: '#' + lights.points[0].color.getHexString(),
  };
  const fields = [
    ['keyAzimuth', '全局光水平方向', -180, 180, 1], ['keyElevation', '全局光俯角', 5, 85, 1],
    ['keyShadows', '全局光阴影', 0, 1, 1], ['lampColor', '占位灯颜色'],
    ['lampStrength', '占位灯强度', 0, 3, 0.01], ['lampRange', '占位灯范围', 0.5, 2, 0.01],
    ['lampShadows', '占位灯阴影', 0, 1, 1],
  ];
  const base = lights.points.map((light, i) => ({
    intensity: light.intensity, distance: light.distance,
    scatterIntensity: lights.scatter[i].intensity, scatterRange: lights.scatter[i].range,
    strength: lights.emitters[i].strength, radius: lights.emitters[i].radius,
    glowStrength: light.intensity / LIGHT_SCALE * 0.55,
  }));
  function apply(settings) {
    const azimuth = THREE.MathUtils.degToRad(settings.keyAzimuth);
    const elevation = THREE.MathUtils.degToRad(settings.keyElevation);
    moonDir.set(Math.sin(azimuth) * Math.cos(elevation), -Math.sin(elevation), Math.cos(azimuth) * Math.cos(elevation));
    moon.castShadow = settings.keyShadows > 0;
    lights.points.forEach((light, i) => {
      light.color.set(settings.lampColor);
      light.intensity = base[i].intensity * settings.lampStrength;
      light.distance = base[i].distance * settings.lampRange;
      light.shadow.camera.far = light.distance;
      light.shadow.camera.updateProjectionMatrix();
      light.userData.wantsShadow = settings.lampShadows > 0 && settings.lampStrength > 0;
      light.userData.marker.material.emissive.copy(light.color);
      light.userData.marker.material.emissiveIntensity = 1.5 * settings.lampStrength;
      light.userData.glow.material.uniforms.uColor.value.copy(light.color).multiplyScalar(base[i].glowStrength * settings.lampStrength);
      Object.assign(lights.scatter[i], { intensity: base[i].scatterIntensity * settings.lampStrength, range: base[i].scatterRange * settings.lampRange });
      lights.scatter[i].color.copy(light.color);
      Object.assign(lights.emitters[i], { strength: base[i].strength * settings.lampStrength, radius: base[i].radius * settings.lampRange });
      lights.emitters[i].color.copy(light.color);
    });
    setEmitters(lights.emitters);
    post.scatter.setLights(lights.scatter);
  }
  return { defaults, fields, apply };
}
