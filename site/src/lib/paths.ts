import { defaultLocale, locales, type Locale } from '../i18n/locales';

/** A page in a language. The English home page is the site's root, /. */
export function pagePath(locale: Locale, page = '') {
  return locale === defaultLocale && page === '' ? '/' : `/${locale}/${page}`;
}

/** One page per language. */
export function localePaths() {
  return locales.map((locale) => ({ params: { locale } }));
}

/** One home page per language but English, which is at /. */
export function translatedPaths() {
  return localePaths().filter(({ params }) => params.locale !== defaultLocale);
}
