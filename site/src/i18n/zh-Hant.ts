import type { Messages } from './messages';

export default {
  description: 'Sugu 是免費、開源的 Mac 輸入法，可輸入中文和日文。',
  nav: { changelog: '更新紀錄', privacy: '隱私權', licenses: '授權', language: '語言' },
  home: {
    pageTitle: 'Sugu – Mac 中文與日文輸入法',
    title: '心中所想，即刻呈現。',
    lead: 'Sugu 是一款 Mac 中文與日文輸入法。它把你想要的字詞放在第一位，用一個輸入法就能切換中文、日文和英文，轉換與學習都在你的 Mac 上完成。',
    download: '下載',
    requirement: '免費開源 · macOS 14 或以上版本',
    version: (version: string) => `版本 ${version}`,
    features: [
      { title: '一個輸入法，三種語言', body: '使用 Shift、大寫鎖定鍵，或「かな」與「英数」鍵，在中文、日文和英文之間自在切換。' },
      { title: '中文，隨心輸入', body: '支援注音、全拼與雙拼，可輸入繁體或簡體中文，也支援模糊音。' },
      { title: '日文，得心應手', body: '支援羅馬字與假名輸入、逐文節轉換與即時轉換、輸入預測，還能自動修正拼寫錯誤。' },
      { title: '越用越懂你', body: '常用的字詞與片語會排在前面。學到的內容可以搜尋、釘選與刪除，也可以忘掉最近一小時學到的內容。' },
      { title: '隱私，從設計開始', body: '不需要帳號，也不收集分析資料。你輸入的內容不會離開你的 Mac；開啟 Apple 的裝置端模型後，它也只在你的 Mac 上執行。' },
      { title: '詞庫，一併帶來', body: '可從 Google 日本語入力、Microsoft IME、ATOK、搜狗、RIME 與 macOS 文字替代中匯入字詞。' },
    ],
    install: {
      title: '安裝',
      steps: [
        '打開下載的安裝檔，依照安裝程式的指示完成安裝。',
        '在輸入法選單中選擇 Sugu。若沒有看到，請在「系統設定」›「鍵盤」›「輸入方式」›「編輯」中，從「簡體中文」下加入；若列表中還沒有 Sugu，請登出後再重新登入。',
        'Sugu 會自動檢查更新，輸入管理者密碼即可安裝。你也可以在設定中關閉檢查。',
      ],
    },
  },
  changelog: {
    title: '更新紀錄',
    empty: '尚無發行版本。',
    download: '下載',
  },
  privacy: {
    title: '隱私權',
    updated: '2026 年 10 月 22 日更新',
    sections: [
      {
        title: 'Sugu 儲存的內容',
        body: [
          'Sugu 從你輸入完成的內容中學到的字詞和片語，以及你加入的字詞，都儲存在你 Mac 上的資料庫中。你可以搜尋和刪除它們、忘記最近一小時學到的內容、在某些 App 中停止學習，或關閉學習。',
          'Sugu 會讀取輸入欄位中已有的文字來排序候選字，但從不儲存這些文字。',
          '如果你開啟 Apple 的語言模型（macOS 27 或以上版本）來翻譯或改寫文字，它在你的 Mac 上執行，不傳送任何內容。',
          '如果你選擇了一個檔案夾在多台 Mac 之間同步學到的字詞，Sugu 會把它們寫入該檔案夾，由同步該檔案夾的服務傳送。',
        ],
      },
      {
        title: 'Sugu 傳送的內容',
        body: ['Sugu 沒有遙測、當機報告或分析資料收集，也沒有帳號。它只在以下情況連線：'],
        list: [
          '檢查更新，可以關閉：連線到 sugu.zheng-she.com 檢查 Sugu；打開設定時，每天最多一次連線到 GitHub，檢查你已下載的霧凇拼音詞庫和文法模型是否有新版本。不傳送關於你 Mac 的資訊，傳到 sugu.zheng-she.com 的請求中只包含 Sugu 的版本。',
          '你自行啟動的下載：選用的霧凇拼音詞庫來自 GitHub，文法模型來自 GitHub 或 sugu.zheng-she.com，Zenzai 模型來自 Hugging Face。',
        ],
      },
      {
        title: '本網站',
        body: ['本網站不使用 Cookie、分析工具或第三方指令碼。網站由 Cloudflare 提供，Cloudflare 為傳送網頁而處理請求。'],
      },
    ],
  },
  licenses: {
    title: '授權',
    sugu: 'Sugu 是自由軟體，以 GNU 通用公共授權條款第 3 版或更新版本授權。',
    source: '原始碼',
    license: 'GNU 通用公共授權條款',
    notices: '第三方聲明',
  },
  footer: { copyright: '© 2026 Zheng She' },
} satisfies Messages;
