#!/usr/bin/env bash
# cycle-state.test.sh — la tabella di ripresa, riga per riga, in un repo git usa-e-getta.
#   bash plugins/maat/scripts/cycle-state.test.sh
#   CS=/percorso/variante.sh bash .../cycle-state.test.sh   # controprova su una mutazione
set -uo pipefail
set -f
HERE=$(cd "$(dirname "$0")" && pwd)
CS=${CS:-$HERE/cycle-state.sh}
PC="$HERE/plan-check.sh"
RS="$HERE/review-surface.sh"
# lo script cerca plan-check e review-surface accanto a se': una variante va messa in una copia dell'albero
pass=0 fail=0
W=$(mktemp -d) || exit 2
O=$(mktemp -d) || exit 2
trap 'rm -rf "$W" "$O"' EXIT
cd "$W" || exit 2
git init -q .; git config user.email t@t; git config user.name t; git config core.autocrlf false
mkdir -p src .claude/.ai-workflow
printf 'spec-*\n' > .claude/.ai-workflow/.gitignore
printf 'uno\n' > src/a.py; printf 'altro\n' > src/b.py
git add -A; git commit -qm init
SP=.claude/.ai-workflow/spec-x.md
RUN=.claude/.ai-workflow/spec-x.run

expect() { # $1 descrizione, $2 regex attesa sulla riga Next
  local out; out=$(bash "$CS" "$SP" 2>&1)
  if printf '%s\n' "$out" | grep -q "^Next: " && printf '%s\n' "$out" | sed -n "s/^Next: //p" | grep -Eq -- "$2"; then pass=$((pass + 1))
  else fail=$((fail + 1)); echo "FAIL [$1] atteso /$2/"; printf '%s\n' "$out" | sed 's/^/    /'; fi
}
state() { bash "$CS" "$SP" | sed -n 's/^State: //p'; }

above() { printf '%s\n' "# X" "## Contesto" "Contesto." "## Requisiti funzionali" "1. Fare A."; }
plan() { # $1 Plan status
  printf '%s\n' "## Piano di implementazione" "Plan status: $1" "Test level: std" "Superfici a rischio: nessuna" \
    "### Passi" "1. Modificare \`src/a.py\`." "### Changelog revisione piano" "- giro 1: ok"
}
with_basis() { # scrive la riga Approved basis nella spec corrente
  local cur; cur=$(bash "$PC" basis "$SP" | sed -n 's/^Basis: //p')
  sed -i "s/^Superfici a rischio: .*/&\nApproved basis: $cur/" "$SP"
}
review() { # $1 Review status, $2 Feature status, [$3 snapshot line], [$4 contract line]
  printf '%s\n' "## Review implementazione" "Review status: $1" "Feature status: $2" "Verification: VERIFIED"
  [ -n "${3:-}" ] && printf '%s\n' "$3"
  [ -n "${4:-}" ] && printf '%s\n' "$4"
  printf '%s\n' "Review rounds: 1/3 · post-approval NEEDS_CHANGES: 0/1" "" "<details><summary>Manifest (1 paths)</summary>" "" \
    "Scope:" "src/a.py" "" "Excluded:" "src/b.py" "" "</details>"
}
esito() { # $1 label, $2 riga ESITO, $3 state — come run-phase: .jsonl, .esito e, se l'attribuzione e' misurata, pre/post-tree
  mkdir -p "$RUN/log"; : > "$RUN/log/$1.jsonl"; printf '%s\nstate=%s\n' "$2" "$3" > "$RUN/log/$1.esito"
  case "$1" in *implement*|*fix*) echo x > "$RUN/log/$1.pre-tree"; echo y > "$RUN/log/$1.post-tree" ;; esac
}
esito_inline() { # come la modalita' --inline: nessun .jsonl
  mkdir -p "$RUN/log"; printf '%s\nstate=%s\n' "$2" "$3" > "$RUN/log/$1.esito"
  echo x > "$RUN/log/$1.pre-tree"; echo y > "$RUN/log/$1.post-tree"
}
reset() { rm -rf "$RUN"; git checkout -q -- src; git clean -qfd src; }
rjson() { # $1 label, $2 fase, $3 esito, $4 deviazioni (lista JSON), $5 bloccato_su — come run-phase: result.json valido
  printf '{"fase":"%s","esito":"%s","motivo":"m","deviazioni":%s,"bloccato_su":"%s","file":[],"gate_interni":[],"finding":[]}\n' \
    "$2" "$3" "$4" "$5" > "$RUN/log/$1.result.json"
}

