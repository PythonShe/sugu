import type { Locale } from './locales';
import en from './en';
import ja from './ja';
import zhHans from './zh-Hans';
import zhHant from './zh-Hant';

export type Messages = typeof en;

const messages: Record<Locale, Messages> = { en, ja, 'zh-Hans': zhHans, 'zh-Hant': zhHant };

export function messagesFor(locale: Locale): Messages {
  return messages[locale];
}
