import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
fs.mkdirSync(path.join(root, 'public/opening'), { recursive: true });
const catalog = {}, assets = [];
for (const [name, expected, call] of [
  ['stone', [64, 64], '1-制作广场石板地表/CALL002-修正铺装'],
  ['details', [1024, 768], '2-制作石板细节/CALL001-生成'],
  ['vista', [1024, 768], '3-制作宗门远景/CALL001-生成'],
]) {
  const source = `assets/meowa/${name}/${name}.png`;
  const file = `opening/${name}.png`;
  const bytes = fs.readFileSync(path.join(root, source));
  const dimensions = [bytes.readUInt32BE(16), bytes.readUInt32BE(20)];
  if (dimensions.some((value, index) => value !== expected[index])) throw new Error(`Unexpected ${name} dimensions`);
  fs.writeFileSync(path.join(root, 'public', file), bytes);
  catalog[name] = { file, width: dimensions[0], height: dimensions[1] };
  assets.push({ name, source, file, dimensions, meowaCall: [call], sha256: crypto.createHash('sha256').update(bytes).digest('hex') });
}
fs.writeFileSync(path.join(root, 'public/opening/assets.json'), JSON.stringify(catalog, null, 2) + '\n');
fs.writeFileSync(path.join(root, 'public/opening/provenance.json'), JSON.stringify({
  note: 'Original Meowa image bytes, unchanged.',
  assets,
}, null, 2) + '\n');
console.log('Prepared stone.png, details.png and vista.png (native Meowa files)');