# --- piano ---
above > "$SP"; expect "nessun piano" "^PLAN"
{ above; plan DRAFT; } > "$SP"; expect "DRAFT senza review" "^PLAN"
{ above; plan "NEEDS HUMAN DECISION"; } > "$SP"; expect "NHD senza review" "^STOP — decisione aperta"
{ above; plan "PENDING"; } > "$SP"; expect "Plan status non standard" "^STOP — Plan status non riconosciuto"
{ above; plan APPROVED; } > "$SP"; expect "APPROVED legacy, nessuna review" "^IMPLEMENT"
with_basis; expect "APPROVED con basis FRESH" "^IMPLEMENT"
sed -i 's/^Contesto\.$/Contesto cambiato./' "$SP"; expect "spec cambiata dopo l'approvazione" "^STOP — spec o piano cambiati.*STALE \(spec\)"
{ above; plan APPROVED; } > "$SP"; with_basis; sed -i 's/Modificare `src\/a.py`/Modificare `src\/c.py`/' "$SP"
expect "piano cambiato a mano dopo l'approvazione" "^STOP — .*STALE \(plan\)"
{ above; plan APPROVED; } > "$SP"; with_basis; sed -i 's/^- giro 1: ok/&\nMetrica ciclo: giri=1 · esito=approvato/' "$SP"
expect "solo il changelog cambiato" "^IMPLEMENT"

# --- implement → review (run dir) ---
{ above; plan APPROVED; } > "$SP"; with_basis
esito 02-implement "ESITO FASE implement: OK — fatto" "$(state)"; expect "implement OK, stato invariato" "^REVIEW — implementazione finita"
esito 02-implement "ESITO FASE implement: STOP — migrazione" "$(state)"; expect "implement STOP" "^IMPLEMENT"
esito 02-implement "ESITO FASE implement: OK — fatto" "000000000000"; expect "implement OK ma spec cambiata da allora" "^IMPLEMENT"
rm -f "$RUN/log/02-implement.esito"; expect "implement uccisa (nessun .esito)" "^IMPLEMENT"
reset

# --- esito strutturato (harness-pt08): result.json, regole in codice ---
{ above; plan APPROVED; } > "$SP"; with_basis
esito 02-implement "ESITO FASE implement: OK — fatto" "$(state)"
expect "run dir vecchia senza result.json: stesso Next di prima" "^REVIEW — implementazione finita \(02-implement\)"
rjson 02-implement implement OK '[]' nessuno; expect "result.json OK senza deviazioni → REVIEW" "^REVIEW — implementazione finita"
rjson 02-implement implement OK '["passo 8 adattato"]' nessuno
expect "deviazioni non vuote con esito OK → STOP" "^STOP — 02-implement: deviazioni dichiarate \(1\): passo 8 adattato"
rjson 02-implement implement OK '["difensiva: a.py:3 — ramo per un caso escluso dal CHECK", "difensiva: helper interno"]' nessuno
expect "solo deviazioni «difensiva: » → nessuno STOP, REVIEW" "^REVIEW — implementazione finita"
rjson 02-implement implement OK '["difensiva: a.py:3 — ramo", "passo 8 adattato"]' nessuno
expect "una difensiva e una no → STOP, tutte elencate" "^STOP — 02-implement: deviazioni dichiarate \(2\): difensiva: a.py:3 — ramo; passo 8 adattato"
rjson 02-implement implement STOP '["difensiva: a.py:3 — ramo"]' nessuno
expect "solo difensive ma esito STOP → STOP per l'esito" "^STOP — 02-implement: esito STOP"
rjson 02-implement implement STOP '[]' "migrazione da applicare — m.sql"
expect "bloccato_su diverso da nessuno → STOP" "^STOP — 02-implement: bloccato su: migrazione da applicare"
rjson 02-implement implement STOP '[]' nessuno; expect "esito STOP → STOP" "^STOP — 02-implement: esito STOP"
esito 02-implement "ESITO FASE implement: STOP — riga" "$(state)"; rjson 02-implement implement OK '[]' nessuno
expect "riga ESITO STOP con result.json OK: vale il piu conservativo" "^IMPLEMENT"
esito 02-implement "ESITO FASE implement: OK — fatto" "$(state)"; printf '{rotto' > "$RUN/log/02-implement.result.json"
expect "result.json illeggibile → STOP" "^STOP — 02-implement: result.json illeggibile"
rjson 02-implement implement OK '["x"]' nessuno; esito 02-implement "ESITO FASE implement: OK — fatto" "000000000000"
expect "result.json STOP ma spec cambiata da allora → IMPLEMENT (non uno STOP perpetuo)" "^IMPLEMENT"
esito 02-implement "ESITO FASE implement: STOP — JSON: deviazioni dichiarate (1): x" "$(state)"   # come la scrive run-phase
expect "deviazioni con stato invariato → STOP" "^STOP — 02-implement: deviazioni"
mv "$RUN/log/02-implement.result.json" "$RUN/log/02-implement.result.json.visto"
expect "recupero: result.json rinominato → decide la riga ESITO (STOP: si rilancia)" "^IMPLEMENT"
reset

