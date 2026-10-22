// Paving and lighting study: original plaza, characters, small light placeholders.
export function createOpeningLayout(base) {
  const json = structuredClone(base);
  json.name = '仙门灯会 · 石板广场';
  json.terrain.origin_cell = [-6, -5];
  json.terrain.size = [10, 11];
  json.terrain.rows_north_to_south = Array.from({ length: 11 }, () =>
    Array.from({ length: 10 }, () => ({ biome: 2, level: 0, overlay: 0 })));
  json.meshes = [];
  json.player = { spawn: [-2.4, 0.02, 1.6], speed: 3.2 };
  json.camera = { fov_vertical_deg: 34, pitch_deg: 32, distance: 22, yaw_deg: 22 };
  json.moon = { direction_light_travels: [-0.5, -0.8, -0.35], color: [0.66, 0.76, 1], energy: 0.32 };
  json.sprites = [
    ['Player/Sprite', 'char_04_white_robed_swordsman.png', -2.4, 1.6],
    ['Residents/ConversationA', 'char_05_jade_robed_cultivator.png', -3.5, -3.2],
    ['Residents/ConversationB', 'char_04_white_robed_swordsman.png', -2.6, -3.4],
    ['Residents/Practice', 'char_04_white_robed_swordsman.png', 0.2, -3.4],
    ['Residents/Tea', 'char_05_jade_robed_cultivator.png', 1.2, 3.6],
    ['Residents/Observer', 'char_05_jade_robed_cultivator.png', 3.6, -2.3],
  ].map(([name, file, x, z]) => ({ name, texture: 'characters/' + file, center_position: [x, 0.77, z] }));
  json.lights = [
    ['Plaza/Lamp01', [-6, 1.9, 3.2]],
    ['Plaza/Lamp02', [-4.6, 1.9, -4.6]],
    ['Plaza/Lamp03', [2.4, 1.9, 1.9]],
  ].map(([name, position]) => ({ name, position, type: 'OmniLight3D', color: [1, 0.74, 0.45], energy: 3, range: 6, shadows: true, placeholder: true }));
  json.particles = [];
  json.fog_volumes = [];
  json.opening = {};
  return json;
}
