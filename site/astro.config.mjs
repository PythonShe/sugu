// @ts-check
import { defineConfig } from 'astro/config';
import { locales, defaultLocale } from './src/i18n/locales.ts';

// Static pages for Cloudflare Pages; functions/ serves the update feed.
export default defineConfig({
  site: 'https://sugu.zheng-she.com',
  trailingSlash: 'always',
  i18n: {
    locales: [...locales],
    defaultLocale,
    routing: { prefixDefaultLocale: true, redirectToDefaultLocale: false },
  },
  vite: {
    // The icon and the third-party notices come from the app's sources.
    server: { fs: { allow: ['..'] } },
  },
});