# --- attribuzione misurata (R-b) ---
{ above; plan APPROVED; } > "$SP"; with_basis
esito 02-implement "ESITO FASE implement: OK — fatto" "$(state)"; rm -f "$RUN/log/02-implement.post-tree"
expect "implement OK senza .post-tree → STOP" "^STOP — attribuzione non misurata \(02-implement senza .post-tree\)"
rm -f "$RUN/log/02-implement.pre-tree"; expect "implement OK senza pre ne' post-tree → STOP" "^STOP — attribuzione non misurata"
reset; { above; plan APPROVED; } > "$SP"; with_basis
mkdir -p "$RUN/log"; : > "$RUN/log/02-implement.jsonl"; echo x > "$RUN/log/02-implement.pre-tree"   # fase uccisa
: > "$RUN/log/04-implement.jsonl"; echo 4 > "$RUN/log/04-implement.exit"                          # rilancio: lock occupato
expect "pre-tree aperto + rilancio bloccato dal lock: nessuno STOP spurio" "^IMPLEMENT"
esito 05-implement "ESITO FASE implement: OK — fatto" "$(state)"
expect "fase OK ma un .pre-tree di un label minore e' rimasto aperto → STOP" "^STOP — attribuzione non misurata \(02-implement con .pre-tree ancora aperto\)"
echo z > "$RUN/log/02-implement.post-tree"; expect "controprova: chiuso il .pre-tree → REVIEW" "^REVIEW — implementazione finita \(05-implement\)"
reset

# --- --inline: solo .esito, nessun .jsonl ---
{ above; plan APPROVED; } > "$SP"; with_basis
esito_inline 02-implement "ESITO FASE implement: OK — inline" "$(state)"; expect "implement inline OK → REVIEW" "^REVIEW — implementazione finita \(02-implement\)"
esito_inline 02-implement "ESITO FASE implement: STOP — deviazione" "$(state)"; expect "implement inline con STOP → IMPLEMENT (l'orchestratore si ferma sulla riga STOP)" "^IMPLEMENT"
reset
{ above; plan APPROVED; review NEEDS_CHANGES PLANNED; } > "$SP"
esito 03-review "ESITO FASE review: OK" "x"; esito_inline 04-fix "ESITO FASE fix: OK — inline" "$(state)"
expect "fix inline OK → REVIEW" "^REVIEW — correzione finita \(04-fix\)"
rm -f "$RUN/log/04-fix.post-tree"; expect "fix inline senza misura → STOP" "^STOP — attribuzione non misurata"
reset

# --- review ---
{ review APPROVED IMPLEMENTED; } > "$SP"; expect "review senza piano" "^STOP — sezione di review senza piano"
{ above; plan DRAFT; review APPROVED IMPLEMENTED; } > "$SP"; expect "piano riaperto dopo la review" "^STOP — piano riaperto"
{ above; plan APPROVED; printf '%s\n' "## Review implementazione" "Qualcosa di legacy."; } > "$SP"; expect "review legacy senza stati" "^REVIEW — sezione di review legacy"
{ above; plan APPROVED; review "NEEDS HUMAN DECISION" PLANNED; } > "$SP"; expect "Review NHD" "^STOP — Review status: NEEDS HUMAN DECISION"
{ above; plan APPROVED; review NEEDS_CHANGES PLANNED; } > "$SP"; expect "NEEDS_CHANGES" "^FIX"
esito 9-review "ESITO FASE review: OK" "x"; esito 10-fix "ESITO FASE fix: OK — risolto" "$(state)"
expect "fix OK (ordinamento numerico: 10 dopo 9)" "^REVIEW — correzione finita \(10-fix\)"
: > "$RUN/log/11-review.jsonl"; expect "review lanciata e mai partita dopo il fix (lock, crash): resta REVIEW" "^REVIEW — correzione finita \(10-fix\)"
sed -i 's/^Review rounds: 1\/3/Review rounds: 2\/3/' "$SP"; expect "una review ha scritto dopo il fix (stato cambiato)" "^FIX"
# budget dei fix calcolato (harness-pt08)
sed -i 's/^Review rounds: 2\/3/Review rounds: 3\/3/' "$SP"; expect "budget esaurito: 3/3 → STOP" "^STOP — budget dei fix esaurito \(Review rounds 3/3"
sed -i 's/^Review rounds: 3\/3 · post-approval NEEDS_CHANGES: 0\/1/Review rounds: 1\/3 · post-approval NEEDS_CHANGES: 1\/1/' "$SP"
expect "budget esaurito: post-approval 1/1 → STOP" "^STOP — budget dei fix esaurito .*post-approval NEEDS_CHANGES 1/1"
sed -i '/^Review rounds:/d' "$SP"; expect "riga Review rounds assente → STOP" "^STOP — budget dei fix non calcolabile"
reset
{ above; plan APPROVED; review NEEDS_CHANGES PLANNED; } > "$SP"
esito 03-review "ESITO FASE review: OK" "x"; esito 04-fix "ESITO FASE fix: OK — ok" "$(state)"; rjson 04-fix fix OK '["finding F2 chiuso diversamente"]' nessuno
expect "fix con deviazioni dichiarate → STOP, non REVIEW" "^STOP — 04-fix: deviazioni dichiarate"
reset
{ above; plan APPROVED; } > "$SP"; with_basis
esito 02-implement "ESITO FASE implement: OK — fatto" "$(state)"; : > "$RUN/log/03-review.jsonl"
expect "implement OK, review mai partita: resta REVIEW (non IMPLEMENT)" "^REVIEW — implementazione finita"
reset
{ above; plan APPROVED; review APPROVED NEEDS_VERIFICATION; } > "$SP"; expect "NEEDS_VERIFICATION" "^REVIEW — NEEDS_VERIFICATION"
{ above; plan APPROVED; review APPROVED PLANNED; } > "$SP"; expect "combinazione impossibile" "^STOP — combinazione non riconosciuta"
{ above; plan APPROVED; review APPROVED IMPLEMENTED; } > "$SP"; expect "IMPLEMENTED senza snapshot (legacy)" "^DONE — sezione senza snapshot"

