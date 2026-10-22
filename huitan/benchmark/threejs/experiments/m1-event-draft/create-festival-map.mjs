import fs from 'node:fs';
import { createFestivalLayout } from './festival-layout.js';

const source = new URL('../../public/layout/scene_layout.json', import.meta.url);
const target = new URL('./festival_m1.json', import.meta.url);
const layout = createFestivalLayout(JSON.parse(fs.readFileSync(source, 'utf8')));
fs.writeFileSync(target, JSON.stringify(layout, null, 2) + '\n');
console.log(`Created ${layout.terrain.size.join(' × ')} cell M1 map: ${target.pathname}`);
