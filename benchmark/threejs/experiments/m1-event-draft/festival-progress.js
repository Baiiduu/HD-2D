// Only real player interactions advance the milestone. Repeated actions are harmless.
export function createFestivalProgress() {
  return {
    phase: 'festival', stone: false,
    interact(id) {
      if (id === 'river' && this.phase === 'festival') { this.phase = 'blackout'; return 'blackout'; }
      if (id === 'stone' && this.phase === 'blackout' && !this.stone) { this.stone = true; return 'stone'; }
      if (id === 'lamp' && this.phase === 'blackout' && this.stone) {
        this.stone = false; this.phase = 'restored'; return 'restored';
      }
      return null;
    },
  };
}