# --- IMPLEMENTED: freschezza del codice ---
printf 'due\n' > src/a.py
snap=$(bash "$RS" snapshot); B=$(printf '%s\n' "$snap" | sed -n 's/^Base: //p'); T=$(printf '%s\n' "$snap" | sed -n 's/^Tree: //p')
printf 'src/a.py\n' > "$O/scope"; FP=$(bash "$RS" fingerprint --tree "$T" --paths-file "$O/scope" | sed -n 's/^Fingerprint: //p')
SNAPL="Reviewed snapshot: base ${B:0:12} · tree ${T:0:12} · fingerprint $FP · 1 paths"
{ above; plan APPROVED; } > "$SP"; with_basis; C=$(bash "$PC" basis "$SP" | sed -n 's/^Basis: //p')
review APPROVED IMPLEMENTED "$SNAPL" "Reviewed contract: $C" >> "$SP"
expect "IMPLEMENTED + codice FRESH" "^DONE — codice uguale"
printf 'tre\n' > src/a.py; expect "IMPLEMENTED + file in scope cambiato" "^REVIEW — codice cambiato.*STALE"
printf 'due\n' > src/a.py; printf 'x\n' > src/b.py; expect "file escluso cambiato: resta DONE" "^DONE"
o=$(bash "$CS" "$SP"); printf '%s\n' "$o" | grep -q "EXCLUDED-CHANGED" && pass=$((pass + 1)) || { fail=$((fail + 1)); echo "FAIL [EXCLUDED-CHANGED stampato]"; }
git checkout -q -- src/b.py
sed -i 's/^Reviewed contract: .*/Reviewed contract: spec 000000000000 · plan 000000000000/' "$SP"
expect "contratto diverso dalla basis" "^REVIEW — spec o piano cambiati dopo la review"
sed -i 's/^Reviewed contract: .*/Reviewed contract: '"$C"'/' "$SP"; expect "controprova: contratto uguale" "^DONE"
# 13f (harness-pt08): nel nuovo regime DONE solo con una riga Finalize: IMPLEMENTED sullo snapshot attuale, non piu'
# vecchia della review. SFP = impronta del Reviewed snapshot come la scrive finalize.sh (sha256 del valore, 12 cifre).
SFP=$(printf '%s' "${SNAPL#Reviewed snapshot: }" | sha256sum | cut -c1-12)
mkdir -p "$RUN/evidence"
expect "nuovo regime (evidence/) senza Finalize → REVIEW, mai DONE" "^REVIEW — IMPLEMENTED non firmato da finalize.sh \(nessuna riga Finalize:\)"
sed -i "s/^Feature status: IMPLEMENTED\$/&\nFinalize: IMPLEMENTED — snapshot $SFP — firmato · $(date -u +%Y-%m-%dT%H:%M:%SZ)/" "$SP"
expect "  con Finalize: IMPLEMENTED sullo snapshot attuale → DONE" "^DONE — codice uguale"
# review a mano / --inline: nuovo Reviewed snapshot, nessun .jsonl nuovo, la vecchia Finalize sopravvive
cp "$SP" "$O/spec-prima"
# (base, tree e fingerprint restano quelli FRESH, altrimenti la riga 13 darebbe REVIEW per il codice e 13f non
# verrebbe mai raggiunta: cambia solo il resto del valore, come un'altra review sullo stesso albero)
sed -i 's/^Reviewed snapshot: .* · 1 paths$/& (review inline)/' "$SP"
expect "vecchia Finalize: IMPLEMENTED + Reviewed snapshot cambiato, nessun .jsonl → REVIEW, non DONE" "^REVIEW — Finalize: firmata su un altro snapshot \(snapshot $SFP\)"
cp "$O/spec-prima" "$SP"
sed -i "s/^Finalize: IMPLEMENTED — snapshot $SFP/Finalize: IMPLEMENTED/" "$SP"
expect "  Finalize senza impronta dello snapshot → REVIEW" "^REVIEW — riga Finalize: senza l'impronta dello snapshot"
cp "$O/spec-prima" "$SP"
mkdir -p "$RUN/log"; : > "$RUN/log/07-review.jsonl"; touch -d '2000-01-01' "$RUN/log/07-review.jsonl"
expect "  Finalize piu recente dell'ultima review → DONE" "^DONE"
sed -i "s/^Finalize: .*/Finalize: IMPLEMENTED — snapshot $SFP — vecchio · 2001-01-01T00:00:00Z/" "$SP"; touch "$RUN/log/07-review.jsonl"
expect "  Finalize piu vecchia dell'ultima review (finalize non ripartito) → REVIEW" "^REVIEW — Finalize: piu' vecchia dell'ultima review lanciata \(07-review\)"
sed -i 's/^Finalize: .*/Finalize: NEEDS_VERIFICATION — tests-fe: FAIL · 2001-01-01T00:00:00Z/' "$SP"
expect "  Finalize non IMPLEMENTED → REVIEW" "^REVIEW — IMPLEMENTED non firmato da finalize.sh \(Finalize: NEEDS_VERIFICATION"
rm -rf "$RUN/evidence"; expect "  senza evidence/ ne' result.json (vecchio regime) → DONE come prima" "^DONE"
echo '{}' > "$RUN/log/02-implement.result.json"; expect "nuovo regime anche da un *.result.json → REVIEW" "^REVIEW — IMPLEMENTED non firmato"
mv "$RUN/log/02-implement.result.json" "$RUN/log/02-implement.result.json.visto"
expect "nuovo regime anche da un *.result.json.visto (dopo il recupero) → REVIEW" "^REVIEW — IMPLEMENTED non firmato"
sed -i '/^Finalize:/d' "$SP"; rm -rf "$RUN"; expect "run dir vecchia, nessuna Finalize → DONE come prima" "^DONE"
# X1: un file toccato dalla feature (touched.txt) fra gli esclusi → STOP, anche se tutto il resto darebbe DONE
mkdir -p "$RUN"; printf 'src/a.py\nsrc/b.py\n' > "$RUN/touched.txt"
expect "file toccato fra gli esclusi → STOP" "^STOP — la review ha escluso un file toccato dalla feature: src/b.py"
printf 'src/a.py\n' > "$RUN/touched.txt"; expect "controprova: touched solo in Scope → DONE" "^DONE"
printf 'src/b.pyc\n' > "$RUN/touched.txt"; expect "controprova: match esatto, non per prefisso" "^DONE"
rm -rf "$RUN"
sed -i 's/^Review status: APPROVED/Review status: NEEDS HUMAN DECISION/; s/^Reviewed contract: .*/Reviewed contract: spec 000000000000 · plan 000000000000/' "$SP"
expect "NHD vince sul contratto cambiato" "^STOP — Review status: NEEDS HUMAN DECISION"
# una riga di stato dentro un recinto nella review non conta
{ above; plan APPROVED; printf '%s\n' "## Review implementazione" '```text' "Review status: APPROVED" "Feature status: IMPLEMENTED" '```'; } > "$SP"
expect "stati dentro un recinto non contano" "^REVIEW — sezione di review legacy"
reset

