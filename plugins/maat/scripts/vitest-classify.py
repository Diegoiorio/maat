#!/usr/bin/env python3
"""vitest-classify.py — which vitest project a test file of apps/admin belongs to: `unit` or `nuxt`.

ONE-OFF script (harness-pt06, step 1): it produced the UNIT_TEST_FILES list of
modules/app/apps/admin/vitest.config.ts (used by vitest.workspace.ts), and it is run again to move more files. It is also used by
scripts/vitest-classify.test.sh, which checks the list against the current classification.

Usage: python3 scripts/vitest-classify.py <apps/admin dir> [--nuxt-dir <.nuxt dir>] [test files…]
      without files: all `*.test.ts` outside node_modules, e2e, .nuxt, .output.
Output: one line per file, TAB-separated: `unit<TAB><file>` or `nuxt<TAB><file><TAB><reason>`.
Exit: 0 · 2 = wrong usage or generated declarations missing (needs `npx nuxi prepare` or a vitest run).

RULE: WHEN IN DOUBT, `nuxt` (errors in one direction only). A file goes to `nuxt` if it, or a local file it
imports (transitively: relative, `~/`, `@/`, `~~/`, `@@/`, `@repo/<package>`), meets one of:
- uses an API of the Nuxt runtime or of the test DOM: mountSuspended, renderSuspended, mockNuxtImport, mockComponent,
  registerEndpoint, useNuxtApp, `$fetch`, imports from `#…` (#imports, #app, #components, #build), from
  `@nuxt/test-utils`, `@vue/test-utils`, `@testing-library/…`, `nuxt`, `vuetify`, `happy-dom`, `jsdom`;
- imports a `.vue` file (mounting, template, auto-imported components);
- names a DOM global (document, window, localStorage, …): they do not exist in the `unit` project;
- uses, without importing or declaring it, an AUTO-IMPORTED name (`.nuxt/imports.d.ts`: composables, utils,
  stores, vue APIs) or an auto-imported component (`.nuxt/components.d.ts`, also in kebab-case);
- depends on Nuxt defines (`import.meta.client|server|dev|browser`, `process.client|server`);
- has an unresolvable import (local file missing, unknown @repo package).
A `@vitest-environment <x>` docblock other than `node` -> nuxt. With `node` the file still goes through the rules
above: the `unit` project lacks the Nuxt pipeline (auto-imports, `#…` aliases), which in the `nuxt` project the file
keeps having even with the docblock's `node` environment.
Block comments and comment-only lines do not count; everything else (strings included) does.

MESSAGES (1.4.0): the reasons and the errors come from the catalog lib/messages.tsv (maat_msg.T, next to this file):
English by default, Italian with "lingua": "it". The classes `unit`/`nuxt` and the TAB-separated lines stay.
"""
import os
import re
import sys

sys.dont_write_bytecode = True   # no __pycache__ under MAAT_ROOT
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from maat_msg import T  # noqa: E402

DOM_GLOBALS = [
    'document', 'window', 'navigator', 'localStorage', 'sessionStorage', 'location', 'history',
    'HTMLElement', 'HTMLInputElement', 'HTMLDivElement', 'Element', 'getComputedStyle',
    'requestAnimationFrame', 'cancelAnimationFrame', 'IntersectionObserver', 'ResizeObserver',
    'MutationObserver', 'customElements', 'DOMParser', 'matchMedia', 'innerWidth', 'innerHeight',
    'KeyboardEvent', 'MouseEvent', 'PointerEvent', 'FocusEvent', 'InputEvent', 'DataTransfer',
    'CustomEvent', 'FileReader', 'scrollTo',
]
NUXT_APIS = [
    'mountSuspended', 'renderSuspended', 'mockNuxtImport', 'mockComponent', 'registerEndpoint',
    'useNuxtApp', r'\$fetch',
]
NUXT_DEFINES = r'import\.meta\.(client|server|dev|browser|nitro)\b|process\.(client|server|browser)\b'
NUXT_SPECS = re.compile(r'^(#|@nuxt/|@vue/test-utils|@testing-library/|nuxt(/|$)|vuetify|happy-dom|jsdom|@pinia/nuxt)')
SPEC_RE = re.compile(
    r"""(?:\bfrom\s*|\bimport\s*\(\s*|\bimport\s+|\brequire\s*\(\s*|vi\.(?:mock|doMock|importActual|importMock)\s*\(\s*)"""
    r"""(['"])([^'"\n]+)\1""")
ENV_RE = re.compile(r'@vitest-environment\s+([\w-]+)')
EXTS = ['', '.ts', '.js', '.mjs', '.mts', '/index.ts', '/index.js']


def strip_comments(src):
    src = re.sub(r'/\*.*?\*/', ' ', src, flags=re.S)
    return '\n'.join(l for l in src.split('\n') if not l.lstrip().startswith('//'))


