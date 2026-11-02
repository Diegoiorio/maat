#!/usr/bin/env bash
# ui-transitiva.sh <worktree>
# Defect: a TRANSITIVE change in modules/app/packages/ui — the `ui` package that apps/admin imports
# (`import { Action } from "ui"`, dozens of components). The default size of the `Action` button
# is changed (packages/ui/src/button/action.vue: prop `size`, "small" → "x-small"; unique at all the
# corpus bases): no apps/admin file changes, but what it renders does. Attributed to the feature
# (touched.txt) if a code phase precedes the replayed one.
# Who catches it: evidence reuse (pt04), which must invalidate the apps/admin gates when a
# dependency changes, and the review, which must see the file outside apps/admin.
. "$(dirname "$0")/_lib.sh"
[ $# -eq 0 ] || die "$(msg inject.no_options)"
F=modules/app/packages/ui/src/button/action.vue
replace_once "$F" 'default: "small",' 'default: "x-small",'
mark_touched "$F"
inj_done "$F: $(msg inject.default_size)"