# --- catene (harness-pt12): madre, anelli nello stesso working tree, L6, chiusura ---
CW=.claude/.ai-workflow; MA=$CW/spec-m.md; RA=$CW/spec-m-1-a.run; RB=$CW/spec-m-2-b.run; RM=$CW/spec-m.run
KA=$CW/spec-m-1-a.md; KB=$CW/spec-m-2-b.md
printf '%s\n' "# M" "Figlie: spec-m-1-a, spec-m-2-b" "## Requisiti funzionali" "1. RF1 — a" "2. RF2 — b" > "$MA"
ring() { # $1 spec, $2 Plan status, $3 file citato dal piano
  { printf '%s\n' "# Anello" "Dipende da: x" "Interfaccia per: nessuna" "## Requisiti funzionali" "1. RF1 — a"
    printf '%s\n' "## Piano di implementazione" "Plan status: $2" "Test level: std" "Superfici a rischio: nessuna" "### Passi" "1. Modificare \`$3\`."; } > "$1"
}
# EFP: impronta del Reviewed snapshot vuoto (la fixture non ne ha uno), come la scrive finalize.sh
EFP=$(printf '' | sha256sum | cut -c1-12)
closed() { # $1 spec, $2 Scope, $3 Excluded, [$4 senza-finalize] — anello chiuso = Finalize: IMPLEMENTED fresca
  local fz="Finalize: IMPLEMENTED — snapshot $EFP — firmato · $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  [ "${4:-}" = senza-finalize ] && fz=""
  printf '%s\n' "## Review implementazione" "Review status: APPROVED" "Feature status: IMPLEMENTED" ${fz:+"$fz"} "Verification: VERIFIED" \
  "Review rounds: 1/3 · post-approval NEEDS_CHANGES: 0/1" "" "<details><summary>Manifest</summary>" "" "Scope:" "$2" "" "Excluded:" "$3" "" "</details>" >> "$1"; }
