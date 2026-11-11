#!/usr/bin/env bash
# nomi_test.test.sh — tests of nomi_test.py (Maat 1.8.0, D1-bis): the relation between the name of a test in the plan
# and the name of a case of the report (uguale | discendente | antenato | altro), with the separators of the language
# of the test file, and the table SIMBOLO_MANCANTE.
#   bash plugins/maat/scripts/nomi_test.test.sh          (Git Bash or WSL)
#   NT=/path/variant.py bash .../nomi_test.test.sh      # the suite against another copy of the module
# Cases: Go with the space written _, a Go subtest and its folded parent; pytest class and [param]; Rust mod::t;
# vitest describe > it, the full -t name, and a prefix with a space that is NOT a parent; bats «parses a/b» NOT the
# parent of «parses a/b c»; declared separators (separatori_test) that become levels. Counterproof at the end: a copy
# with relazione reduced to equality -> the hierarchical cases red.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
NT=${NT:-$HERE/nomi_test.py}
. "$HERE/python.sh" || true
[ -n "${FIC_PY:-}" ] || { echo "nomi_test.test.sh: nessun Python utilizzabile" >&2; exit 2; }
export PYTHONDONTWRITEBYTECODE=1 PYTHONIOENCODING=utf-8
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
nat() { cygpath -m "$1" 2>/dev/null || printf '%s' "$1"; }
pass=0 fail=0

# the cases: <expected> TAB <test file> TAB <plan name> TAB <case name> [TAB <vitest segments joined by |>] [TAB <declared separators joined by ,>]
cat > "$T/casi.tsv" <<'EOF'
uguale	m/body_test.go	TestX	m/body_test.go::TestX
discendente	m/body_test.go	TestX	m/body_test.go::TestX/limit_5,_50_bytes
uguale	m/body_test.go	TestX/limit 5, 50 bytes	m/body_test.go::TestX/limit_5,_50_bytes
antenato	m/body_test.go	TestX/limit 5, 50 bytes	m/body_test.go::TestX
altro	m/body_test.go	TestX	m/body_test.go::TestXY/a
altro	m/body_test.go	TestY	m/body_test.go::TestX/TestY_more
uguale	tests/test_core.py	test_uno	tests/test_core.py::test_uno
uguale	tests/test_core.py	tests/test_core.py::test_uno	tests/test_core.py::test_uno
discendente	tests/test_core.py	test_x	tests/test_core.py::test_x[a]
uguale	tests/test_core.py	test_x[a]	tests/test_core.py::test_x[a]
altro	tests/test_core.py	test_x[b]	tests/test_core.py::test_x[a]
discendente	tests/test_core.py	TestC	tests/test_core.py::TestC::test_a
uguale	tests/test_core.py	TestC::test_a	tests/test_core.py::TestC::test_a
antenato	tests/test_core.py	TestC::test_a	tests/test_core.py::TestC
altro	tests/test_core.py	test_x	tests/test_core.py::test_xy
altro	tests/test_core.py	a/b	tests/test_core.py::a
uguale	src/lib.rs	parse::empty	src/lib.rs::parse::empty
discendente	src/lib.rs	parse	src/lib.rs::parse::empty
antenato	src/lib.rs	parse::empty::nested	src/lib.rs::parse::empty
uguale	test/x.bats	parses a/b	test/x.bats::parses a/b
altro	test/x.bats	parses a/b	test/x.bats::parses a/b c
altro	test/x.bats	parses a	test/x.bats::parses a/b
discendente	test/x.bats	parses	test/x.bats::parses[1]
uguale	a.test.ts	describe > it	-	describe|it
uguale	a.test.ts	describe it	-	describe|it
uguale	a.test.ts	it	-	describe|it
discendente	a.test.ts	describe	-	describe|it
discendente	a.test.ts	outer > inner	-	outer|inner|it
antenato	a.test.ts	describe > it > deep	-	describe|it
altro	a.test.ts	parse	-	parse empty
altro	a.test.ts	parse	-	suite|parse empty
altro	a.test.ts	describe	-	other|it
uguale	t/x.foo	grp/caso	t/x.foo::grp/caso		/
discendente	t/x.foo	grp	t/x.foo::grp/caso		/
altro	t/x.foo	grp	t/x.foo::grp/caso
EOF

cat > "$T/drv.py" <<'EOF'
import importlib.util, sys
sys.dont_write_bytecode = True
s = importlib.util.spec_from_file_location("nomi_test", sys.argv[1]); nt = importlib.util.module_from_spec(s)
s.loader.exec_module(nt)
for n, l in enumerate(open(sys.argv[2], encoding="utf-8").read().splitlines(), 1):
    f = l.split("\t")
    exp, path, piano, caso = f[:4]
    segs = f[4].split("|") if len(f) > 4 and f[4] else None
    dich = f[5].split(",") if len(f) > 5 and f[5] else None
    if segs is not None:
        got = nt.relazione(piano, None, nt.SEP_VITEST, segmenti=segs)
    else:
        got = nt.relazione(piano, caso, nt.separatori(path, dich))
    print("%s\t%s\t%s\t%s" % ("OK" if got == exp else "NO", exp, got, l.replace("\t", " | ")))
