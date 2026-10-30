---
name: setup
description: Configurazione guidata di Maat in un progetto (/maat:setup). Riconosce lo stack in sola lettura, propone moduli e profili, chiede solo ciò che non si deduce (produzione, rilascio, involucri, verifica remota, percorsi da non toccare), scrive .claude/maat.json dopo la conferma, prova la guardia e lancia maat-doctor.sh.
allowed-tools: Read, Write, Glob, Grep, Bash
argument-hint: "(nessun argomento: lanciala dalla radice del progetto)"
---

# /maat:setup

Radice del plugin: `${CLAUDE_PLUGIN_ROOT}`. Nei file di questa skill che leggi con Read, `${CLAUDE_PLUGIN_ROOT}` vale questo percorso: sostituiscilo prima di eseguire un comando.

Prima di ogni comando Bash o PowerShell, scrivi `description` secondo `${CLAUDE_PLUGIN_ROOT}/docs/descrizione-comandi.md`.

Gira nella **sessione principale**, con l'utente. Obiettivo (R5): dopo i due comandi d'installazione, un
`.claude/maat.json` valido e `maat-doctor.sh` senza MANCA, senza modifiche a mano.

Regole ferme:
- **Nessun file del progetto si scrive prima della conferma** del passo 4. I passi 1–3 sono in sola lettura
  (Read, Glob, Grep, comandi che non scrivono).
- Una domanda alla volta, con una proposta già pronta: l'utente conferma o corregge.
- Il Python del plugin si trova con `python.sh` (`bash -c '. "${CLAUDE_PLUGIN_ROOT}/scripts/python.sh" && "$FIC_PY" …'`),
  come nei comandi sotto: mai un `python` del PATH scelto a caso.

## 1. Riconoscimento dello stack (sola lettura)

Cerca, dalla radice del repo (escludi `node_modules`, `.venv`, `.git` e le cartelle generate):
- `package.json`: dipendenze `nuxt`, `vitest`, `jest`, lo script `test`;
- `pyproject.toml`, `requirements*.txt`, `pytest.ini`/`conftest.py`, `pytest` fra le dipendenze;
- cartelle `tests/`, file `*.test.*` e `*.spec.*`, script `*.sh`;
- workspace: `turbo.json`, `pnpm-workspace.yaml`, `workspaces` in un `package.json`. Il workspace dà le radici dei
  moduli candidate (le sue app e i suoi pacchetti) e la **cartella del workspace** (dove stanno `node_modules` e il
  `package.json` col campo `workspaces`), che serve al passo 2 come `radice_pacchetti`.