out_has() { # $1 spec, $2 descrizione, $3 regex su una riga dell'output
  local out; out=$(bash "$CS" "$1" 2>&1)   # prima l'output: grep -q in pipe con pipefail darebbe SIGPIPE
  if printf '%s\n' "$out" | grep -Eq -- "$3"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL [$2] manca /$3/"; printf '%s\n' "$out" | sed 's/^/    /'; fi
}
ring "$KA" DRAFT src/a.py; printf '%s\n' "# Anello 2" "Dipende da: spec-m-1-a" "Interfaccia per: nessuna" > "$KB"
SP=$MA; expect "madre, anello 1 aperto → WAIT sull'anello" "^WAIT — catena: anello 1/2 \(spec-m-1-a\) non chiuso"
SP=$KB; expect "anello 2 senza piano, piano di 1 in DRAFT → WAIT (L6)" "^WAIT — catena: il piano dell'anello 2 parte quando il piano dell'anello 1 \(spec-m-1-a\) e' APPROVED"
ring "$KA" APPROVED src/a.py; SP=$KA; with_basis
SP=$KB; expect "piano di 1 APPROVED → il piano di 2 parte mentre 1 implementa (L6)" "^PLAN — nessun piano"
ring "$KB" APPROVED src/b.py; with_basis
expect "anello 2 approvato, anello 1 aperto → WAIT: l'implement aspetta" "^WAIT — catena: l'implement dell'anello 2 aspetta l'anello 1"
SP=$KA; expect "anello 1: una spec normale → IMPLEMENT" "^IMPLEMENT"
# l'anello 1 chiude: il suo lavoro (src/a.py) resta nel working tree, il commit e' dell'utente
printf 'uno-anello1\n' > src/a.py
mkdir -p "$RA/log"; printf 'src/a.py\n' > "$RA/touched.txt"; bash "$RS" tree > "$RA/log/02-implement.post-tree"
closed "$KA" src/a.py "" senza-finalize
SP=$MA; expect "B1: anello 1 APPROVED+IMPLEMENTED senza Finalize → la madre resta in WAIT su di lui" "^WAIT — catena: anello 1/2 \(spec-m-1-a\) non chiuso"
SP=$KB; expect "B1: anello 1 senza Finalize → l'implement dell'anello 2 aspetta" "^WAIT — catena: l'implement dell'anello 2 aspetta l'anello 1"
sed -i "s/^Feature status: IMPLEMENTED\$/&\nFinalize: IMPLEMENTED — snapshot 000000000000 — vecchia · $(date -u +%Y-%m-%dT%H:%M:%SZ)/" "$KA"
SP=$MA; expect "B1: Finalize su un altro snapshot → la madre resta in WAIT" "^WAIT — catena: anello 1/2 \(spec-m-1-a\) non chiuso"
SP=$KB; expect "B1: Finalize su un altro snapshot → l'anello 2 aspetta" "^WAIT — catena: l'implement dell'anello 2 aspetta l'anello 1"
sed -i "s/snapshot 000000000000 — vecchia/snapshot $EFP — firmato/" "$KA"
SP=$MA; expect "madre: anello 2 ancora aperto → WAIT" "^WAIT — catena: anello 2/2 \(spec-m-2-b\) non chiuso"
SP=$KB; expect "anello 1 chiuso, tree = .post-tree di 1 → IMPLEMENT" "^IMPLEMENT"
out_has "$KB" "file dell'anello precedente: stessa catena, non altri flussi" "^Anelli precedenti: src/a.py — stessa catena, anello precedente"
out_has "$KB" "base dell'anello = .post-tree dell'anello 1" "^Base anello: $(cat "$RA/log/02-implement.post-tree")$"
printf 'src/a.py\nsrc/b.py\n' > "$RA/touched.txt"
expect "L6: file citato da 2 nel touched.txt di 1 (approvato mentre 1 implementava) → STALE, giro delta" "^STOP — spec o piano cambiati .*STALE \(touched: src/b.py\)"
printf 'src/a.py\n' > "$RA/touched.txt"
printf 'mano umana\n' > src/b.py
expect "anello 2 all'avvio con il tree diverso dal .post-tree di 1 → STOP" "^STOP — catena: il working tree .* non e' il .post-tree dell'anello 1"
git checkout -q -- src/b.py; expect "  controprova: tree riportato com'era → IMPLEMENT" "^IMPLEMENT"
# l'anello 2 lavora: la sua superficie e' solo il suo diff, non quello dell'anello 1
mkdir -p "$RB/log"; bash "$RS" tree > "$RB/log/03-implement.pre-tree"; printf 'altro-anello2\n' > src/b.py
out_has "$KB" "la review dell'anello 2 vede solo il suo diff (base = .post-tree di 1, mai HEAD)" "^Diff anello: src/b.py$"
printf 'mano umana dopo\n' > src/c.py
expect "anello gia' partito (.pre-tree): il controllo del tree non si ripete" "^IMPLEMENT"
rm -f src/c.py
bash "$RS" tree > "$RB/log/03-implement.post-tree"; printf 'src/b.py\n' > "$RB/touched.txt"
closed "$KB" src/b.py src/a.py
expect "anello 2: la review esclude src/a.py (anello precedente, non nel suo touched.txt) → DONE, nessuno STOP" "^DONE"
SP=$MA; expect "anelli chiusi, nessuna chiusura → CHIUSURA (la madre non e' IMPLEMENTED)" "^CHIUSURA — 2 anelli chiusi"
mkdir -p "$RM"; printf 'src/a.py\nsrc/b.py\n' > "$RM/touched.txt"
printf 'Chiusura: NEEDS_VERIFICATION — gates FAIL · 2026-09-29T00:00:00Z\n' > "$RM/chiusura.txt"
expect "chiusura non riuscita → STOP col recupero" "^STOP — chiusura della catena non riuscita .*chiusura.txt.visto"
printf 'Chiusura: IMPLEMENTED — base %s · tree %s · gates PASS · e2e non richiesto · 2026-09-29T00:00:00Z\n' "$(git rev-parse HEAD)" "$(bash "$RS" tree)" > "$RM/chiusura.txt"
expect "chiusura IMPLEMENTED sul codice attuale → DONE" "^DONE — catena chiusa"
printf 'cambiato dopo\n' > src/a.py; expect "codice della catena cambiato dopo la chiusura → CHIUSURA" "^CHIUSURA — codice della catena cambiato"
rm -rf "$RA" "$RB" "$RM" "$MA" "$KA" "$KB"; SP=.claude/.ai-workflow/spec-x.md; reset

