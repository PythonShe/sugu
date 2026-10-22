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

# License texts for bundled code that ships without one in its sources
# (scripts/make-notices.sh).
LLAMA_CPP_REF=b4846
LLAMA_CPP_LICENSE_SHA256=e562a2ddfaf8280537795ac5ecd34e3012b6582a147ef69ba6a6a5c08c84757d
MOZC_REF=0136c35782536cb43d710575c311cd4185982738
MOZC_LICENSE_SHA256=44cdd923b91ea9199293abecc2762c70c87dbf1e581c027a94c416368d1a648c
CLDR_REF=release-46
CLDR_LICENSE_SHA256=743308f92225393665b0722b73418b4d4061fd2163e8e9c38b3368904acf19d6

# Sparkle, the updater (Packages/SuguKit/Package.swift pins the same version).
SPARKLE_VERSION=2.10.0
SPARKLE_TOOLS_SHA256=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
SPARKLE_LICENSE_SHA256=389a4e4e9a32f059775b13a06e25a591445ba229d2838d26dd3e7c0c45127cfe
# Creative Commons Paternité 2.0 France legal code (Tatoeba), from the
# cc-legal-tools-data repository.
CC_LEGAL_TOOLS_REF=a0dac18d1a773b4cdb7d8dd5d9bf4efab7901030
CC_BY_2_FR_SHA256=597d4c64f6606c64da65ba6c079e5cc87e4cce2b5187eda908c939b538e7ab9b
