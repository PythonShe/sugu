import type { Messages } from './messages';

export default {
  description: 'Sugu 是一款免费的 Mac 输入法，用来输入中文和日文。',
  nav: { changelog: '更新记录', privacy: '隐私', licenses: '许可', language: '语言' },
  home: {
    title: 'Mac 上的中文与日文输入法。',
    lead: 'Sugu 在一个输入源里输入中文、日文和英文，把你想要的词放在第一位。转换和学习都在你的 Mac 上完成。',
    download: '下载',
    requirement: '免费 · macOS 14 或更高版本',
    version: (version: string) => `版本 ${version}`,
    features: [
      { title: '一个输入源', body: '用 Shift、Caps Lock 或かな、英数键在中文、日文和英文之间切换。' },
      { title: '中文', body: '全拼、双拼和注音，简体或繁体，支持模糊音。' },
      { title: '日文', body: '罗马字或假名输入，逐文节转换或实时转换，联想输入，容错输入。' },
      { title: '学习你的写法', body: '你常用的词和短语排在前面。学到的内容可以搜索、置顶和删除，也可以忘记最近一小时。' },
      { title: '留在你的 Mac 上', body: '无需账户，没有数据分析。除非你开启私有云计算，Sugu 不会发送你输入的任何内容。' },
      { title: '带上你的词库', body: '可以导入 Google 日本語入力、Microsoft IME、ATOK、搜狗、RIME 和 macOS 文本替换中的词。' },
    ],
    install: {
      title: '安装',
      steps: [
        '打开下载的安装包，按照安装器的提示操作。',
        '输入法菜单中会加入 Sugu。如果没有，请在“系统设置”›“键盘”›“输入法”›“编辑”中，从“简体中文”下添加；如果列表中还没有它，请注销后重新登录。',
        'Sugu 会自动检查更新，你可以在它的设置中关闭。',
      ],
    },
  },
  changelog: {
    title: '更新记录',
    empty: '还没有发布版本。',
    download: '下载',
  },
  privacy: {
    title: '隐私',
    updated: '2026 年 10 月 20 日更新',
    sections: [
      {
        title: 'Sugu 保存的内容',
        body: [
          'Sugu 从你上屏的内容中学到的词和短语，以及你添加的词，都保存在你 Mac 上的数据库中。你可以搜索和删除它们、忘记最近一小时、在某些应用中停止学习，或关闭学习。',
          'Sugu 为排列候选而读取的输入框中已有的文字，从不保存。',
          '如果你选择了一个文件夹在多台 Mac 之间同步学到的词，Sugu 会把它们写入该文件夹，由同步该文件夹的服务传送。',
        ],
      },
      {
        title: 'Sugu 发送的内容',
        body: ['Sugu 没有遥测、崩溃报告、数据分析，也没有账户。它只在以下情况联网：'],
        list: [
          '检查更新，连接 sugu.zheng-she.com，可以关闭。不发送关于你 Mac 的信息，请求中只包含 Sugu 的版本。',
          '你开始的下载：可选的 rime-ice 词库和语法模型来自 GitHub，Zenzai 模型来自 Hugging Face。',
          '私有云计算，仅在你选择时：正在转换的文字、光标前的文字或你选中的文字会发送到 Apple 的私有云计算，用于转换、翻译或改写。选择“在此 Mac 上”时，Apple 的模型在你的 Mac 上运行，不发送任何内容。',
        ],
      },
      {
        title: '本网站',
        body: ['本网站不使用 Cookie、数据分析或第三方脚本。网站由 Cloudflare 提供，Cloudflare 为传送网页而处理请求。'],
      },
    ],
  },
  licenses: {
    title: '许可',
    sugu: 'Sugu 是免费的专有软件。',
    license: 'Sugu 许可',
    notices: '第三方声明',
  },
  footer: { copyright: '© 2026 Zheng She' },
} satisfies Messages;
