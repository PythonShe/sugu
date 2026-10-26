import type { APIRoute } from 'astro';
import { locales } from '../i18n/locales';
import { pagePath } from '../lib/paths';

/** Every page in every language, each listing its translations. */
const pages = ['', 'changelog/', 'privacy/', 'licenses/'];

export const GET: APIRoute = ({ site }) => {
  const url = (locale: (typeof locales)[number], page: string) => new URL(pagePath(locale, page), site).href;
  const entries = pages.flatMap((page) =>
    locales.map((locale) => {
      const alternates = locales
        .map((other) => `    <xhtml:link rel="alternate" hreflang="${other}" href="${url(other, page)}"/>`)
        .concat(`    <xhtml:link rel="alternate" hreflang="x-default" href="${url('en', page)}"/>`)
        .join('\n');
      return `  <url>\n    <loc>${url(locale, page)}</loc>\n${alternates}\n  </url>`;
    }),
  );
  const body = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">
${entries.join('\n')}
</urlset>
`;
  return new Response(body, { headers: { 'Content-Type': 'application/xml; charset=utf-8' } });
};
