import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'node:path';

// JuraDrop bootstrap — Vite + React + Tauri 2.x
// Port 1420 is the Tauri convention. strictPort prevents Vite from drifting
// to a different port if 1420 is busy (per research.md R-004).
export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  clearScreen: false,
  server: {
    port: 1420,
    strictPort: true,
  },
  build: {
    target: 'es2022',
  },
});