def parse_auto_imports(nuxt_dir):
    names = set()
    with open(os.path.join(nuxt_dir, 'imports.d.ts'), encoding='utf-8') as f:
        for m in re.finditer(r'export\s*\{([^}]*)\}\s*from', f.read()):
            for part in m.group(1).split(','):
                part = part.strip()
                if not part or part.startswith('type '):
                    continue
                names.add(part.split(' as ')[-1].strip())
    comps = set()
    with open(os.path.join(nuxt_dir, 'components.d.ts'), encoding='utf-8') as f:
        for m in re.finditer(r"^\s*'([A-Z][A-Za-z0-9]*)'\s*:", f.read(), flags=re.M):
            comps.add(m.group(1))
    return names, comps


def kebab(name):
    return re.sub(r'(?<!^)(?=[A-Z])', '-', name).lower()


def local_names(src):
    """Names imported or declared in the file: these are NOT auto-imports."""
    got = set()
    for m in re.finditer(r"""\bimport\s+(type\s+)?([^'"]*?)\s+from\s""", src, flags=re.S):
        clause = m.group(2)
        for b in re.findall(r'\{([^}]*)\}', clause):
            for part in b.split(','):
                part = part.strip()
                if part.startswith('type '):
                    part = part[5:]
                if part:
                    got.add(part.split(' as ')[-1].strip())
        rest = re.sub(r'\{[^}]*\}', '', clause)
        for tok in re.split(r'[,\s]+', rest):
            tok = tok.strip()
            if tok and tok not in ('*', 'as', 'type') and re.match(r'^[A-Za-z_$][\w$]*$', tok):
                got.add(tok)
    for m in re.finditer(r'\b(?:function\*?|class|const|let|var|type|interface|enum)\s+([A-Za-z_$][\w$]*)', src):
        got.add(m.group(1))
    # arrow function parameters: `h => …`, `(a, h) => …`
    for m in re.finditer(r'(?<![\w$.])([A-Za-z_$][\w$]*)\s*=>', src):
        got.add(m.group(1))
    for m in re.finditer(r'\(([^()]*)\)\s*(?::[^=()]*)?=>', src):
        for part in m.group(1).split(','):
            part = re.split(r'[:=?]', part.strip().lstrip('.'))[0].strip()
            if re.match(r'^[A-Za-z_$][\w$]*$', part):
                got.add(part)
    for m in re.finditer(r'\b(?:const|let|var)\s*\{([^}]*)\}\s*=', src):
        for part in m.group(1).split(','):
            part = part.strip().split(':')[-1].split('=')[0].strip()
            if part:
                got.add(part)
    return got


