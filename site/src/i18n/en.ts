export default {
  description: 'Sugu is a free input method for typing Chinese and Japanese on the Mac.',
  nav: { changelog: 'Changelog', privacy: 'Privacy', licenses: 'Licenses', language: 'Language' },
  home: {
    pageTitle: 'Sugu – Chinese and Japanese Input for Mac',
    title: 'The right word, right away.',
    lead: 'Sugu is a Chinese and Japanese input method for the Mac. It puts the word you mean first, moves between Chinese, Japanese and English in a single input source, and does all its work on your Mac.',
    download: 'Download',
    requirement: 'Free · macOS 14 or later',
    version: (version: string) => `Version ${version}`,
    features: [
      { title: 'One input source. Three languages.', body: 'Move between Chinese, Japanese and English with Shift, Caps Lock, or the かな and 英数 keys.' },
      { title: 'Chinese, your way', body: 'Full pinyin, shuangpin or Zhuyin, in Simplified or Traditional characters, with fuzzy pinyin when you need it.' },
      { title: 'Japanese, your way', body: 'Romaji or kana input, clause-by-clause or live conversion, with predictions that keep up and forgive typos.' },
      { title: 'Learns how you write', body: 'The words and phrases you use most come first. Search, pin or remove anything Sugu has learned, or forget the last hour.' },
      { title: 'Private by design', body: 'No account. No analytics. What you type never leaves your Mac, and Apple’s on-device model, if you turn it on, runs there too.' },
      { title: 'Bring your own words', body: 'Import your dictionary from Google Japanese Input, Microsoft IME, ATOK, Sogou, RIME or macOS text replacements.' },
    ],
    install: {
      title: 'Install',
      steps: [
        'Open the downloaded package and follow the installer.',
        'Choose Sugu from the Input menu. If it isn’t there, add it in System Settings › Keyboard › Input Sources › Edit, under Chinese, Simplified; if it isn’t listed yet, log out and back in.',
        'Sugu checks for updates itself and installs them with an administrator’s password. You can turn the checks off in its settings.',
      ],
    },
  },
  changelog: {
    title: 'Changelog',
    empty: 'No releases yet.',
    download: 'Download',
  },
  privacy: {
    title: 'Privacy',
    updated: 'Updated October 22, 2026',
    sections: [
      {
        title: 'What Sugu keeps',
        body: [
          'The words and phrases Sugu learns from what you commit, and the words you add, stay in a database on your Mac. You can search and delete them, forget the last hour, stop learning in some apps, or turn learning off.',
          'Text already in the field, which Sugu reads to rank candidates, is never stored.',
          'Apple’s language model (macOS 27 or later), if you turn it on to translate or rewrite text, runs on your Mac and sends nothing.',
          'If you choose a folder to sync learned words between Macs, Sugu writes them there; whatever syncs that folder carries them.',
        ],
      },
      {
        title: 'What Sugu sends',
        body: [
          'Sugu has no telemetry, crash reporting or analytics, and no account. It connects only for:',
        ],
        list: [
          'Update checks, which you can turn off: to sugu.zheng-she.com for Sugu, and, when you open Settings, at most once a day to GitHub for newer releases of the rime-ice dictionary and grammar model you downloaded. They send nothing about your Mac; the request to sugu.zheng-she.com names Sugu’s version.',
          'Downloads you start: the optional rime-ice dictionary from GitHub, the grammar model from GitHub or sugu.zheng-she.com, and the Zenzai model from Hugging Face.',
        ],
      },
      {
        title: 'This website',
        body: [
          'This website uses no cookies, no analytics and no third-party scripts. It is served by Cloudflare, which handles requests to deliver it.',
        ],
      },
    ],
  },
  licenses: {
    title: 'Licenses',
    sugu: 'Sugu is free software under the GNU General Public License, version 3 or later.',
    source: 'Source code',
    license: 'GNU General Public License',
    notices: 'Third-party notices',
  },
  footer: { copyright: '© 2026 Zheng She' },
};
