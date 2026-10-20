import type { Messages } from './messages';

export default {
  description: 'Sugu 是一款免費的 Mac 輸入法，用來輸入中文和日文。',
  nav: { changelog: '更新記錄', privacy: '隱私權', licenses: '授權', language: '語言' },
  home: {
    title: 'Mac 上的中文與日文輸入法。',
    lead: 'Sugu 在一個輸入來源裡輸入中文、日文和英文，把你想要的詞放在第一位。轉換和學習都在你的 Mac 上完成。',
    download: '下載',
    requirement: '免費 · macOS 14 或以上版本',
    version: (version: string) => `版本 ${version}`,
    features: [
      { title: '一個輸入來源', body: '用 Shift、Caps Lock 或かな、英数鍵在中文、日文和英文之間切換。' },
      { title: '中文', body: '注音、全拼和雙拼，繁體或簡體，支援模糊音。' },
      { title: '日文', body: '羅馬字或假名輸入，逐文節轉換或即時轉換，聯想輸入，容錯輸入。' },
      { title: '學習你的寫法', body: '你常用的詞和片語排在前面。學到的內容可以搜尋、置頂和刪除，也可以忘記最近一小時。' },
      { title: '留在你的 Mac 上', body: '不需要帳號，沒有數據分析。除非你開啟私密雲端運算，Sugu 不會傳送你輸入的任何內容。' },
      { title: '帶上你的詞庫', body: '可以匯入 Google 日本語入力、Microsoft IME、ATOK、搜狗、RIME 和 macOS 文字替代中的詞。' },
    ],
    install: {
      title: '安裝',
      steps: [
        '打開下載的安裝包，依照安裝程式的指示操作。',
        '輸入法選單中會加入 Sugu。若沒有，請在「系統設定」›「鍵盤」›「輸入方式」›「編輯」中，從「簡體中文」下加入；若列表中還沒有它，請登出後重新登入。',
        'Sugu 會自動檢查更新，你可以在它的設定中關閉。',
      ],
    },
  },
  changelog: {
    title: '更新記錄',
    empty: '還沒有發佈版本。',
    download: '下載',
  },
  privacy: {
    title: '隱私權',
    updated: '2026 年 10 月 20 日更新',
    sections: [
      {
        title: 'Sugu 保存的內容',
        body: [
          'Sugu 從你輸入完成的內容中學到的詞和片語，以及你加入的詞，都保存在你 Mac 上的資料庫中。你可以搜尋和刪除它們、忘記最近一小時、在某些 App 中停止學習，或關閉學習。',
          'Sugu 為排列候選字而讀取的輸入欄中已有的文字，從不保存。',
          '如果你選擇了一個檔案夾在多台 Mac 之間同步學到的詞，Sugu 會把它們寫入該檔案夾，由同步該檔案夾的服務傳送。',
        ],
      },
      {
        title: 'Sugu 傳送的內容',
        body: ['Sugu 沒有遙測、當機報告、數據分析，也沒有帳號。它只在以下情況連網：'],
        list: [
          '檢查更新，連線到 sugu.zheng-she.com，可以關閉。不傳送關於你 Mac 的資訊，請求中只包含 Sugu 的版本。',
          '你開始的下載：選用的 rime-ice 詞庫和語法模型來自 GitHub，Zenzai 模型來自 Hugging Face。',
          '私密雲端運算，僅在你選擇時：正在轉換的文字、游標前的文字或你選取的文字會傳送到 Apple 的私密雲端運算，用於轉換、翻譯或改寫。選擇「在此 Mac 上」時，Apple 的模型在你的 Mac 上執行，不傳送任何內容。',
        ],
      },
      {
        title: '本網站',
        body: ['本網站不使用 Cookie、數據分析或第三方指令碼。網站由 Cloudflare 提供，Cloudflare 為傳送網頁而處理請求。'],
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
