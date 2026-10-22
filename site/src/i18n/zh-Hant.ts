import type { Messages } from './messages';

export default {
  description: 'Sugu 是免費的 Mac 輸入法，可輸入中文和日文。',
  nav: { changelog: '更新紀錄', privacy: '隱私權', licenses: '授權', language: '語言' },
  home: {
    title: 'Mac 上的中文與日文輸入法。',
    lead: 'Sugu 把你想要的字詞排在第一位，在單一輸入方式中輸入中文、日文和英文。轉換和學習都在你的 Mac 上完成。',
    download: '下載',
    requirement: '免費 · macOS 14 或以上版本',
    version: (version: string) => `版本 ${version}`,
    features: [
      { title: '單一輸入方式', body: '用 Shift、大寫鎖定鍵，或「かな」和「英数」鍵在中文、日文和英文之間切換。' },
      { title: '中文', body: '注音、全拼和雙拼，繁體或簡體，支援模糊音。' },
      { title: '日文', body: '羅馬字或假名輸入，逐文節轉換或即時轉換，輸入預測，容錯輸入。' },
      { title: '學習你的寫法', body: '你常用的字詞和片語排在前面。學到的內容可以搜尋、釘選和刪除，也可以忘記最近一小時學到的內容。' },
      { title: '留在你的 Mac 上', body: '不需要帳號，也不收集分析資料，你輸入的內容不會離開你的 Mac。開啟 Apple 的裝置端模型後，它也在你的 Mac 上執行。' },
      { title: '沿用你的詞庫', body: '可以匯入 Google 日本語入力、Microsoft IME、ATOK、搜狗、RIME 和 macOS 文字替代中的字詞。' },
    ],
    install: {
      title: '安裝',
      steps: [
        '打開下載的安裝檔，依照安裝程式的指示操作。',
        '輸入法選單中會加入 Sugu。第一次安裝後，macOS 常常需要重新啟動 Mac 才會顯示它；若重新啟動後仍然沒有，請在「系統設定」›「鍵盤」›「輸入方式」›「編輯」中，從「簡體中文」下加入。',
        'Sugu 會自動檢查更新，你可以在它的設定中關閉。',
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
          '如果你開啟 Apple 的語言模型來翻譯或改寫文字，它在你的 Mac 上執行，不傳送任何內容。',
          '如果你選擇了一個檔案夾在多台 Mac 之間同步學到的字詞，Sugu 會把它們寫入該檔案夾，由同步該檔案夾的服務傳送。',
        ],
      },
      {
        title: 'Sugu 傳送的內容',
        body: ['Sugu 沒有遙測、當機報告或分析資料收集，也沒有帳號。它只在以下情況連線：'],
        list: [
          '檢查更新，可以關閉：連線到 sugu.zheng-she.com 檢查 Sugu；打開設定時，每天最多一次連線到 GitHub，檢查你已下載的霧凇拼音詞庫和文法模型是否有新版本。不傳送關於你 Mac 的資訊，傳到 sugu.zheng-she.com 的請求中只包含 Sugu 的版本。',
          '你自行啟動的下載：選用的霧凇拼音詞庫和文法模型來自 GitHub，Zenzai 模型來自 Hugging Face。',
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
    sugu: 'Sugu 是免費的專有軟體。',
    license: 'Sugu 授權',
    notices: '第三方聲明',
  },
  footer: { copyright: '© 2026 Zheng She' },
} satisfies Messages;
