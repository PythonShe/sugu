import type { Locale } from '../i18n/locales';

/** Where scripts/publish-release.sh puts releases; SUGU_UPDATES_URL overrides it for testing. */
const updates = (process.env.SUGU_UPDATES_URL ?? 'https://sugu.zheng-she.com').replace(/\/$/, '');
/** Set by the deploy workflow: a build that cannot read the releases fails rather than deploy an empty changelog. */
const required = process.env.SUGU_REQUIRE_RELEASES === '1';

export interface Release {
  version: string;
  build: number;
  date: string;
  minimumSystemVersion: string;
  /** The notes as Markdown, by language. */
  notes: Partial<Record<Locale, string>>;
}

let cached: Promise<Release[]> | undefined;

/** Every release, newest first; none when they cannot be read outside a deploy. */
export function releases(): Promise<Release[]> {
  cached ??= load();
  return cached;
}

async function load(): Promise<Release[]> {
  const response = await fetch(`${updates}/releases.json`).catch(() => undefined);
  if (!response?.ok) {
    const reason = `releases.json: ${response?.status ?? 'unreachable'}`;
    if (required) throw new Error(reason);
    console.warn(`${reason}; building without releases`);
    return [];
  }
  const list = (await response.json()) as Omit<Release, 'notes'>[];
  return Promise.all(
    list
      .filter((release) => /^\d+\.\d+\.\d+$/.test(release.version))
      .map(async (release) => {
        const notes: Release['notes'] = {};
        for (const locale of ['en', 'ja', 'zh-Hans', 'zh-Hant'] as const) {
          const url = `${updates}/releases/${release.version}/notes/${locale}.md`;
          const notesResponse = await fetch(url).catch(() => undefined);
          if (notesResponse?.ok) notes[locale] = await notesResponse.text();
          else if (required && notesResponse?.status !== 404) throw new Error(`${url}: ${notesResponse?.status ?? 'unreachable'}`);
        }
        return { ...release, notes };
      }),
  );
}