# --- riga 7t: fase test-red (harness-pt11), solo formato 2, fra piano APPROVED e implement ---
plan2() { # $1 Plan status — piano in formato 2 con un test di accettazione nuovo
  printf '%s\n' "## Piano di implementazione" "Plan format: 2" "Plan status: $1" "Test level: std" "Superfici a rischio: nessuna" \
    "### File toccati" "- \`src/a.py\`" "- \`src/test_a.py\` (nuovo)" "### Passi" "#### Blocco B1 — x" "scrive: \`src/a.py\`" "dopo: nessuno" "" \
    "| id | file | modifica | test |" "|---|---|---|---|" "| P1 | \`src/a.py\` | x | T1 |" \
    "### Tracciabilità requisiti" "| Req | Passi del piano | Verifica |" "|---|---|---|" "| RF1 | P1 | T1 |" \
    "### Piano di test" "| ID | requisito | file | asserzione | mutazione |" "|---|---|---|---|---|" \
    "| T1 | RF1 | \`src/test_a.py::test_a\` (nuovo) | rosso se: \`assert 1 == 2\` | — |" "### Changelog revisione piano" "- giro 1: ok"
}
{ above; plan2 APPROVED; } > "$SP"; with_basis
expect "formato 2 approvato, nessuna fase → TEST-RED" "^TEST-RED — piano in formato 2 approvato"
{ above; plan APPROVED; } > "$SP"; with_basis
expect "formato 1 approvato → IMPLEMENT (niente test-red)" "^IMPLEMENT"
{ above; plan2 APPROVED; } > "$SP"; with_basis
esito 03-test-red "ESITO FASE test-red: STOP — test di accettazione non dimostrati: T1 verde" "$(state)"
expect "test-red STOP, stato invariato → STOP con la riga" "^STOP — 03-test-red: test di accettazione non registrati \(ESITO FASE test-red: STOP — .*T1 verde\).*esito\.visto"
mv "$RUN/log/03-test-red.esito" "$RUN/log/03-test-red.esito.visto"
expect "  recupero: .esito rinominato → TEST-RED di nuovo" "^TEST-RED"
printf 'def test_a():\n    assert 1 == 2\n' > src/test_a.py
bash "$PC" basis "$SP" --write-tests >/dev/null
esito 03-test-red "ESITO FASE test-red: OK — rossi dimostrati" "$(state)"
expect "test-red OK, impronta tests registrata → IMPLEMENT" "^IMPLEMENT — piano approvato"
printf 'def test_a():\n    assert True\n' > src/test_a.py
expect "test di accettazione cambiato dopo test-red → STOP (deviazione)" "^STOP — test di accettazione cambiati dopo la fase test-red"
printf 'def test_a():\n    assert 1 == 2\n' > src/test_a.py
esito 04-implement "ESITO FASE implement: OK — fatto" "$(state)"
expect "  poi implement OK → REVIEW come prima" "^REVIEW — implementazione finita \(04-implement\)"
reset; rm -f src/test_a.py
{ above; plan2 APPROVED; } > "$SP"; with_basis
esito 02-implement "ESITO FASE implement: OK — fatto" "$(state)"
expect "formato 2 gia' implementato senza test-red (ciclo avviato prima): REVIEW come prima" "^REVIEW — implementazione finita \(02-implement\)"
reset

