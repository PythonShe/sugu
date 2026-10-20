import type { Locale } from '../i18n/locales';

/** Where scripts/publish-release.sh puts releases; SUGU_UPDATES_URL overrides it for testing. */
const updates = (process.env.SUGU_UPDATES_URL ?? 'https://sugu.zheng-she.com').replace(/\/$/, '');

export interface Release {
  version: string;
  build: number;
  date: string;
  minimumSystemVersion: string;
  /** The notes as Markdown, by language. */
  notes: Partial<Record<Locale, string>>;
}

let cached: Promise<Release[]> | undefined;

/** Every release, newest first; none when there are none yet or they cannot be read. */
export function releases(): Promise<Release[]> {
  cached ??= load();
  return cached;
}

async function load(): Promise<Release[]> {
  const response = await fetch(`${updates}/releases.json`).catch(() => undefined);
  if (!response?.ok) {
    console.warn(`releases.json: ${response?.status ?? 'unreachable'}; building without releases`);
    return [];
  }
  const list = (await response.json()) as Omit<Release, 'notes'>[];
  return Promise.all(
    list
      .filter((release) => /^\d+\.\d+\.\d+$/.test(release.version))
      .map(async (release) => {
        const notes: Release['notes'] = {};
        for (const locale of ['en', 'ja', 'zh-Hans', 'zh-Hant'] as const) {
          const notesResponse = await fetch(`${updates}/releases/${release.version}/notes/${locale}.md`).catch(() => undefined);
          if (notesResponse?.ok) notes[locale] = await notesResponse.text();
        }
        return { ...release, notes };
      }),
  );
}
