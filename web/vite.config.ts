import {defineConfig} from 'vite';
import react from '@vitejs/plugin-react';

// Deployed to Vercel at the domain root, so no `base` path is needed.
export default defineConfig({
  plugins: [react()],
  build: {chunkSizeWarningLimit: 1200},
});
