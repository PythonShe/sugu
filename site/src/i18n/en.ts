export default {
  description: 'Sugu is a free input method for typing Chinese and Japanese on the Mac.',
  nav: { changelog: 'Changelog', privacy: 'Privacy', licenses: 'Licenses', language: 'Language' },
  home: {
    title: 'Chinese and Japanese input for the Mac.',
    lead: 'Sugu puts the word you mean first, in one input source for Chinese, Japanese and English. Conversion and learning happen on your Mac.',
    download: 'Download',
    requirement: 'Free · macOS 14 or later',
    version: (version: string) => `Version ${version}`,
    features: [
      { title: 'One input source', body: 'Switch between Chinese, Japanese and English with Shift, Caps Lock or the かな and 英数 keys.' },
      { title: 'Chinese', body: 'Full pinyin, shuangpin and Zhuyin, in Simplified or Traditional characters, with fuzzy pinyin.' },
      { title: 'Japanese', body: 'Romaji or kana input, clause-by-clause or live conversion, predictions and typo tolerance.' },
      { title: 'Learns how you write', body: 'Your words and phrases come first. Search, pin and delete what Sugu has learned, or forget the last hour.' },
      { title: 'Stays on your Mac', body: 'No account, no analytics. Sugu sends nothing you type unless you turn on Private Cloud Compute.' },
      { title: 'Brings your dictionaries', body: 'Import words from Google Japanese Input, Microsoft IME, ATOK, Sogou, RIME and macOS text replacements.' },
    ],
    install: {
      title: 'Install',
      steps: [
        'Open the downloaded package and follow the installer.',
        'Sugu is selected in the input menu. It is listed under Chinese, Simplified in System Settings › Keyboard › Input Sources.',
        'Sugu checks for updates itself; you can turn this off in its settings.',
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
    updated: 'Updated October 20, 2026',
    sections: [
      {
        title: 'What Sugu keeps',
        body: [
          'The words and phrases Sugu learns from what you commit, and the words you add, stay in a database on your Mac. You can search and delete them, forget the last hour, stop learning in some apps, or turn learning off.',
          'Text already in the field, which Sugu reads to rank candidates, is never stored.',
          'If you choose a folder to sync learned words between Macs, Sugu writes them there; whatever syncs that folder carries them.',
        ],
      },
      {
        title: 'What Sugu sends',
        body: [
          'Sugu has no telemetry, crash reporting or analytics, and no account. It connects only for:',
        ],
        list: [
          'Update checks, to sugu.zheng-she.com, which you can turn off. They send nothing about your Mac; the request names Sugu’s version.',
          'Downloads you start: the optional rime-ice dictionary and grammar model from GitHub, and the Zenzai model from Hugging Face.',
          'Private Cloud Compute, only if you choose it: the text you are converting, the text before the cursor, or the text you selected goes to Apple’s Private Cloud Compute to be converted, translated or rewritten. On This Mac, Apple’s model runs on your Mac and sends nothing.',
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
    sugu: 'Sugu is proprietary software, free of charge.',
    license: 'Sugu License',
    notices: 'Third-party notices',
  },
  footer: { copyright: '© 2026 Zheng She' },
};
