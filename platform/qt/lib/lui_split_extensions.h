// Registers the Bonsplit-style split components (split-view, split-branch,
// split-pane, split-tab) on a LUI::ExtensionRegistry. Call before the
// registry is frozen into a LuiQmlBackend.
//
// The fingerprint literals mirror the schemas declared once in
// src/lui_split.ml; test/test_lui.ml ("split / host literals in sync") fails
// if they drift.

#pragma once

#include "lui_extension_registry.h"

class QString;

namespace LUI {

bool registerSplitExtensions(ExtensionRegistry &registry, QString *error);

} // namespace LUI
