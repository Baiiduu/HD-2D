import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const option = (name, fallback) => {
  const at = process.argv.indexOf(name);
  return path.resolve(at < 0 ? fallback : process.argv[at + 1]);
};
const shared = option('--shared-dir', fs.existsSync('D:/Project/godot/games/Asserts')
  ? 'D:/Project/godot/games/Asserts' : path.resolve(root, '../godot/assets'));
const demo = option('--demo-dir', path.resolve(root, '../../assets'));
const entries = [];
const hash = (bytes) => crypto.createHash('sha256').update(bytes).digest('hex');
function copy(source, destination, role, origin) {
  const bytes = fs.readFileSync(source);
  const target = path.join(root, destination);
  if (fs.existsSync(target) && hash(fs.readFileSync(target)) !== hash(bytes)) {
    throw new Error(`Existing asset differs; preserve and review it before importing: ${target}`);
  }
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, bytes);
  entries.push({ file: destination.replaceAll('\\', '/'), source, role, origin, bytes: bytes.length,
    sha256: hash(bytes), dimensions: source.endsWith('.png') ? [bytes.readUInt32BE(16), bytes.readUInt32BE(20)] : undefined });
}
function walk(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) =>
    entry.isDirectory() ? walk(path.join(dir, entry.name)) : [path.join(dir, entry.name)]);
}
for (const folder of ['characters', 'textures', 'tilesets', 'layout']) {
  for (const source of walk(path.join(shared, folder)).filter((f) => /\.(png|json|txt)$/.test(f))) {
    copy(source, path.join('public', folder, path.relative(path.join(shared, folder), source)), 'existing benchmark asset', 'existing shared pack');
  }
}
copy(path.join(shared, 'README.md'), 'assets/shared-pack-readme.md', 'source documentation', 'existing shared pack');
for (const source of walk(path.join(demo, 'props')).filter((f) => /\.png$/.test(f))) {
  copy(source, path.join('public/props', path.basename(source)), 'prop component; validate style before use', 'existing extracted prop sheet');
}
copy(path.join(demo, 'props/final_outputs.json'), 'assets/prop-components.json', 'component bounding boxes', 'existing extraction manifest');
for (const source of walk(path.join(demo, 'ground/references')).filter((f) => /\.png$/.test(f))) {
  if (entries.some((e) => e.sha256 === hash(fs.readFileSync(source)))) continue;
  copy(source, path.join('public/textures/references', path.basename(source)), 'supplementary texture reference', 'existing reference; not a newly generated asset');
}
for (const source of walk(path.join(demo, 'meowa')).filter((f) => /sprite_pack_preview\.png$|result_images_0_url\.png$/.test(f))) {
  copy(source, 'assets/source-packs/' + (/sprite_pack/.test(source) ? 'characters-preview.png' : 'realm-props.png'), 'source sheet; not loaded by runtime', 'existing Meowa output');
}
const catalog = { schemaVersion: 1, note: 'Local copies of pre-existing files. No generation was performed. Source licenses are not inferred.', entries };
fs.mkdirSync(path.join(root, 'assets'), { recursive: true });
fs.writeFileSync(path.join(root, 'assets/asset-catalog.json'), JSON.stringify(catalog, null, 2) + '\n');
console.log(`Imported and hash-verified ${entries.length} files (${entries.filter((e) => e.dimensions).length} images) into ${root}`);
