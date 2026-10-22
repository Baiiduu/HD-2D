import * as THREE from 'three';

// One unchanged Meowa atlas, six flat decal types. Rectangles use top-left image pixels.
const DETAILS = [
  { key: 'cracks', label: '裂纹数量', rect: [0, 0, 341, 384], max: 90, density: 0.45, size: [1.0, 0.7], opacity: 0.75 },
  { key: 'wear', label: '磨损数量', rect: [341, 0, 341, 384], max: 90, density: 0.5, size: [0.9, 0.7], opacity: 0.7 },
  { key: 'petals', label: '花瓣数量', rect: [682, 0, 342, 384], max: 65, density: 0.3, size: [1.5, 1.4], opacity: 0.95 },
  { key: 'water', label: '水迹数量', rect: [0, 384, 341, 384], max: 36, density: 0.28, size: [2.0, 1.4], opacity: 0.85 },
  { key: 'moss', label: '青苔数量', rect: [341, 384, 341, 384], max: 75, density: 0.32, size: [1.3, 0.8], opacity: 0.85 },
  { key: 'dirt', label: '污渍数量', rect: [682, 384, 342, 384], max: 50, density: 0.25, size: [1.7, 1.2], opacity: 0.65 },
];

function random(seed) {
  let state = seed >>> 0;
  return () => {
    state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
    return state / 4294967296;
  };
}

export function buildGroundDetails(world, atlas, variation) {
  const group = new THREE.Group();
  group.name = 'Ground details';
  const defaults = { stoneVariation: variation.value };
  const fields = [['stoneVariation', '石板明暗变化', 0, 0.25, 0.01]];
  const meshes = new Map();
  const dummy = new THREE.Object3D();
  DETAILS.forEach((detail, index) => {
    defaults[detail.key] = detail.density;
    fields.push([detail.key, detail.label, 0, 1, 0.01]);
    const geometry = new THREE.PlaneGeometry(1, 1);
    const uv = geometry.attributes.uv;
    const [left, top, width, height] = detail.rect;
    for (let i = 0; i < uv.count; i++) {
      uv.setXY(i, (left + uv.getX(i) * width) / 1024, 1 - (top + (1 - uv.getY(i)) * height) / 768);
    }
    geometry.rotateX(-Math.PI / 2);
    const material = new THREE.MeshStandardMaterial({
      map: atlas, transparent: true, opacity: detail.opacity, alphaTest: 0.025,
      roughness: detail.key === 'water' ? 0.65 : 0.86, metalness: 0,
      depthWrite: false, polygonOffset: true, polygonOffsetFactor: -1,
    });
    const mesh = new THREE.InstancedMesh(geometry, material, detail.max);
    mesh.name = detail.key;
    const next = random(8201 + index * 191);
    for (let i = 0; i < detail.max; i++) {
      const scale = 0.75 + next() * 0.5;
      const sx = detail.size[0] * scale, sz = detail.size[1] * scale;
      // Keep the entire rotated plane within the plaza, including at maximum density.
      const margin = Math.hypot(sx, sz) / 2 + 0.05;
      let x = world.minX + margin + next() * (world.maxX - world.minX - margin * 2);
      let z = world.minZ + margin + next() * (world.maxZ - world.minZ - margin * 2);
      if (detail.key === 'moss') {
        // Prefer outer paving, with a little growth in the inner seams.
        if (next() < 0.7) {
          if (next() < 0.5) x = next() < 0.5 ? world.minX + margin : world.maxX - margin;
          else z = next() < 0.5 ? world.minZ + margin : world.maxZ - margin;
        }
        z = THREE.MathUtils.clamp(Math.round(z / 0.4) * 0.4, world.minZ + margin, world.maxZ - margin);
      }
      dummy.position.set(x, world.yoff + 0.004 + index * 0.0005, z);
      dummy.rotation.set(0, next() * Math.PI * 2, 0);
      dummy.scale.set(sx, 1, sz);
      dummy.updateMatrix(); mesh.setMatrixAt(i, dummy.matrix);
    }
    mesh.instanceMatrix.needsUpdate = true;
    mesh.computeBoundingSphere();
    meshes.set(detail.key, { mesh, max: detail.max });
    group.add(mesh);
  });
  function apply(settings) {
    variation.value = settings.stoneVariation;
    for (const [key, { mesh, max }] of meshes) mesh.count = Math.round(max * settings[key]);
  }
  apply(defaults);
  return { group, defaults, fields, apply };
}
