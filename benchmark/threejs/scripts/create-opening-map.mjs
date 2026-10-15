import fs from 'node:fs';
import { createOpeningLayout } from '../src/opening-layout.js';

const base = JSON.parse(fs.readFileSync(new URL('../public/layout/scene_layout.json', import.meta.url), 'utf8'));
const layout = createOpeningLayout(base);
fs.writeFileSync(new URL('../public/layout/opening_layout.json', import.meta.url), JSON.stringify(layout, null, 2) + '\n');
console.log(`Created opening environment: ${layout.terrain.size.join(' × ')} cells`);
