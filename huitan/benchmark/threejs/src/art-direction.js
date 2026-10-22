import * as THREE from 'three';
import { FOG, FOG_UNIFORMS } from './shaderlib.js';
import './art-direction.css';

const STORAGE_KEY = 'four-realms.visual-settings.v1';
const hex = (color) => '#' + color.getHexString();
const effectValue = (effect, name) => effect.uniforms.get(name).value;
const setEffect = (effect, name, value) => { effect.uniforms.get(name).value = value; };

// One controller owns the live settings; the UI and JSON profiles use the same values.
export function createArtDirection({ scene, sky, mountains, moon, hemi, post, ground, lighting, vista, cam, camera, onCameraChange, storageKey = STORAGE_KEY, legacyStorageKey, preservedSettings = [] }) {
  const su = sky.material.uniforms;
  const defaults = {
    fogColor: hex(FOG.color), fogDensity: FOG.density, fogStart: FOG_UNIFORMS.uFogStart.value,
    heightDensity: FOG.heightDensity, heightFalloff: FOG.heightFalloff, heightBase: FOG.heightBase,
    skyTop: hex(su.uZenith.value), skyMid: hex(su.uMid.value), glowColor: hex(su.uGlowColor.value),
    horizonGlow: su.uGlowStrength.value, stars: su.uStars.value, milky: su.uMilky.value,
    mountainColor: hex(mountains.children[0].material.uniforms.uRock.value), mountainHaze: 1,
    moonColor: hex(moon.color), moonEnergy: moon.intensity,
    ambientColor: hex(hemi.color), groundColor: hex(hemi.groundColor), ambientEnergy: hemi.intensity,
    scatter: effectValue(post.scatter, 'uStrength'), exposure: effectValue(post.scatter, 'uExposure'),
    brightness: 1, contrast: 1, saturation: effectValue(post.grade, 'uSat'), splitToning: effectValue(post.grade, 'uSplit'), temperature: 0,
    bloom: post.bloom.intensity, bloomThreshold: post.bloom.luminanceMaterial.threshold,
    vignette: effectValue(post.vignette, 'darkness'), ao: post.ao.configuration.intensity,
    dofRadius: effectValue(post.dof, 'uMaxR'), dofFar: effectValue(post.dof, 'uFarMax'),
    fov: cam.fov, pitch: cam.pitch, yaw: cam.yaw, distance: cam.dist,
    ...ground?.defaults,
    ...lighting?.defaults,
    ...vista?.defaults,
  };
  const settings = { ...defaults };
  const originalColors = Object.fromEntries(Object.entries({
    fogColor: FOG.color, skyTop: su.uZenith.value, skyMid: su.uMid.value, glowColor: su.uGlowColor.value,
    mountainColor: mountains.children[0].material.uniforms.uRock.value,
    moonColor: moon.color, ambientColor: hemi.color, groundColor: hemi.groundColor,
  }).map(([key, color]) => [key, color.clone()]));
  const setColor = (key, color) => {
    if (settings[key] === defaults[key]) color.copy(originalColors[key]);
    else color.set(settings[key]);
  };
  const groups = [
    ['色彩与后处理', true, [
      ['exposure', '曝光', 0.2, 3, 0.01], ['brightness', '亮度', 0.5, 1.5, 0.01],
      ['contrast', '对比度', 0.5, 1.8, 0.01], ['saturation', '饱和度', 0, 2, 0.01],
      ['temperature', '色温 · 冷 → 暖', -1, 1, 0.01], ['splitToning', '冷暗暖亮染色', 0, 2, 0.01],
      ['bloom', '泛光强度', 0, 2, 0.01], ['bloomThreshold', '泛光阈值', 0, 2, 0.01],
      ['vignette', '暗角', 0, 1, 0.01],
    ]],
    ['雾与大气', true, [
      ['fogColor', '雾与地平线颜色'], ['fogDensity', '距离雾密度', 0, 0.06, 0.001],
      ['fogStart', '起雾距离', 0, 80, 0.5], ['heightDensity', '低处雾密度', 0, 0.2, 0.001],
      ['heightFalloff', '高度衰减', 0.05, 2, 0.01], ['heightBase', '雾基准高度', -5, 5, 0.1],
      ['scatter', '灯光空气散射', 0, 0.08, 0.001],
    ]],
    ['天空与远景', false, [
      ['skyTop', '天顶颜色'], ['skyMid', '天空中部颜色'], ['glowColor', '地平线辉光颜色'],
      ['horizonGlow', '地平线辉光', 0, 3, 0.01], ['stars', '星光强度', 0, 3, 0.01],
      ['milky', '银河强度', 0, 3, 0.01], ['mountainColor', '远山底色'], ['mountainHaze', '远山雾化', 0, 2, 0.01],
    ]],
    [lighting ? '全局光与环境光' : '环境光与月光', !!lighting, [
      ['moonColor', lighting ? '全局光颜色' : '月光颜色'], ['moonEnergy', lighting ? '全局光强度' : '月光强度', 0, 6, 0.01],
      ['ambientColor', '环境光颜色'], ['groundColor', '地面反弹光颜色'], ['ambientEnergy', '环境光强度', 0, 3, 0.01],
    ]],
    ['景深与接触阴影', false, [
      ['dofRadius', '景深模糊半径', 0, 16, 0.1], ['dofFar', '远景模糊比例', 0, 1, 0.01],
      ['ao', '接触阴影强度', 0, 5, 0.01],
    ]],
    ['镜头', false, [
      ['fov', '视野角度', 15, 55, 0.5], ['pitch', '俯角', 0, 40, 0.5], ['distance', '跟随距离', 6, 22, 0.1],
      ['yaw', '横向旋转', -180, 180, 0.5],
    ]],
  ];
  if (vista) groups.find(([title]) => title === '天空与远景')[2].push(...vista.fields);
  if (lighting) groups.unshift(['光源方向与占位灯', true, lighting.fields]);
  if (ground) groups.unshift(['石板与覆盖细节', true, ground.fields]);
  const fields = new Map(groups.flatMap(([, , items]) => items.map((field) => [field[0], field])));

  function apply() {
    ground?.apply(settings);
    lighting?.apply(settings);
    vista?.apply(settings);
    setColor('fogColor', FOG.color);
    FOG.density = scene.fog.density = settings.fogDensity;
    scene.fog.color.copy(FOG.color);
    scene.background.copy(FOG.color);
    FOG.heightDensity = FOG_UNIFORMS.uFogHeightDensity.value = settings.heightDensity;
    FOG.heightFalloff = FOG_UNIFORMS.uFogHeightFalloff.value = settings.heightFalloff;
    FOG.heightBase = FOG_UNIFORMS.uFogHeightBase.value = settings.heightBase;
    FOG_UNIFORMS.uFogStart.value = settings.fogStart;
    setColor('skyTop', su.uZenith.value); setColor('skyMid', su.uMid.value);
    setColor('glowColor', su.uGlowColor.value); su.uGlowStrength.value = settings.horizonGlow;
    su.uStars.value = settings.stars; su.uMilky.value = settings.milky;
    for (const mountain of mountains.children) {
      setColor('mountainColor', mountain.material.uniforms.uRock.value);
      mountain.material.uniforms.uHazeScale.value = settings.mountainHaze;
    }
    setColor('moonColor', moon.color); moon.intensity = settings.moonEnergy;
    setColor('ambientColor', hemi.color); setColor('groundColor', hemi.groundColor); hemi.intensity = settings.ambientEnergy;
    setEffect(post.scatter, 'uStrength', settings.scatter); setEffect(post.scatter, 'uExposure', settings.exposure);
    for (const [key, uniform] of [['brightness', 'uBrightness'], ['contrast', 'uContrast'], ['saturation', 'uSat'], ['splitToning', 'uSplit'], ['temperature', 'uTemperature']]) {
      setEffect(post.grade, uniform, settings[key]);
    }
    post.bloom.intensity = settings.bloom;
    post.bloom.luminanceMaterial.threshold = settings.bloomThreshold;
    setEffect(post.vignette, 'darkness', settings.vignette);
    post.ao.configuration.intensity = settings.ao;
    setEffect(post.dof, 'uMaxR', settings.dofRadius); setEffect(post.dof, 'uFarMax', settings.dofFar);
    const cameraChanged = cam.fov !== settings.fov || cam.pitch !== settings.pitch || cam.dist !== settings.distance || cam.yaw !== settings.yaw;
    cam.fov = camera.fov = settings.fov; cam.pitch = settings.pitch; cam.dist = settings.distance; cam.yaw = settings.yaw;
    if (cameraChanged) onCameraChange();
  }

  function readProfile(profile) {
    if (!profile || profile.schemaVersion !== 1 || !profile.settings || typeof profile.settings !== 'object' || Array.isArray(profile.settings)) {
      throw new Error('需要版本 1 的视觉参数 JSON 文件');
    }
    const next = { ...defaults };
    for (const [key, field] of fields) {
      if (!(key in profile.settings)) continue;
      const value = profile.settings[key];
      if (field.length === 2) {
        if (typeof value !== 'string' || !/^#[0-9a-f]{6}$/i.test(value)) throw new Error(`${field[1]}需要十六进制颜色`);
        next[key] = value;
      } else {
        if (typeof value !== 'number' || !Number.isFinite(value)) throw new Error(`${field[1]}需要有效数字`);
        next[key] = THREE.MathUtils.clamp(value, field[2], field[3]);
      }
    }
    Object.assign(settings, next);
    apply();
  }
  const profile = () => ({ schemaVersion: 1, settings: { ...settings } });

  const host = document.createElement('aside');
  host.id = 'visual-controls';
  host.innerHTML = `
    <button class="visual-toggle" type="button" aria-expanded="true" aria-controls="visual-panel">视觉调节 <span>F2</span></button>
    <section id="visual-panel" aria-label="视觉调节面板">
      <header><strong>画面调优</strong><span>实时预览</span></header>
      <p class="visual-hint">拖动参数即时生效；每行可单独恢复。F2 收起面板。</p>
      <div class="visual-fields"></div>
      <footer>
        ${vista ? '<button type="button" data-action="frame-vista">远景构图</button>' : ''}
        <button type="button" data-action="save">保存本地</button><button type="button" data-action="export">导出 JSON</button>
        <button type="button" data-action="import">导入 JSON</button><button type="button" data-action="reset">恢复默认</button>
        <input type="file" accept="application/json,.json" aria-label="导入视觉参数文件" hidden>
        <p class="visual-status" role="status" aria-live="polite">当前为原始画面参数。</p>
      </footer>
    </section>`;
  document.body.appendChild(host);
  const frameStats = document.createElement('div');
  frameStats.id = 'frame-stats';
  frameStats.setAttribute('aria-label', '实时帧率与平均帧间隔');
  frameStats.title = '按实际经过时间统计，约每秒更新；帧间隔包含浏览器调度与渲染等待。';
  frameStats.innerHTML = '<strong><span class="frame-fps">--</span> FPS</strong><span>平均帧间隔 <span class="frame-ms">--</span> ms</span>';
  document.body.appendChild(frameStats);
  const fpsValue = frameStats.querySelector('.frame-fps');
  const frameMsValue = frameStats.querySelector('.frame-ms');
  const updateFrameStats = (fps, frameMs) => {
    fpsValue.textContent = fps.toFixed(1);
    frameMsValue.textContent = frameMs.toFixed(1);
  };
  const status = host.querySelector('[role="status"]');
  const controls = new Map();
  for (const [title, open, items] of groups) {
    const section = document.createElement('details');
    section.open = open;
    const summary = document.createElement('summary');
    summary.textContent = title;
    section.appendChild(summary);
    for (const [key, label, min, max, step] of items) {
      const row = document.createElement('div'); row.className = 'visual-row';
      const heading = document.createElement('div'); heading.className = 'visual-caption';
      const caption = document.createElement('label'); caption.textContent = label; caption.htmlFor = `visual-${key}`;
      const reset = document.createElement('button'); reset.type = 'button'; reset.className = 'visual-reset';
      reset.textContent = '恢复'; reset.setAttribute('aria-label', `恢复${label}默认值`);
      reset.title = `恢复默认：${defaults[key]}`;
      reset.addEventListener('click', () => {
        settings[key] = defaults[key]; apply();
        for (const control of controls.get(key)) control.value = settings[key];
        status.textContent = `已恢复${label}默认值；其他参数保持当前值。点击保存本地以保留。`;
      });
      heading.append(caption, reset); row.appendChild(heading);
      const input = document.createElement('input'); input.id = `visual-${key}`;
      if (min === undefined) {
        input.type = 'color'; input.value = settings[key];
        row.appendChild(input);
        input.addEventListener('input', () => { settings[key] = input.value; apply(); status.textContent = '参数已修改，点击保存本地以保留。'; });
        controls.set(key, [input]);
      } else {
        input.type = 'range'; input.min = min; input.max = max; input.step = step; input.value = settings[key];
        const number = document.createElement('input'); number.type = 'number'; number.min = min; number.max = max; number.step = step;
        number.setAttribute('aria-label', label + '数值'); number.value = settings[key];
        row.append(input, number);
        const update = (source) => {
          if (source.value === '' || !Number.isFinite(source.valueAsNumber)) return;
          settings[key] = THREE.MathUtils.clamp(source.valueAsNumber, min, max);
          input.value = settings[key];
          if (source !== number) number.value = settings[key];
          apply(); status.textContent = '参数已修改，点击保存本地以保留。';
        };
        input.addEventListener('input', () => update(input));
        number.addEventListener('input', () => update(number));
        number.addEventListener('change', () => { number.value = settings[key]; });
        controls.set(key, [input, number]);
      }
      section.appendChild(row);
    }
    host.querySelector('.visual-fields').appendChild(section);
  }
  const refresh = () => { for (const [key, inputs] of controls) for (const input of inputs) input.value = settings[key]; };
  if (vista) host.querySelector('[data-action="frame-vista"]').addEventListener('click', () => {
    Object.assign(settings, { fov: 34, pitch: 18, yaw: 22, distance: 22 }); apply(); refresh();
    status.textContent = '已切换远景观赏镜头；光影与地表参数保持当前值。保存本地后保留。';
  });
  const panel = host.querySelector('#visual-panel');
  const toggle = host.querySelector('.visual-toggle');
  function togglePanel() { panel.hidden = !panel.hidden; toggle.setAttribute('aria-expanded', String(!panel.hidden)); }
  toggle.addEventListener('click', togglePanel);
  window.addEventListener('keydown', (event) => {
    if (event.code === 'F2' && !event.repeat) { event.preventDefault(); togglePanel(); }
  });
  host.querySelector('[data-action="save"]').addEventListener('click', () => {
    try { localStorage.setItem(storageKey, JSON.stringify(profile())); status.textContent = '已保存到当前浏览器；刷新后自动恢复。'; }
    catch { status.textContent = '浏览器无法保存，请导出 JSON 保留参数。'; }
  });
  host.querySelector('[data-action="reset"]').addEventListener('click', () => {
    Object.assign(settings, defaults); apply(); refresh();
    try { localStorage.removeItem(storageKey); status.textContent = '已恢复原始画面参数，并清除本地保存。'; }
    catch { status.textContent = '已恢复默认；本地保存无法清除。'; }
  });
  host.querySelector('[data-action="export"]').addEventListener('click', () => {
    const url = URL.createObjectURL(new Blob([JSON.stringify(profile(), null, 2)], { type: 'application/json' }));
    const link = document.createElement('a'); link.href = url; link.download = 'four-realms-visual-settings.json'; link.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
    status.textContent = '已导出当前参数；可以导入恢复或分享。';
  });
  const fileInput = host.querySelector('input[type="file"]');
  host.querySelector('[data-action="import"]').addEventListener('click', () => fileInput.click());
  fileInput.addEventListener('change', async () => {
    const file = fileInput.files[0];
    if (!file) return;
    try {
      readProfile(JSON.parse(await file.text())); refresh();
      status.textContent = '已导入并应用；点击保存本地以保留。';
    } catch (error) { status.textContent = '导入失败：' + error.message; }
    fileInput.value = '';
  });
  try {
    const saved = localStorage.getItem(storageKey);
    if (saved) { readProfile(JSON.parse(saved)); refresh(); status.textContent = '已恢复当前浏览器保存的参数。'; }
    else if (legacyStorageKey) {
      const legacy = JSON.parse(localStorage.getItem(legacyStorageKey) || 'null');
      if (legacy?.schemaVersion === 1 && legacy.settings) {
        readProfile({ schemaVersion: 1, settings: Object.fromEntries(preservedSettings.filter(key => key in legacy.settings).map(key => [key, legacy.settings[key]])) });
        refresh(); status.textContent = '已沿用保存的镜头和地表参数，应用新的光影默认值。';
      }
    }
  } catch { status.textContent = '本地参数无法读取，使用原始画面参数。'; }
  return { settings, defaults, apply, profile, readProfile, updateFrameStats };
}
