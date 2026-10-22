import { defineConfig } from 'vite';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.dirname(fileURLToPath(import.meta.url));

// Small dev/preview endpoint so the page itself can save screenshots into ./screenshots
function screenshotSaver() {
  const handler = (req, res, next) => {
    if (req.method !== 'POST' || !req.url.startsWith('/__save-shot')) return next();
    const name = new URL(req.url, 'http://x').searchParams.get('name') || 'shot.png';
    const safe = path.basename(name).replace(/[^\w.\-]/g, '_');
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => {
      const body = Buffer.concat(chunks).toString();
      const b64 = body.replace(/^data:image\/png;base64,/, '');
      fs.mkdirSync(path.join(root, 'screenshots'), { recursive: true });
      fs.writeFileSync(path.join(root, 'screenshots', safe), Buffer.from(b64, 'base64'));
      res.statusCode = 200;
      res.end('ok');
    });
  };
  return {
    name: 'screenshot-saver',
    configureServer(server) { server.middlewares.use(handler); },
    configurePreviewServer(server) { server.middlewares.use(handler); },
  };
}

export default defineConfig({
  publicDir: path.join(root, 'public'),
  server: { port: 5199, strictPort: true },
  preview: { port: 5198, strictPort: true },
  plugins: [screenshotSaver()],
  build: { chunkSizeWarningLimit: 2000 },
});