# --- riga 0: impronta del harness (pt03; pk04a-2: la decide run-phase.sh --harness-fp-confronta), solo sopra le fasi
# da lanciare. Le mutazioni si fanno su una COPIA del plugin: MAAT_ROOT per cycle-state.sh e FIC_DRIVER_ROOT per
# `driver.py next` (porting in driver.test.sh, sezione 9: i due devono stampare lo stesso percorso nel rimedio).
unset FIC_REPO   # il repository e' quello della spec, non quello di una fase che ospita il test
HPC="$O/plug/maat"; mkdir -p "$O/plug" && cp -r "$HERE/.." "$HPC" && find "$HPC" -name __pycache__ -type d -prune -exec rm -rf {} +
HPC_M=$(cygpath -m "$HPC" 2>/dev/null || printf '%s' "$HPC")
fdr_prima=${FIC_DRIVER_ROOT-__non_impostata__}
export MAAT_ROOT="$HPC" FIC_DRIVER_ROOT="$HPC"
hfp() { bash "$HERE/run-phase.sh" --harness-fp "$W" > "$RUN/harness.fp"; }
RIM="bash \"$HPC_M/scripts/run-phase\.sh\" --harness-fp > \"[^\"]*harness\.fp\""
{ above; plan APPROVED; } > "$SP"; with_basis; mkdir -p "$RUN"; hfp
expect "harness invariato → la riga della tabella" "^IMPLEMENT"
printf '#' >> "$HPC/scripts/context-pack.sh"
expect "harness cambiato → STOP con data e rimedio a percorso assoluto" "^STOP — harness cambiato dal [0-9T:-]+Z \(impronta registrata [0-9a-f]{12}, attuale [0-9a-f]{12}\): ricomincia la fase o conferma\. Rimedio: se il cambio e' voluto, $RIM e riprendi \(prossima fase: IMPLEMENT\)"
hfp; expect "controprova: impronta confermata → IMPLEMENT" "^IMPLEMENT"
echo x | sha256sum | cut -c1-64 > "$RUN/harness.fp"
expect "harness.fp di formato precedente → STOP col rimedio" "^STOP — impronta di formato precedente: ciclo iniziato col harness interno \(impronta registrata [0-9a-f]{12} dal [0-9T:-]+Z, attuale [0-9a-f]{12}\)\. Rimedio: .*$RIM e riprendi \(prossima fase: IMPLEMENT\)"
: > "$RUN/harness.fp"
expect "harness.fp vuoto → STOP illeggibile col rimedio" "^STOP — harness\.fp illeggibile \(vuoto o senza impronta, registrato dal [0-9T:-]+Z; attuale [0-9a-f]{12}\)\. Rimedio: .*$RIM e riprendi \(prossima fase: IMPLEMENT\)"
echo 0000 > "$RUN/harness.fp"
expect "harness.fp con 0000 → lo stesso STOP" "^STOP — harness\.fp illeggibile \(vuoto o senza impronta.*$RIM"
hfp; expect "controprova: impronta riconfermata → IMPLEMENT" "^IMPLEMENT"
printf '#' >> "$HPC/scripts/context-pack.sh"; rm -f "$RUN/harness.fp"
expect "senza harness.fp (ciclo vecchio) nessun controllo" "^IMPLEMENT"
echo 0000 > "$RUN/harness.fp"
{ above; plan APPROVED; review APPROVED IMPLEMENTED; } > "$SP"; expect "harness cambiato ma ciclo DONE → resta DONE" "^DONE"
{ above; plan "NEEDS HUMAN DECISION"; } > "$SP"; expect "harness cambiato ma STOP della tabella → resta quello" "^STOP — decisione aperta"
unset MAAT_ROOT
if [ "$fdr_prima" = __non_impostata__ ]; then unset FIC_DRIVER_ROOT; else export FIC_DRIVER_ROOT="$fdr_prima"; fi
reset

echo "cycle-state.test.sh: $pass passati, $fail falliti"
[ $fail -eq 0 ]