class Classifier:
    def __init__(self, admin, nuxt_dir):
        self.admin = os.path.abspath(admin)
        self.app = os.path.dirname(os.path.dirname(self.admin))   # modules/app
        self.auto, self.comps = parse_auto_imports(nuxt_dir)
        self.auto_re = self._words(self.auto)
        comp_words = sorted(self.comps | {'Lazy' + c for c in self.comps}, key=len, reverse=True)
        self.comp_re = re.compile(r'(?<![\w$.-])(' + '|'.join(re.escape(c) for c in comp_words)
                                  # kebab-case only for multi-word names: `Title` -> `title` is an ordinary
                                  # word, `GoalsUserPanelBody` -> `goals-user-panel-body` is not
                                  + ''.join('|' + re.escape(kebab(c)) for c in self.comps if '-' in kebab(c))
                                  + r')(?![\w$-])') \
            if self.comps else None
        self.dom_re = self._words(DOM_GLOBALS)
        self.api_re = re.compile(r'(?<![\w$])(' + '|'.join(NUXT_APIS) + r')(?![\w$])')
        self.pkgs = {}
        pk = os.path.join(self.app, 'packages')
        for d in (os.listdir(pk) if os.path.isdir(pk) else []):
            pj = os.path.join(pk, d, 'package.json')
            if os.path.isfile(pj):
                m = re.search(r'"name"\s*:\s*"([^"]+)"', open(pj, encoding='utf-8').read())
                main = re.search(r'"main"\s*:\s*"([^"]+)"', open(pj, encoding='utf-8').read())
                if m:
                    self.pkgs[m.group(1)] = (os.path.join(pk, d), main.group(1) if main else 'index.ts')
        self.memo = {}

    @staticmethod
    def _words(words):
        return re.compile(r'(?<![\w$.])(' + '|'.join(re.escape(w) for w in sorted(words, key=len, reverse=True))
                          + r')(?![\w$])') if words else None

    def resolve(self, spec, frm):
        """Absolute path of the local file, None if the module is external, '' if local and unresolvable."""
        base = None
        if spec.startswith('.'):
            base = os.path.join(os.path.dirname(frm), spec)
        elif spec.startswith(('~/', '@/')):
            base = os.path.join(self.admin, spec[2:])
        elif spec.startswith(('~~/', '@@/')):
            base = os.path.join(self.admin, spec[3:])
        elif spec.startswith('@repo/'):
            name = '/'.join(spec.split('/')[:2])
            if name not in self.pkgs:
                return ''
            root, main = self.pkgs[name]
            sub = spec[len(name) + 1:]
            base = os.path.join(root, sub) if sub else os.path.join(root, main)
        else:
            return None
        for ext in EXTS:
            p = os.path.normpath(base + ext)
            if os.path.isfile(p):
                return p
        return ''

    def reason(self, path, stack=()):
        """Reason why the file (or one of its local imports) needs `nuxt`; None if it is pure."""
        if path in self.memo:
            return self.memo[path]
        if path in stack:
            return None   # cycle: the file is already being examined further up
        self.memo[path] = None
        why = self._reason(path, stack + (path,))
        self.memo[path] = why
        return why

    def _reason(self, path, stack):
        rel = os.path.relpath(path, self.admin)
        if path.endswith('.vue'):
            return T('vitest-classify.imports_vue') + rel
        try:
            raw = open(path, encoding='utf-8').read()
        except OSError:
            return T('vitest-classify.unreadable') + rel
        src = strip_comments(raw)
        m = re.search(NUXT_DEFINES, src)
        if m:
            return T('vitest-classify.nuxt_define', define=m.group(0), rel=rel)
        m = self.api_re.search(src)
        if m:
            return T('vitest-classify.nuxt_api', api=m.group(1), rel=rel)
        if self.dom_re:
            m = self.dom_re.search(src)
            if m:
                return T('vitest-classify.dom_global', name=m.group(1), rel=rel)
        known = local_names(src)
        if self.auto_re:
            # An auto-imported name inside a '…' or "…" string is not a runtime reference ('Manager' as a
            # role); template literals stay, because of `${…}`. `readonly` counts only as a call: it is also
            # the TypeScript modifier (`readonly string[]`).
            code = re.sub(r"""'(?:\\.|[^'\\\n])*'|"(?:\\.|[^"\\\n])*\"""", "''", src)
            for m in self.auto_re.finditer(code):
                name = m.group(1)
                if name in known or (name == 'readonly' and not re.match(r'\s*\(', code[m.end():])):
                    continue
                return f'auto-import {name} in {rel}'
        if self.comp_re:
            m = self.comp_re.search(src)
            if m and m.group(1) not in known:
                return T('vitest-classify.auto_component', name=m.group(1), rel=rel)
        for m in SPEC_RE.finditer(src):
            spec = m.group(2)
            if NUXT_SPECS.match(spec):
                return T('vitest-classify.import_of', spec=spec, rel=rel)
            if spec.split('?')[0].endswith('.vue'):
                return T('vitest-classify.import_vue', spec=spec, rel=rel)
            dep = self.resolve(spec, path)
            if dep is None:
                continue
            if dep == '':
                return T('vitest-classify.unresolvable', spec=spec, rel=rel)
            why = self.reason(dep, stack)
            if why:
                return why
        return None

    def classify(self, test):
        path = os.path.abspath(os.path.join(self.admin, test))
        try:
            raw = open(path, encoding='utf-8').read()
        except OSError:
            return 'nuxt', T('vitest-classify.file_missing')
        m = ENV_RE.search(raw)
        if m and m.group(1) != 'node':
            return 'nuxt', f'docblock @vitest-environment {m.group(1)}'
        why = self.reason(path)
        return ('nuxt', why) if why else ('unit', None)


def all_tests(admin):
    out = []
    for d, dirs, files in os.walk(admin):
        dirs[:] = [x for x in dirs if x not in ('node_modules', 'e2e', '.nuxt', '.output', 'coverage')]
        out += [os.path.relpath(os.path.join(d, f), admin).replace(os.sep, '/') for f in files if f.endswith('.test.ts')]
    return sorted(out)


def main(argv):
    args = list(argv)
    nuxt_dir = None
    if '--nuxt-dir' in args:
        i = args.index('--nuxt-dir')
        if i + 1 >= len(args):
            print(T('vitest-classify.usage'), file=sys.stderr)
            return 2
        nuxt_dir = args[i + 1]
        del args[i:i + 2]
    if not args or not os.path.isdir(args[0]):
        print(T('vitest-classify.usage'), file=sys.stderr)
        return 2
    admin = args[0]
    nuxt_dir = nuxt_dir or os.path.join(admin, '.nuxt')
    for f in ('imports.d.ts', 'components.d.ts'):
        if not os.path.isfile(os.path.join(nuxt_dir, f)):
            print('vitest-classify: ' + T('vitest-classify.nuxt_missing', dir=nuxt_dir, f=f),
                  file=sys.stderr)
            return 2
    c = Classifier(admin, nuxt_dir)
    for t in (args[1:] or all_tests(admin)):
        kind, why = c.classify(t)
        print(f'{kind}\t{t}' + (f'\t{why}' if why else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
