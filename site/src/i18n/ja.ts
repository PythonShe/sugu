import type { Messages } from './messages';

export default {
  description: 'Sugu は、Mac で中国語と日本語を入力するための無料のインプットメソッドです。',
  nav: { changelog: '更新履歴', privacy: 'プライバシー', licenses: 'ライセンス', language: '言語' },
  home: {
    title: 'Mac のための中国語・日本語入力。',
    lead: 'Sugu は中国語・日本語・英語をひとつの入力ソースで扱い、思いどおりの言葉を最初に出します。変換も学習も Mac の中で行われます。',
    download: 'ダウンロード',
    requirement: '無料 · macOS 14 以降',
    version: (version: string) => `バージョン ${version}`,
    features: [
      { title: 'ひとつの入力ソース', body: 'Shift、Caps Lock、かな・英数キーで、中国語・日本語・英語を切り替えられます。' },
      { title: '中国語', body: '全拼、双拼、注音に対応。簡体字でも繁体字でも入力でき、あいまいピンインも使えます。' },
      { title: '日本語', body: 'ローマ字入力とかな入力、文節ごとの変換とライブ変換、予測変換、タイプミスの補正。' },
      { title: '書き方を学習', body: 'よく使う言葉や言い回しが先に出ます。学習した内容は検索・固定・削除でき、直近1時間の学習を消去することもできます。' },
      { title: 'Mac の中で完結', body: 'アカウントも利用状況の分析もありません。Apple Private Cloud Compute を有効にしない限り、入力した内容を送信することはありません。' },
      { title: '辞書を引き継げる', body: 'Google 日本語入力、Microsoft IME、ATOK、Sogou、RIME、macOS のユーザ辞書から単語を読み込めます。' },
    ],
    install: {
      title: 'インストール',
      steps: [
        'ダウンロードしたパッケージを開き、インストーラの指示に従います。',
        '入力メニューに Sugu が追加されます。見当たらない場合は「システム設定」›「キーボード」›「入力ソース」›「編集」で「簡体字中国語」から追加します。一覧にないときは、ログアウトしてからログインし直してください。',
        'Sugu はアップデートを自動で確認します。確認は設定でオフにできます。',
      ],
    },
  },
  changelog: {
    title: '更新履歴',
    empty: 'まだリリースはありません。',
    download: 'ダウンロード',
  },
  privacy: {
    title: 'プライバシー',
    updated: '2026年10月20日更新',
    sections: [
      {
        title: 'Sugu が保存するもの',
        body: [
          '確定した内容から学習した単語や言い回し、追加した単語は、Mac 上のデータベースに保存されます。検索や削除のほか、直近1時間の学習の消去、特定のアプリでの学習の停止、学習のオフもできます。',
          '候補の順位づけのために読み取る入力欄の既存のテキストは、保存されません。',
          '学習した単語を Mac 間で同期するフォルダを選んだ場合は、そのフォルダに書き出されます。その先の同期は、そのフォルダを同期しているサービスが行います。',
        ],
      },
      {
        title: 'Sugu が送信するもの',
        body: ['Sugu にはテレメトリ、クラッシュレポート、分析、アカウントはありません。通信するのは次の場合だけです。'],
        list: [
          'アップデートの確認。sugu.zheng-she.com に接続します。オフにできます。Mac の情報は送信せず、リクエストに含まれるのは Sugu のバージョンだけです。',
          'ユーザが始めたダウンロード。オプションの rime-ice 辞書と文法モデルは GitHub から、Zenzai モデルは Hugging Face からダウンロードします。',
          'Apple Private Cloud Compute。選んだ場合に限り、変換中のテキスト、カーソルより前のテキスト、または選択したテキストを、変換・翻訳・書き直しのために Apple Private Cloud Compute に送ります。「このMac上」を選んだ場合は Apple のモデルが Mac 上で動作し、何も送信しません。',
        ],
      },
      {
        title: 'このWebサイト',
        body: ['このWebサイトは Cookie、アクセス解析、サードパーティのスクリプトを使用しません。配信は Cloudflare が行い、配信のためにリクエストを処理します。'],
      },
    ],
  },
  licenses: {
    title: 'ライセンス',
    sugu: 'Sugu は無料のプロプライエタリソフトウェアです。',
    license: 'Sugu ライセンス',
    notices: 'サードパーティのライセンス表記',
  },
  footer: { copyright: '© 2026 Zheng She' },
} satisfies Messages;
