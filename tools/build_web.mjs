// No npm dependencies: node tools/build_web.mjs [--flutter=D:/flutter/bin/flutter.bat] [Flutter flags]
import { createHash } from 'node:crypto';
import { readFile, readdir, writeFile } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const project = fileURLToPath(new URL('../', import.meta.url));
const args = process.argv.slice(2);
const flutterFlag = args.find(arg => arg.startsWith('--flutter='));
const flutter = flutterFlag?.slice('--flutter='.length) || process.env.FLUTTER_BIN || 'flutter';
const flutterArgs = args.filter(arg => arg !== flutterFlag && arg !== '--prepare-only');
if (!args.includes('--prepare-only')) {
  const result = spawnSync(flutter, ['build', 'web', '--release', ...flutterArgs], {
    cwd: project, stdio: 'inherit', shell: process.platform === 'win32',
  });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}
const output = path.join(project, 'build/web');
async function listFiles(dir, prefix = '') {
  const result = [];
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const relative = `${prefix}${entry.name}`;
    if (entry.isDirectory()) result.push(...await listFiles(path.join(dir, entry.name), `${relative}/`));
    else result.push(relative);
  }
  return result;
}
// canvaskit/ is skipped: the app loads the one renderer each browser needs from
// Flutter's versioned CDN, and the worker caches it as used. Precaching all six
// local variants made the first visit download ~40 MB.
const files = (await listFiles(output)).filter(file =>
  !file.endsWith('.map') && !file.endsWith('.symbols') && !file.startsWith('canvaskit/')
  && !['splitrip_service_worker.js', 'flutter_service_worker.js'].includes(file)
).sort();
const template = await readFile(path.join(project, 'web/splitrip_service_worker.js'), 'utf8');
const hash = createHash('sha256').update(template);
for (const file of files) hash.update(file).update(await readFile(path.join(output, file)));
const version = hash.digest('hex').slice(0, 20);
await writeFile(path.join(output, 'splitrip_service_worker.js'), template
  .replace('__SPLITRIP_VERSION__', version)
  .replace('__SPLITRIP_FILES__', JSON.stringify(files)));
console.log(`Offline shell ${version}: ${files.length} files. Close all app tabs to activate an update.`);
