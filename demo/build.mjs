import { spawnSync } from 'node:child_process';
import { copyFile, mkdir } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const output = join(root, 'demo', 'dist');
const moon = process.platform === 'win32' ? 'moon.exe' : 'moon';
const build = spawnSync(moon, ['build', '--target', 'js', 'demo/bridge'], {
  cwd: root,
  stdio: 'inherit',
});
if (build.error) throw build.error;
if (build.status !== 0) process.exit(build.status ?? 1);

await mkdir(join(output, 'data'), { recursive: true });
for (const name of ['index.html', 'styles.css', 'app.js']) {
  await copyFile(join(root, 'demo', 'web', name), join(output, name));
}
await copyFile(
  join(root, '_build', 'js', 'debug', 'build', 'demo', 'bridge', 'bridge.js'),
  join(output, 'core.js'),
);
for (const name of ['student-plan.v1.json', 'project-plan.v1.json']) {
  await copyFile(join(root, 'examples', name), join(output, 'data', name));
}
console.log(`Demo built at ${output}`);
