# Pinned versions of everything Sugu builds or bundles from outside the repo.
# Sourced by the scripts in this directory.

SUGU_MACOS_DEPLOYMENT_TARGET=14.0

LIBRIME_REF=1.17.0
# The tag's commit: a tag can move.
LIBRIME_COMMIT=33e78140250125871856cdc5b42ddc6a5fcd3cd4
OCTAGRAM_REF=57d18b9f58e5284bd891d559f6bdd16cf60341e9
BOOST_VERSION=1.92.0
BOOST_SHA256=c4a3b310ddd2472416e091067166b0713be97c63f38c212c484ada022fd296ce

WANXIANG_REF=v18.1.6
WANXIANG_SHA256=d02793a93b9f92cea6f4dc2fcc1d6f92316c2fc96a23753877cf767b114c11c1
# RimeSharedData.importedTables in wanxiang's order, plus en for the English
# word list.
WANXIANG_DICTS="zi jichu cuoyin duoyin diming mingren yiren en"

# The AzooKeyKanaKanjiConverter release Sugu's fork is based on; the fork's
# commit is pinned in Packages/SuguKit/Package.swift.
AZOOKEY_BASE=0.11.2

# Tatoeba sentences (CC BY 2.0 FR) at an OPUS snapshot, for the character
# language models (ADR 0005).
TATOEBA_OPUS_VERSION=v2026-07-08
TATOEBA_JA_SHA256=d5b2eb0eb1084b20c8b86aff29aedb51dfac96eb53c8ba65fe6aa4dfaf00de60
TATOEBA_CMN_SHA256=1d582fbbf05e5af2ca718e3a6565597337eef2dfb562c9c73c4d2c4b86e56b76

# CLDR's Chinese emoji annotations (Unicode-DFS-2016), for emoji after
# Chinese words. CLDR 43 covers Emoji 15.0, which every supported macOS
# draws.
CLDR_ANNOTATIONS_REF=release-43
CLDR_ANNOTATIONS_ZH_SHA256=df647e5e09048f1d8f3605e5f6a04c6f616e5398c047039fc5e51b4da0151ac1
CLDR_ANNOTATIONS_ZH_HANT_SHA256=ca3b5553a153308ab455b6566fc5dc52e002b2fe9eb50114c8c3c100105ddc67
CLDR_ANNOTATIONS_LICENSE_SHA256=830ec6dd25a943b70a31d74caa56b08b34c35f5c9679fba664c1658712849271

# Foreign words. UniDic's lemmas name their source spelling (BSD, chosen from
# BSD, GPL or LGPL; only lex.csv and the license are taken from its 3 GB
# package, by range request). CLDR's names of languages, territories and
# cities (Unicode-3.0). scripts/data/wikidata-katakana.tsv.gz (CC0) is tracked.
UNIDIC_URL=https://clrd.ninjal.ac.jp/unidic_archive/2512/unidic-cwj-202512_full.zip
UNIDIC_VERSION=202512
UNIDIC_LEX_SHA256=bd00a695ba897a3250965257341e1929ae062dfa2e63b223a05bcc02f22e74a2
UNIDIC_BSD_SHA256=9980b1824f0d1dac41ea93dc96780c222e5cca3c4d1b5677ac8ab923a8533c3f
CLDR_NAMES_REF=release-49
CLDR_NAMES_LICENSE_SHA256=65eb33419e22a297550a811b5b535f5e532f9a7e0114b516c0ea18afd53c3804
CLDR_NAMES_SHA256_de=e5289a46e85cd2384660eeac0f1665a9aa90299f4e6c2864ec138402c0fff632
CLDR_NAMES_SHA256_en=f8cbf26964d0e349fc96d9e5a56292edcbaab25c8e64177ca4f111773dfb79cf
CLDR_NAMES_SHA256_es=85eb95dea0f020b13f7f615b09c86ebe568d71fd71f59c3720e23a65b9cddf50
CLDR_NAMES_SHA256_fr=7aa6b2f783d3223fb7e8fd1b4e0f3782d9731f2f91f829e93747e20ac7b3c268
CLDR_NAMES_SHA256_it=a9e8612bd4b80477de74bfac9ad2e86f1d73cf7d4c4bec1b365debb6469cbde8
CLDR_NAMES_SHA256_ja=d42a5c7327f6708cb9f13384ae2b7638ccaeafc17dc80a0a56dfe1491bc21c54
CLDR_NAMES_SHA256_nl=d423c9f9a880650153fc548bc8cbbc575c3478dd16b208d467ee30d0d0d52332
CLDR_NAMES_SHA256_pt=f5511280d86e4382116882525ae0c88c906dd6fe0cbc892122f768f2fafd46ec

# License texts for bundled code that ships without one in its sources
# (scripts/make-notices.sh).
LLAMA_CPP_REF=b4846
LLAMA_CPP_LICENSE_SHA256=e562a2ddfaf8280537795ac5ecd34e3012b6582a147ef69ba6a6a5c08c84757d
MOZC_REF=0136c35782536cb43d710575c311cd4185982738
MOZC_LICENSE_SHA256=44cdd923b91ea9199293abecc2762c70c87dbf1e581c027a94c416368d1a648c
CLDR_REF=release-46
CLDR_LICENSE_SHA256=743308f92225393665b0722b73418b4d4061fd2163e8e9c38b3368904acf19d6
# RapidJSON, inside OpenCC's sources without its license file.
RAPIDJSON_REF=v1.1.0
RAPIDJSON_LICENSE_SHA256=a140e5d46fe734a1c78f1a3c3ef207871dd75648be71fdda8e309b23ab8b1f32

# Sparkle, the updater (Packages/SuguKit/Package.swift pins the same version).
SPARKLE_VERSION=2.10.0
SPARKLE_TOOLS_SHA256=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
SPARKLE_LICENSE_SHA256=389a4e4e9a32f059775b13a06e25a591445ba229d2838d26dd3e7c0c45127cfe
# Creative Commons Paternité 2.0 France legal code (Tatoeba), from the
# cc-legal-tools-data repository.
CC_LEGAL_TOOLS_REF=a0dac18d1a773b4cdb7d8dd5d9bf4efab7901030
CC_BY_2_FR_SHA256=597d4c64f6606c64da65ba6c079e5cc87e4cce2b5187eda908c939b538e7ab9b
