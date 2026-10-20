import { locales } from '../i18n/locales';

/** One page per language. */
export function localePaths() {
  return locales.map((locale) => ({ params: { locale } }));
}
