// Temporary synthesized feedback for M1 timing; replace with tracked Meowa assets later.
export function createFestivalAudio() {
  let context = null, musicGain = null, enabled = true;
  async function start() {
    if (!context) {
      context = new AudioContext();
      musicGain = context.createGain(); musicGain.gain.value = 0;
      musicGain.connect(context.destination);
      for (const frequency of [196, 293.66, 392]) {
        const tone = context.createOscillator(); tone.type = 'sine'; tone.frequency.value = frequency;
        tone.connect(musicGain); tone.start();
      }
      const buffer = context.createBuffer(1, context.sampleRate * 2, context.sampleRate);
      const data = buffer.getChannelData(0);
      for (let i = 0; i < data.length; i++) data[i] = Math.random() * 2 - 1;
      const source = context.createBufferSource(); source.buffer = buffer; source.loop = true;
      const filter = context.createBiquadFilter(); filter.type = 'lowpass'; filter.frequency.value = 450;
      const gain = context.createGain(); gain.gain.value = 0.013;
      source.connect(filter); filter.connect(gain); gain.connect(context.destination); source.start();
    }
    if (enabled) await context.resume();
  }
  function state(phase) {
    if (!context) return;
    const time = context.currentTime;
    musicGain.gain.cancelScheduledValues(time);
    musicGain.gain.setTargetAtTime(phase === 'blackout' ? 0 : 0.012, time, 0.2);
  }
  function bell(frequency = 523.25) {
    if (!context || context.state !== 'running') return;
    for (const [multiple, volume] of [[1, 0.08], [2.7, 0.025]]) {
      const tone = context.createOscillator(); tone.frequency.value = frequency * multiple;
      const gain = context.createGain(); const time = context.currentTime;
      gain.gain.setValueAtTime(volume, time); gain.gain.exponentialRampToValueAtTime(0.0001, time + 1.8);
      tone.connect(gain); gain.connect(context.destination); tone.start(); tone.stop(time + 1.8);
      tone.onended = () => { tone.disconnect(); gain.disconnect(); };
    }
  }
  async function toggle() {
    enabled = !enabled;
    if (context) { if (enabled) await context.resume(); else await context.suspend(); }
    return enabled;
  }
  return { start, state, bell, toggle };
}
