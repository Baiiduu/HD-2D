import * as THREE from 'three';
import { FOG_UNIFORMS, bindFogUniforms, setEmitters } from './shaderlib.js';
import { makeCharacter } from './sprites.js';
import { createFestivalProgress } from './festival-progress.js';
import { createFestivalAudio } from './festival-audio.js';
import './festival-stage.css';

export function createFestivalStage({ scene, world, renderer, lights, props, post, sprites, player, placePlayer, dust }) {
  const progress = createFestivalProgress();
  const audio = createFestivalAudio();
  const interactions = world.json.festival.interactions;
  const group = new THREE.Group(); scene.add(group);
  const stone = makeCharacter('props/component_014.png', renderer, { size: [0.7, 0.94], pixels: [166, 222] });
  stone.position.set(...interactions.stone.position); stone.position.y += 0.6; group.add(stone);
  const lamp = new THREE.Group(); lamp.position.set(...interactions.lamp.position); group.add(lamp);
  const plinth = new THREE.Mesh(new THREE.CylinderGeometry(0.48, 0.6, 0.45, 8), new THREE.MeshStandardMaterial({ color: 0x57666c, roughness: 0.65 }));
  plinth.position.y = 0.22; plinth.receiveShadow = plinth.castShadow = true; lamp.add(plinth);
  const core = new THREE.Mesh(new THREE.OctahedronGeometry(0.3), new THREE.MeshStandardMaterial({ color: 0xffd98a, emissive: 0xffb64c, emissiveIntensity: 2 }));
  core.position.y = 1.0; lamp.add(core);
  const ring = new THREE.Mesh(new THREE.TorusGeometry(0.42, 0.035, 6, 24), new THREE.MeshStandardMaterial({ color: 0xf3d7a0, emissive: 0xffc46c, emissiveIntensity: 1 }));
  ring.position.y = 1; lamp.add(ring);
  const lampLight = new THREE.PointLight(0xffc477, 6, 8, 1.7); lampLight.position.y = 1; lamp.add(lampLight);
  const pollution = new THREE.PointLight(0x368ce8, 0, 13, 1.5); pollution.position.set(9, 2.5, -6); group.add(pollution);
  world.colliders.push({ type: 'circle', x: lamp.position.x, z: lamp.position.z, r: 0.48 });
  const riverLamps = [];
  for (let i = 0; i < 9; i++) {
    const material = new THREE.MeshStandardMaterial({ color: 0xffdca3, emissive: 0xffb54b, emissiveIntensity: 2 });
    const mesh = new THREE.Mesh(new THREE.BoxGeometry(0.2, 0.13, 0.24), material);
    mesh.position.set(world.json.festival.riverX + Math.sin(i * 2) * 0.27, world.waterY(-1) + 0.12, -7 + i * 1.6);
    mesh.userData.startZ = mesh.position.z; group.add(mesh); riverLamps.push(mesh);
  }
  bindFogUniforms(group);
  const sourceLevels = lights.sources.map((source) => ({ ...source, intensity: source.light.intensity,
    glowColor: source.glow?.material.uniforms.uColor.value.clone(), level: 1 }));
  const emissive = props.group.children.filter((mesh) => mesh.material.emissiveIntensity > 0 || mesh.userData.style === 'redlantern');
  const scatterBase = post.scatter.uniforms.get('uLC').value.map((value) => value.clone());
  const emitters = [...props.emitters, ...lights.emitters];
  const emitterBase = emitters.map((emitter) => emitter.strength);
  const lampEmitter = { a: lampLight.getWorldPosition(new THREE.Vector3()), b: lampLight.getWorldPosition(new THREE.Vector3()),
    color: lampLight.color, strength: 1.5, radius: 7, wrap: 1 };

  const host = document.createElement('section'); host.id = 'festival-stage';
  host.innerHTML = `
    <div class="festival-task"><span class="festival-tag">第一阶段 · 事件核心</span><h1>仙门灯会·异变</h1><p class="festival-objective"></p><small class="festival-inventory">灵石 0 / 1</small></div>
    <div class="festival-intro"><div><h2>今晚，灯会正盛</h2><p>去河岸放一盏灯，再看看灯阵发生了什么。</p><p class="festival-note">现有素材验证版 · NPC 动作为占位 · 声音为临时合成</p><button type="button" data-stage-action="start">进入灯会</button></div></div>
    <p class="festival-announcement" role="status" aria-live="polite" hidden></p>
    <div class="festival-bottom"><p class="festival-prompt"></p><div><button type="button" data-stage-action="sound">声音：开</button><button type="button" data-stage-action="restart">重新体验</button><a href="?scene=benchmark">原视觉基准</a></div></div>
    <details class="festival-inspection"><summary>开发观察点</summary><p>仅移动机位，不推进事件</p><button type="button" data-location="spawn">广场</button><button type="button" data-location="river">河岸</button><button type="button" data-location="stone">灵石旁</button><button type="button" data-location="lamp">灵灯旁</button></details>`;
  document.body.appendChild(host);
  const objective = host.querySelector('.festival-objective');
  const prompt = host.querySelector('.festival-prompt');
  const inventory = host.querySelector('.festival-inventory');
  const announcement = host.querySelector('.festival-announcement');
  let started = false, nearest = null, elapsed = 0, messageUntil = 0, lockUntil = 0, flow = 0;
  function announce(text, duration = 4) { announcement.textContent = text; announcement.hidden = false; messageUntil = elapsed + duration; }
  function refresh() {
    objective.textContent = progress.phase === 'festival' ? '到石桥河岸放一盏河灯' : progress.phase === 'restored'
      ? '第一座引灵灯已恢复 · 广场重新亮起，河岸仍待修复' : progress.stone ? '将灵石放入广场引灵灯' : '异变：寻找广场灵石，修复引灵灯';
    inventory.textContent = `灵石 ${progress.stone ? 1 : 0} / 1`;
  }
  refresh();
  host.querySelector('[data-stage-action="start"]').addEventListener('click', async () => {
    started = true; host.querySelector('.festival-intro').hidden = true;
    try { await audio.start(); audio.state(progress.phase); } catch { announce('声音未能开启，可以继续体验画面。'); }
  });
  host.querySelector('[data-stage-action="sound"]').addEventListener('click', async (event) => {
    try { event.target.textContent = `声音：${await audio.toggle() ? '开' : '关'}`; } catch { announce('浏览器无法切换声音。'); }
  });
  host.querySelector('[data-stage-action="restart"]').addEventListener('click', () => {
    progress.phase = 'festival'; progress.stone = false; lockUntil = 0; flow = 0;
    placePlayer(...[world.json.player.spawn[0], world.json.player.spawn[2]]);
    audio.state(progress.phase); refresh(); announce('灯会已重置，可以重新放灯。');
  });
  for (const button of host.querySelectorAll('[data-location]')) button.addEventListener('click', () => {
    const id = button.dataset.location;
    const point = id === 'spawn' ? world.json.player.spawn : interactions[id].position;
    // Observe next to the object, never inside its collision footprint.
    placePlayer(point[0] - (id === 'lamp' ? 1.05 : 0), point[2] + (id === 'lamp' ? 0.55 : 0.35));
  });
  window.addEventListener('keydown', (event) => {
    if (event.code !== 'KeyE' || event.repeat || event.target.closest?.('#visual-controls, #festival-stage') || !started || elapsed < lockUntil || !nearest) return;
    const result = progress.interact(nearest);
    if (result === 'blackout') { audio.bell(130.81); lockUntil = elapsed + 1.8; announce('灯火尽灭，河灯逆流。引灵灯阵失去了灵力。', 5); }
    if (result === 'stone') { audio.bell(659.25); announce('拾取灵石 · 将它放入广场引灵灯'); }
    if (result === 'restored') { audio.bell(523.25); announce('引灵灯恢复 · 暖光与生机回到广场', 5); }
    if (result) { audio.state(progress.phase); refresh(); }
  });
  function update(dt) {
    elapsed += dt;
    if (elapsed > messageUntil) announcement.hidden = true;
    nearest = null;
    if (started && elapsed >= lockUntil) {
      const active = progress.phase === 'festival' ? ['river'] : progress.phase === 'blackout' ? progress.stone ? ['lamp'] : ['stone', 'lamp'] : [];
      let distance = Infinity;
      for (const id of active) {
        const item = interactions[id]; const d = Math.hypot(player.x - item.position[0], player.z - item.position[2]);
        if (d < item.radius && d < distance) { nearest = id; distance = d; }
      }
    }
    prompt.textContent = nearest === 'river' ? 'E · 放一盏河灯' : nearest === 'stone' ? 'E · 拾取灵石'
      : nearest === 'lamp' ? progress.stone ? 'E · 嵌入灵石，修复引灵灯' : '引灵灯已熄灭 · 需要一枚灵石'
      : progress.phase === 'restored' ? 'M1 事件闭环完成 · 可以继续观察画面或重新体验' : 'WASD / 方向键移动 · 靠近目标后按 E';
    const blend = 1 - Math.exp(-dt * 3.5);
    dust.visible = progress.phase !== 'blackout';
    const targetFog = progress.phase === 'festival' ? 0 : progress.phase === 'blackout' ? 0.85 : 0.3;
    FOG_UNIFORMS.uEventFogBlend.value = THREE.MathUtils.lerp(FOG_UNIFORMS.uEventFogBlend.value, targetFog, blend);
    pollution.intensity = THREE.MathUtils.lerp(pollution.intensity, progress.phase === 'festival' ? 0 : 9, blend);
    function target(region) { return progress.phase === 'festival' || progress.phase === 'restored' && region === 'square' ? 1 : 0; }
    for (const source of sourceLevels) {
      source.level = THREE.MathUtils.lerp(source.level, target(source.region), blend);
      source.light.intensity = source.intensity * source.level;
      if (source.glow) source.glow.material.uniforms.uColor.value.copy(source.glowColor).multiplyScalar(source.level);
    }
    for (const mesh of emissive) {
      const uniform = mesh.material.userData.lampLevel;
      uniform.value = THREE.MathUtils.lerp(uniform.value, target(mesh.userData.region), blend);
    }
    for (let i = 0; i < lights.scatter.length; i++) {
      post.scatter.uniforms.get('uLC').value[i].copy(scatterBase[i]);
      const scale = sourceLevels[i]?.level ?? 1;
      post.scatter.uniforms.get('uLC').value[i].x *= scale;
      post.scatter.uniforms.get('uLC').value[i].y *= scale;
      post.scatter.uniforms.get('uLC').value[i].z *= scale;
    }
    emitters.forEach((emitter, i) => {
      const region = i < props.emitters.length ? 'square' : sourceLevels[i - props.emitters.length]?.region;
      emitter.strength = emitterBase[i] * target(region);
    });
    const lightTarget = progress.phase === 'blackout' ? 0 : 6;
    lampLight.intensity = THREE.MathUtils.lerp(lampLight.intensity, lightTarget, blend);
    lampEmitter.strength = lampLight.intensity / 4;
    setEmitters([...emitters, lampEmitter]);
    core.material.emissiveIntensity = 0.1 + lampLight.intensity / 3;
    ring.material.emissiveIntensity = 0.1 + lampLight.intensity / 6;
    core.rotation.y = elapsed * 0.55; core.position.y = 1 + Math.sin(elapsed * 2) * 0.05;
    stone.visible = progress.phase === 'blackout' && !progress.stone;
    stone.position.y = interactions.stone.position[1] + 0.6 + Math.sin(elapsed * 2.3) * 0.08;
    flow += dt * (progress.phase === 'festival' ? 0.35 : -0.35);
    for (const mesh of riverLamps) {
      mesh.position.z = ((mesh.userData.startZ + flow + 8) % 16 + 16) % 16 - 8;
      mesh.material.emissiveIntensity = progress.phase === 'festival' ? 2 : 0.06;
    }
    for (const rec of sprites) if (!rec.isPlayer && rec.kind !== 'decoration') rec.activity = target(rec.region);
  }
  return { progress, update, get locked() { return !started || elapsed < lockUntil; } };
}