print("sep\t%s" % ",".join(nt.separatori("a/b_test.go")))
print("sep\t%s" % ",".join(nt.separatori("a/test_b.py")))
print("sep\t%s" % ",".join(nt.separatori("a/b.rs")))
print("sep\t%s" % ",".join(nt.separatori("a/b.bats")))
print("sep\t%s" % ",".join(nt.separatori("a/b.bats", ["/"])))
print("foglia\t%s" % nt.foglia("TestX/limit 5, 50 bytes", nt.separatori("x_test.go")))
for t in ("./decode.go:12:3: undefined: MaxDepth", "x.Foo undefined (type T has no field or method MaxDepth)",
          "error[E0425]: cannot find value `depth`", "src/a.test.ts: SyntaxError: The requested module does not provide an export named 'MaxDepth'",
          "error TS2305: Module has no exported member", "ImportError: cannot import name 'max_depth' from 'app'",
          "AttributeError: module 'app' has no attribute 'max_depth'", "error: cannot find symbol", "SyntaxError: invalid syntax",
          "assert 2 == 1"):
    r = nt.simbolo_mancante(t)
    print("simbolo\t%s\t%s" % (r[0] if r else "-", t))
r = nt.simbolo_mancante("MYERR: nope", ["MYERR"])
print("simbolo\t%s\textra" % (r[0] if r else "-"))
EOF

esegui() { "$FIC_PY" "$(nat "$T/drv.py")" "$(nat "$1")" "$(nat "$T/casi.tsv")" > "$T/out" 2>&1; }
check() { if eval "$2"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: $1"; fi; }
esegui "$NT"
check "il modulo si importa e risponde" '[ -s "$T/out" ] && ! grep -q Traceback "$T/out"' || sed 's/^/    /' "$T/out"
while IFS=$'\t' read -r k exp got rest; do
  [ "$k" = OK ] || [ "$k" = NO ] || continue
  check "relazione $exp: $rest" '[ "$k" = OK ] || { echo "    ottenuto: $got"; false; }'
done < <(tr -d '\r' < "$T/out")
o=$(tr -d '\r' < "$T/out")
check "separatori: .go -> /,::" 'printf "%s\n" "$o" | grep -qx "sep	/,::"'
check "separatori: .py -> [,::" 'printf "%s\n" "$o" | sed -n "/^sep/p" | sed -n 2p | grep -qx "sep	\[,::"'
check "separatori: .rs -> solo ::" 'printf "%s\n" "$o" | sed -n "/^sep/p" | sed -n 3p | grep -qx "sep	::"'
check "separatori: .bats -> [,:: (niente /)" 'printf "%s\n" "$o" | sed -n "/^sep/p" | sed -n 4p | grep -qx "sep	\[,::"'
check "separatori dichiarati (separatori_test) al posto di quelli del linguaggio" 'printf "%s\n" "$o" | sed -n "/^sep/p" | sed -n 5p | grep -qx "sep	/,::"'
check "foglia Go: lo spazio scritto _" 'printf "%s\n" "$o" | grep -qx "foglia	limit_5,_50_bytes"'
check "SIMBOLO_MANCANTE: Go undefined e has no field or method" '[ "$(printf "%s\n" "$o" | grep -c "^simbolo	go	")" = 2 ]'
check "SIMBOLO_MANCANTE: Rust E0425, TS export e TS2305, Python import e attributo, Java" 'printf "%s\n" "$o" | grep -q "^simbolo	rust	error\[E0425\]" && [ "$(printf "%s\n" "$o" | grep -c "^simbolo	ts	")" = 2 ] && [ "$(printf "%s\n" "$o" | grep -c "^simbolo	python	")" = 2 ] && printf "%s\n" "$o" | grep -q "^simbolo	java	"'
check "SIMBOLO_MANCANTE: un errore di sintassi qualunque e un asserto non combaciano" 'printf "%s\n" "$o" | grep -qx "simbolo	-	SyntaxError: invalid syntax" && printf "%s\n" "$o" | grep -qx "simbolo	-	assert 2 == 1"'
check "SIMBOLO_MANCANTE: le regex in più (maat.json) estendono la tabella" 'printf "%s\n" "$o" | grep -qx "simbolo	maat.json	extra"'

# counterproof: relazione reduced to equality -> the descendant and ancestor cases are red
cp "$NT" "$T/mut.py"
"$FIC_PY" - "$(nat "$T/mut.py")" <<'EOF'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
a = "    for k in range(0, m - n):   # RELAZIONE-DISCENDENTE"
assert s.count(a) == 1
s = s.replace(a, "    return \"altro\"\n" + a)
open(p, "w", encoding="utf-8").write(s)
EOF
esegui "$T/mut.py"
nno=$(tr -d '\r' < "$T/out" | grep -c "^NO	")
check "controprova: relazione ridotta all uguaglianza -> i casi discendente e antenato rossi" '[ "$nno" -ge 10 ]'

echo "nomi_test.test.sh: $pass ok, $fail falliti"
[ "$fail" = 0 ]
