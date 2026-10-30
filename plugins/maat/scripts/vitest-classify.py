#!/usr/bin/env python3
"""vitest-classify.py — in quale progetto vitest va un file di test di apps/admin: `unit` o `nuxt`.

Script UNA TANTUM (harness-pt06, passo 1): ha prodotto l'elenco UNIT_TEST_FILES di
modules/app/apps/admin/vitest.config.ts (usato da vitest.workspace.ts), e lo si rilancia quando si vuole spostare altri file. Lo usa anche
scripts/vitest-classify.test.sh, che verifica l'elenco contro la classificazione corrente.

Uso:  python3 scripts/vitest-classify.py <dir di apps/admin> [--nuxt-dir <dir .nuxt>] [file di test…]
      senza file: tutti i `*.test.ts` fuori da node_modules, e2e, .nuxt, .output.
Output: una riga per file, TAB-separata: `unit<TAB><file>` oppure `nuxt<TAB><file><TAB><motivo>`.
Exit: 0 · 2 = uso errato o dichiarazioni generate assenti (serve `npx nuxi prepare` o un run di vitest).

REGOLA: il DUBBIO VA A `nuxt` (errore in una sola direzione). Un file va a `nuxt` se lui, o un file locale che
importa (transitivamente: relativi, `~/`, `@/`, `~~/`, `@@/`, `@repo/<pacchetto>`), soddisfa uno di:
- usa un'API del runtime Nuxt o del DOM di test: mountSuspended, renderSuspended, mockNuxtImport, mockComponent,
  registerEndpoint, useNuxtApp, `$fetch`, import da `#…` (#imports, #app, #components, #build), da
  `@nuxt/test-utils`, `@vue/test-utils`, `@testing-library/…`, `nuxt`, `vuetify`, `happy-dom`, `jsdom`;
- importa un `.vue` (montaggio, template, componenti auto-importati);
- nomina un globale del DOM (document, window, localStorage, …): nel progetto `unit` non esistono;
- usa, senza importarlo ne' dichiararlo, un nome AUTO-IMPORTATO (`.nuxt/imports.d.ts`: composable, utils,
  store, API di vue) o un componente auto-importato (`.nuxt/components.d.ts`, anche in kebab-case);
- dipende dai define di Nuxt (`import.meta.client|server|dev|browser`, `process.client|server`);
- ha un import non risolvibile (file locale assente, pacchetto @repo sconosciuto).
Un docblock `@vitest-environment <x>` diverso da `node` -> nuxt. Con `node` il file passa comunque le regole qui
sopra: il progetto `unit` non ha la pipeline di Nuxt (auto-import, alias `#…`), che nel progetto `nuxt` il file
continua ad avere anche con l'environment `node` del docblock.
I commenti a blocco e le righe di solo commento non contano; tutto il resto (stringhe comprese) si.
"""
import os
import re
import sys

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
    """Nomi importati o dichiarati nel file: questi NON sono auto-import."""
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
    # parametri di arrow function: `h => …`, `(a, h) => …`
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
                                  # kebab-case solo per i nomi di piu' parole: `Title` -> `title` e' una parola
                                  # qualunque, `GoalsUserPanelBody` -> `goals-user-panel-body` no
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
        """Percorso assoluto del file locale, None se il modulo e' esterno, '' se locale e non risolvibile."""
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
        """Motivo per cui il file (o un suo import locale) chiede `nuxt`; None se e' puro."""
        if path in self.memo:
            return self.memo[path]
        if path in stack:
            return None   # ciclo: il file e' gia' in esame piu' su
        self.memo[path] = None
        why = self._reason(path, stack + (path,))
        self.memo[path] = why
        return why

    def _reason(self, path, stack):
        rel = os.path.relpath(path, self.admin)
        if path.endswith('.vue'):
            return 'importa un componente .vue: ' + rel
        try:
            raw = open(path, encoding='utf-8').read()
        except OSError:
            return 'illeggibile: ' + rel
        src = strip_comments(raw)
        m = re.search(NUXT_DEFINES, src)
        if m:
            return f'define di Nuxt {m.group(0)} in {rel}'
        m = self.api_re.search(src)
        if m:
            return f'API di Nuxt {m.group(1)} in {rel}'
        if self.dom_re:
            m = self.dom_re.search(src)
            if m:
                return f'globale del DOM {m.group(1)} in {rel}'
        known = local_names(src)
        if self.auto_re:
            # Un nome auto-importato dentro una stringa '…' o "…" non e' un riferimento a runtime ('Manager' come
            # ruolo); i template literal restano, per via di `${…}`. `readonly` conta solo come chiamata: e' anche
            # il modificatore di TypeScript (`readonly string[]`).
            code = re.sub(r"""'(?:\\.|[^'\\\n])*'|"(?:\\.|[^"\\\n])*\"""", "''", src)
            for m in self.auto_re.finditer(code):
                name = m.group(1)
                if name in known or (name == 'readonly' and not re.match(r'\s*\(', code[m.end():])):
                    continue
                return f'auto-import {name} in {rel}'
        if self.comp_re:
            m = self.comp_re.search(src)
            if m and m.group(1) not in known:
                return f'componente auto-importato {m.group(1)} in {rel}'
        for m in SPEC_RE.finditer(src):
            spec = m.group(2)
            if NUXT_SPECS.match(spec):
                return f'import di {spec} in {rel}'
            if spec.split('?')[0].endswith('.vue'):
                return f'import di un .vue ({spec}) in {rel}'
            dep = self.resolve(spec, path)
            if dep is None:
                continue
            if dep == '':
                return f'import non risolvibile {spec} in {rel}'
            why = self.reason(dep, stack)
            if why:
                return why
        return None

    def classify(self, test):
        path = os.path.abspath(os.path.join(self.admin, test))
        try:
            raw = open(path, encoding='utf-8').read()
        except OSError:
            return 'nuxt', 'file assente'
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
            print('uso: vitest-classify.py <apps/admin> [--nuxt-dir <dir>] [file…]', file=sys.stderr)
            return 2
        nuxt_dir = args[i + 1]
        del args[i:i + 2]
    if not args or not os.path.isdir(args[0]):
        print('uso: vitest-classify.py <apps/admin> [--nuxt-dir <dir>] [file…]', file=sys.stderr)
        return 2
    admin = args[0]
    nuxt_dir = nuxt_dir or os.path.join(admin, '.nuxt')
    for f in ('imports.d.ts', 'components.d.ts'):
        if not os.path.isfile(os.path.join(nuxt_dir, f)):
            print(f'vitest-classify: manca {nuxt_dir}/{f} (npx nuxi prepare, o un run di vitest nella copia)',
                  file=sys.stderr)
            return 2
    c = Classifier(admin, nuxt_dir)
    for t in (args[1:] or all_tests(admin)):
        kind, why = c.classify(t)
        print(f'{kind}\t{t}' + (f'\t{why}' if why else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
