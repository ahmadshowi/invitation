// The site lives in web/ (index.html + tamu.html); package.json stays at the repo root.
import { defineConfig, loadEnv } from 'vite';
import { resolve } from 'node:path';
import { cpSync, existsSync, writeFileSync } from 'node:fs';

const root = resolve(import.meta.dirname, 'web');
const outDir = resolve(import.meta.dirname, 'dist');

// index.html loads these by plain string paths at runtime (GLB models, video, photos,
// music, config.js), so Vite never sees them. Copy them into the build untouched.
function copyRuntimeFiles(env) {
  return {
    name: 'copy-runtime-files',
    apply: 'build',
    closeBundle() {
      cpSync(resolve(root, 'assets'), resolve(outDir, 'assets'), { recursive: true, filter: src => !src.endsWith('.gitkeep') });
      // Supabase settings: env vars (e.g. set in Vercel) win over the values in web/config.js
      if (env.VITE_SUPABASE_URL && env.VITE_SUPABASE_ANON_KEY) {
        const cfg = { supabaseUrl: env.VITE_SUPABASE_URL, supabaseAnonKey: env.VITE_SUPABASE_ANON_KEY, eventISO: env.VITE_EVENT_ISO || '2026-12-12T08:00:00+07:00' };
        writeFileSync(resolve(outDir, 'config.js'), `window.WEDDING_CONFIG = ${JSON.stringify(cfg, null, 2)};\n`);
      } else if (existsSync(resolve(root, 'config.js'))) {
        cpSync(resolve(root, 'config.js'), resolve(outDir, 'config.js'));
      }
    },
  };
}

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, import.meta.dirname, 'VITE_');
  return {
    root,
    envDir: import.meta.dirname,
    publicDir: false,
    server: { host: '0.0.0.0' },
    build: {
      outDir,
      emptyOutDir: true,
      assetsDir: 'bundle', // keep Vite's hashed files apart from web/assets
      chunkSizeWarningLimit: 1500, // three.js is large on purpose
      rollupOptions: { input: { main: resolve(root, 'index.html'), tamu: resolve(root, 'tamu.html') } },
    },
    plugins: [copyRuntimeFiles(env)],
  };
});