Poi la piattaforma, che decide l'ambiente dei moduli:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/maat-doctor.sh --piattaforma
```

Stampa `windows-wsl`, `windows-senza-wsl` o `altro` (Windows lo decide `uname`, non la presenza di `wsl.exe`; WSL
assente = `wsl.exe` fuori dal PATH oppure `wsl -- true` che fallisce). Solo con `windows-wsl` i profili restano come
sono; altrimenti il passo 2 usa `--nativo`.

## 2. Proposta: moduli e profili

Profili del plugin (`${CLAUDE_PLUGIN_ROOT}/profiles/`):

| Segnale trovato al passo 1 | Profilo |
|---|---|
| `package.json` con `nuxt` e `vitest` | `nuxt-vitest` |
| Python con `pytest` (`requirements*.txt` o `pyproject.toml`) | `fastapi-pytest` |
| `package.json` senza framework (eventuali `*.test.js` con `node --test`) | `node-semplice` |
| nessuna suite (solo script, JSON, configurazioni) | `generico-senza-test` |

Componi la proposta (un `--radice <modulo>=<percorso>` per profilo, nello stesso ordine):

```bash
bash -c '. "${CLAUDE_PLUGIN_ROOT}/scripts/python.sh" && "$FIC_PY" "$@"' _ ${CLAUDE_PLUGIN_ROOT}/scripts/maat-config.py componi <profilo>… --radice <modulo>=<percorso>… [--nativo]
```

- **`--nativo`** se il passo 1 non ha dato `windows-wsl`: `componi` mette `ambiente: nativo` a ogni modulo, toglie
  `copia`, pone `piattaforma.copia_wsl: no` e fa girare nel repo i comandi che prima passavano dalla copia WSL. Dillo
  all'utente con il motivo («WSL non raggiungibile» oppure «piattaforma non Windows»).
- **Lint con alternative (`copia.lint` come lista):** con `--nativo` `componi` sceglie la prima alternativa senza
  `se_esiste` o il cui file `se_esiste` esiste nel progetto (relativo alla sua cartella), quindi lancia `componi`
  dalla radice del progetto. Nella tabella di conferma controlla tu: se nella radice del modulo esiste il file di un
  `se_esiste` del profilo (es. `lint-baseline.mjs` di `nuxt-vitest`) e il lint proposto non è quello della sua
  alternativa, proponi all'utente il comando di quell'alternativa (senza `{cache?…}`).
- `componi` stampa il JSON e non scrive niente.

Mostra la **tabella di conferma**, una riga per modulo:

| Modulo | Radice | radice_pacchetti | Profilo | Ambiente | Comando di test |
|---|---|---|---|---|---|

- **`radice_pacchetti`:** `componi` la pone uguale a `radice`. Chiedila per ogni modulo, proponendo la cartella del
  workspace trovata al passo 1 (es. `frontend` per il modulo `frontend/apps/web`); senza workspace resta `radice`.
- **Ambiente:** `wsl` solo se il passo 1 ha dato `windows-wsl` e il profilo lo chiede; altrimenti `nativo`, con
  `piattaforma.copia_wsl: no`.
- L'utente conferma o corregge (nomi, radici, profili, comandi). Una correzione si applica al JSON in memoria e la
  tabella si rimostra.

## 3. Domande solo su ciò che non si deduce

Una alla volta, ognuna con «nessuno» come risposta ammessa:

1. **Host e domini di produzione.** Dalla stessa risposta scrivi:
   - in `guardia.produzione` una regex per voce, con i punti protetti (`www\.esempio\.it`) e senza distinzione di
     maiuscole (la applica la guardia);
   - in `guardia.sonde` gli host **letterali** (`www.esempio.it`): sono le sonde che provano la guardia. Ogni sonda
     deve corrispondere ad almeno una regex, e ogni regex di host deve avere la sua sonda.
2. **Script di rilascio** (`guardia.rilascio`): percorsi relativi al repo, sempre negati.
3. **Involucri di accesso remoto** (`guardia.involucri`): script che incapsulano ssh o la copia remota, con le
   eventuali opzioni da negare (`{script, opzioni_negate}`).
4. **Script di suite del progetto** (`guardia.suite`): script che lanciano l'intera suite (es. `run_tests.sh`), con
   le regole di selezione `pytest` o `vitest`.
5. **Verifica remota** (`verifica_remota`): sì/no e il comando. Senza, il ciclo usa `--no-dev`.
6. **Percorsi da non toccare** (`da_non_toccare`): glob.

## 4. Scrittura di `.claude/maat.json`

- Se il file **non esiste**: mostra il JSON completo e chiedi conferma.
- Se **esiste già**: scrivi la proposta in un file temporaneo **fuori dal repo** e mostra il diff
  (`git diff --no-index -- .claude/maat.json <file temporaneo>`); chiedi conferma prima di sovrascrivere.
- Solo dopo il «sì»: scrivi `.claude/maat.json`, crea la cartella di lavoro (`cartelle.lavoro`, default
  `.claude/.ai-workflow`) se manca, poi valida:

```bash
bash -c '. "${CLAUDE_PLUGIN_ROOT}/scripts/python.sh" && "$FIC_PY" "$@"' _ ${CLAUDE_PLUGIN_ROOT}/scripts/maat-config.py valida
```

Un errore di `valida` si corregge nel file (mostrando la correzione all'utente) e si rivalida: non si va avanti con
un file non valido.

## 5. Prova delle regole di guardia

Per **ogni** host di `guardia.sonde`: il comando finto `curl -s https://<host>/` deve dare **ask** dalla guardia di
sessione. Il JSON della prova va in un file temporaneo **fuori dal repo**, scritto con Write (così l'host non compare
nel comando, che altrimenti la guardia vera ti chiederebbe di confermare):

```json
{"tool_name": "Bash", "tool_input": {"command": "curl -s https://<host>/"}}
```

```bash
bash -c '. "${CLAUDE_PLUGIN_ROOT}/scripts/python.sh" && MAAT_CONFIG="$(pwd -W 2>/dev/null || pwd)/.claude/maat.json" "$FIC_PY" "${CLAUDE_PLUGIN_ROOT}/scripts/guard.py" --universal < "$1"' _ <file temporaneo>
```

L'uscita deve contenere `"permissionDecision": "ask"`. Un host che passa senza ask vuol dire una regex che non lo
copre: correggi `guardia.produzione` (passo 4) e riprova.

## 6. `maat-doctor.sh`

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/maat-doctor.sh
```

In sola lettura. Ogni MANCA ha il suo rimedio dopo « — »: applicalo con l'utente (o spiegalo, se è un'installazione
che fa lui) e rilancia il doctor. Le ATTENZIONE si riferiscono, non bloccano. `--prova-test` lancia anche un test per
modulo, ma esce dalla sola lettura (cache e coverage): proponilo, non lanciarlo senza il sì dell'utente.

## 7. Riassunto da incollare in `CLAUDE.md`

Cinque righe, **mostrate e non scritte** (le incolla l'utente, se vuole):

```text
Maat <versione del plugin> — configurazione: .claude/maat.json (moduli: <nomi>; guardia: <n> regole di produzione).
Diagnosi in sola lettura: bash <radice del plugin>/scripts/maat-doctor.sh
Piano e revisione: /maat:plan-review-cycle (o -light) su una spec in <cartella di lavoro>.
Implementazione e firma: /maat:full-implementation-cycle <spec>.
Revisione di un'implementazione: /maat:implementation-review-cycle <spec>.
```

La versione viene da `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`.
