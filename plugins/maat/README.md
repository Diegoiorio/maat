# Maat — scheda del plugin

Maat — Multi-Agent Assurance Toolkit: ciclo di piano, implementazione, review e firma, con prove, misure e guardia.
Versione in `.claude-plugin/plugin.json`; novità in `CHANGELOG.md` alla radice del repo.

Installazione, dalla cartella principale del progetto:

```bash
claude plugin marketplace add https://github.com/Diegoiorio/maat.git#v1.1.0 --scope project
claude plugin install maat@maat --scope project
```

**Configurazione, uso, aggiornamento e piattaforme:** nel [README del repo](../../README.md). Qui c'è solo cosa
contiene il plugin.

| cartella | contenuto |
|---|---|
| `skills/` | `/maat:full-implementation-cycle`, `/maat:plan-review-cycle`, `/maat:plan-review-cycle-light`, `/maat:implementation-review-cycle`, `/maat:setup` |
| `agents/` | `spec-author`, `spec-plan-reviewer`, `spec-plan-reviewer-light`, `acceptance-test-writer`, `plan-implementer`, `implementation-reviewer` (con il prefisso `maat:`) |
| `scripts/` | driver, fasi, gate, firma, guardia, copia WSL, controprove, lettore di `maat.json`, doctor; ogni script ha la sua suite `*.test.sh` accanto |
| `hooks/` | la guardia di sessione (`PreToolUse` su Bash e PowerShell) |
| `schemas/` | schema di `.claude/maat.json` e dell'esito delle fasi |
| `profiles/` | moduli pronti per gli stack comuni, usati da `/maat:setup` |
| `examples/` | due `maat.json` completi: `nuxt-fastapi` (Nuxt + FastAPI, con WSL) e `bash-node` (bash e Node, senza test) |
| `docs/` | regole di scrittura per le descrizioni dei comandi |
| `assets/` | logo e icone (fonte unica: `assets/genera.py`) |

Dentro una skill la radice del plugin è `${CLAUDE_PLUGIN_ROOT}`; negli script è `MAAT_ROOT`. Il plugin non riceve mai
file del progetto: tutto ciò che dipende dal progetto sta in `.claude/maat.json` del progetto.

Diagnosi in sola lettura: `bash <radice del plugin>/scripts/maat-doctor.sh` (`--piattaforma` stampa `windows-wsl`,
`windows-senza-wsl` o `altro`; `--prova-test` lancia anche un test per modulo ed esce dalla sola lettura).

Guida ai flussi: `docs/GUIDA-FLUSSI.html` del repo. Test del plugin: `docs/TESTING-harness.md` del repo.
