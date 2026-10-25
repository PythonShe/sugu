import type { Messages } from './messages';

export default {
  description: 'Sugu 是一款免费的 Mac 输入法，用来输入中文和日文。',
  nav: { changelog: '更新记录', privacy: '隐私', licenses: '许可协议', language: '语言' },
  home: {
    pageTitle: 'Sugu – Mac 中文与日文输入法',
    title: '心中所想，即刻上屏。',
    lead: 'Sugu 是一款 Mac 中文与日文输入法。它把你想要的词放在首位，一个输入法即可切换中文、日文和英文，转换与学习都在你的 Mac 上完成。',
    download: '下载',
    requirement: '免费 · macOS 14 或更高版本',
    version: (version: string) => `版本 ${version}`,
    features: [
      { title: '一个输入法，三种语言', body: '用 Shift 键、大写锁定键，或“かな”“英数”键，在中文、日文和英文之间自如切换。' },
      { title: '中文，随心输入', body: '支持全拼、双拼和注音，可输入简体或繁体，还支持模糊音。' },
      { title: '日文，得心应手', body: '支持罗马字输入和假名输入、逐文节转换与实时转换、联想输入，还能自动纠正拼写错误。' },
      { title: '越用越懂你', body: '常用的词和短语会排在前面。学到的内容可以搜索、置顶和删除，也可以忘掉最近一小时学到的词。' },
      { title: '隐私，从设计开始', body: '无需账户，没有数据分析。你输入的内容不会离开你的 Mac；开启 Apple 的设备端模型后，它也只在你的 Mac 上运行。' },
      { title: '词库，一并带来', body: '可从 Google 日本語入力、Microsoft IME、ATOK、搜狗、RIME 和 macOS 文本替换中导入词条。' },
    ],
    install: {
      title: '安装',
      steps: [
        '打开下载的安装包，按照安装器的提示完成安装。',
        '在输入法菜单中选择 Sugu。如果没有看到，请前往“系统设置”›“键盘”›“输入法”›“编辑…”，在“简体中文”下添加；如果列表中还没有 Sugu，请注销后重新登录。',
        'Sugu 会自动检查更新，输入管理员密码即可安装。你也可以在设置中关闭检查。',
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
    updated: '2026年10月22日更新',
    sections: [
      {
        title: 'Sugu 保存的内容',
        body: [
          'Sugu 从你上屏的内容中学到的词和短语，以及你添加的词，都保存在你 Mac 上的数据库中。你可以搜索和删除它们、忘记过去一小时学到的内容、在某些应用中停止学习，或关闭学习。',
          'Sugu 会读取输入框中已有的文字来为候选词排序，但从不保存这些文字。',
          '如果你开启 Apple 的语言模型（macOS 27 或更高版本）来翻译或改写文字，它在你的 Mac 上运行，不发送任何内容。',
          '如果你选择了一个文件夹在多台 Mac 之间同步学到的词，Sugu 会把它们写入该文件夹，由同步该文件夹的服务传送。',
        ],
      },
      {
        title: 'Sugu 发送的内容',
        body: ['Sugu 没有遥测、崩溃报告、数据分析，也没有账户。它只在以下情况联网：'],
        list: [
          '检查更新（可以关闭）：连接 sugu.zheng-she.com 检查 Sugu；打开设置时，每天最多一次连接 GitHub，检查你已下载的雾凇拼音词库和语法模型是否有新版本。不发送有关你 Mac 的信息，发往 sugu.zheng-she.com 的请求中只包含 Sugu 的版本号。',
          '你主动发起的下载：可选的雾凇拼音词库来自 GitHub，语法模型来自 GitHub 或 sugu.zheng-she.com，Zenzai 模型来自 Hugging Face。',
        ],
      },
      {
        title: '本网站',
        body: ['本网站不使用 Cookie、数据分析或第三方脚本。网站由 Cloudflare 托管，Cloudflare 会处理访问请求以传送网页。'],
      },
    ],
  },
  licenses: {
    title: '许可协议',
    sugu: 'Sugu 是自由软件，以 GNU 通用公共许可证第 3 版或更新版本授权。',
    source: '源代码',
    license: 'GNU 通用公共许可证',
    notices: '第三方声明',
  },
  footer: { copyright: '© 2026 Zheng She' },
} satisfies Messages;
