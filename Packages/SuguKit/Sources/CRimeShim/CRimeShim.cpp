#include "CRimeShim.h"

// Defined by RIME_REGISTER_MODULE in librime-octagram.
void rime_require_module_octagram();
void rime_require_module_grammar();

extern "C" void sugu_rime_link_plugins(void) {
  rime_require_module_octagram();
  rime_require_module_grammar();
}
