// A compact, independent M1 map. Reuse art/material templates, not the four-biome layout.
export function createFestivalLayout(base) {
  const json = structuredClone(base);
  json.name = '仙门灯会·异变 M1';
  json.camera = { ...base.camera, fov_vertical_deg: 30, pitch_deg: 18, distance: 14 };
  json.terrain.origin_cell = [-8, -8];
  json.terrain.size = [19, 17];
  json.terrain.rows_north_to_south = Array.from({ length: 17 }, (_, j) => Array.from({ length: 19 }, (_, i) => {
    const x = i - 8, z = j - 8;
    const river = x === 4;
    const high = z <= -6;
    const square = x >= -5 && x <= 2 && z >= -4 && z <= 4;
    const road = z === 0 || (x === -3 && z >= -5 && z <= 5);
    return { biome: square ? 2 : 3, level: river ? (high ? 0 : -1) : (high ? 1 : 0),
      overlay: river ? 4 | (z === 0 ? 8 : 0) : road ? 1 : z === -5 && x <= 3 ? 16 : 0 };
  }));
  json.meshes = base.meshes.filter((m) => /Cultivation\//.test(m.name)).map((m) => {
    const copy = structuredClone(m);
    copy.transform.origin[0] += 1.8;
    copy.transform.origin[2] -= 7.2;
    copy.region = 'square';
    return copy;
  });
  const lantern = base.meshes.filter((m) => /^World\/Lantern0\//.test(m.name));
  const places = [[-8, 3, 'square'], [-1, 4, 'square'], [2, -1, 'square'], [4.7, 1, 'river'], [8.1, -1, 'river'], [-1, -5, 'square']];
  json.lights = [];
  for (const [i, [x, z, region]] of places.entries()) {
    for (const original of lantern) {
      const m = structuredClone(original);
      m.name = m.name.replace('Lantern0', 'Lantern' + i);
      m.transform.origin[0] += x - 20.9;
      m.transform.origin[2] += z + 1;
      m.region = region;
      json.meshes.push(m);
    }
    json.lights.push({ name: `World/Lantern${i}/Light`, type: 'OmniLight3D', position: [x, 1.24, z],
      color: [1, 0.72, 0.42], energy: 2.2, range: 5.5, shadows: i < 4, region });
  }
  for (const [i, x] of [-7.2, -2.8].entries()) {
    json.lights.push({ name: `World/Cultivation/Lantern${i}`, type: 'OmniLight3D', position: [x, 1.8, -2.05],
      color: [1, 0.68, 0.35], energy: 2.5, range: 6, shadows: false, region: 'square' });
  }
  json.player = { ...base.player, spawn: [-4, 0.02, 3], speed: 3.4 };
  const sprite = (name, texture, x, z, extra = {}) => ({ name, texture, center_position: [x, 0.79, z], ...extra });
  json.sprites = [
    sprite('Player/Sprite', 'characters/char_04_white_robed_swordsman.png', -4, 3),
    sprite('Festival/NPC/Tea', 'characters/char_05_jade_robed_cultivator.png', -6.5, 0.3, { region: 'square' }),
    sprite('Festival/NPC/Guard', 'characters/char_04_white_robed_swordsman.png', -1.5, -3, { region: 'square' }),
    sprite('Festival/NPC/River', 'characters/char_05_jade_robed_cultivator.png', 3.7, -1.8, { region: 'river' }),
    sprite('Festival/Prop/Pine', 'props/component_001.png', -10, -1, { kind: 'decoration', size: [4.2, 3.9], pixels: [276, 256], center_position: [-10, 1.97, -1], collision_radius: 0.45 }),
    sprite('Festival/Prop/Fern', 'props/component_004.png', 9, 3, { kind: 'decoration', size: [1.5, 1.46], pixels: [232, 226], center_position: [9, 0.75, 3], collision_radius: 0 }),
    sprite('Festival/Prop/Gate', 'props/component_009.png', 10, -7.5, { kind: 'decoration', size: [4.3, 4.5], pixels: [242, 254], center_position: [10, 3.05, -7.5], collision_radius: 0 }),
  ];
  json.particles = [{ name: 'Festival/Fireflies', center: [-4, 1, 2], amount: 32 }];
  json.fog_volumes = [{ name: 'Festival/WaterfallMist', center: [6.4, -0.05, -8.8], size: [2, 1.1, 1.8] }];
  json.festival = {
    version: 1, riverX: 6.4,
    interactions: {
      river: { position: [4.5, 0.02, 0], radius: 1.5 },
      stone: { position: [-0.5, 0.02, 2], radius: 1.3 },
      lamp: { position: [1.5, 0.02, -1.5], radius: 1.5 },
    },
  };
  return json;
}
