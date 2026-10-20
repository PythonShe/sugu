export const locales = ['en', 'ja', 'zh-Hans', 'zh-Hant'] as const;
export type Locale = (typeof locales)[number];
export const defaultLocale: Locale = 'en';

/** Each language in its own name, for the language links. */
export const languageNames: Record<Locale, string> = {
  en: 'English',
  ja: '日本語',
  'zh-Hans': '简体中文',
  'zh-Hant': '繁體中文',
};
