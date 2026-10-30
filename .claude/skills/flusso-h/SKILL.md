---
name: flusso-h
description: Flusso H — implementa UNO dei piani già approvati di Maat (docs/piani/maat-pkNN-*.md di questo repo) su un branch di lavoro del repo maat, con gli agenti maat:plan-implementer e maat:implementation-reviewer di una versione fissa (plugin installato da un tag), i test del plugin, il collaudo di rilasciabilità, un commit sul branch e la revisione dei piani successivi. NON usa /maat:full-implementation-cycle (le sue sotto-sessioni caricherebbero il plugin in corso di modifica). Accetta uno o più piani in sequenza; il primo STOP ferma la catena.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, BashOutput, Agent, Monitor, TaskStop
argument-hint: "pkNN [pkMM …]"
---

# Flusso H — implementazione dei piani di Maat

Input: `$ARGUMENTS` — uno o più identificativi di piano (`pk10`, `maat-pk10`, o il percorso del file). Più piani si
eseguono **in sequenza, nell'ordine dato**; il primo STOP ferma tutti i successivi.

**Dove si lancia.** Da dentro la cartella del repo maat: `cd <repo maat>` e poi `claude`, poi `/flusso-h pkNN`. La skill
è di questo repo (`.claude/skills/flusso-h/`), non del plugin: altrove non esiste. **Non** si lancia con `claude
--plugin-dir <repo maat>/plugins/maat`: `--plugin-dir` serve a provare a mano, non a lanciare i cicli (vedi il passo 1).

**È uno strumento per chi sviluppa Maat**, non per chi lo usa. I piani sono note di lavoro del maintainer e **non
sono pubblicati**: si scrivono in `docs/piani/` della propria copia del repo (`maat-pkNN-<titolo>.md`; la cartella la
crea il primo piano). Sono **già approvati**: niente fase di pianificazione, niente riscrittura del piano. La sezione
«Note da piani precedenti», se c'è, **prevale** sui passi che corregge. Una deviazione dal piano è uno STOP per
l'utente.

**Progetto guida** (o banco di prova): un progetto reale che usa Maat, con cicli già chiusi, su cui si collauda ogni
modifica. Si lavora sempre su una sua copia, mai sul progetto vero.

## Perché non `/maat:full-implementation-cycle`

Le sue sotto-sessioni caricano il plugin abilitato nel progetto. Se quel plugin è proprio il codice in modifica (un
marketplace da cartella o `--plugin-dir` sul branch), il ciclo cambierebbe sotto i propri piedi: è l'incidente del
harness cambiato sotto un ciclo (misure di quattro cicli falsate). Nel flusso H il harness in modifica viene **testato**,
mai **usato** per implementarsi: gli agenti vengono da una versione **fissa** (il plugin installato da un tag), mai
dalla cartella del branch. Il passo 1 lo controlla.

## Regole ferme

- Si lavora **solo su un branch di lavoro** del repo maat (per esempio `wip/pkNN`, meglio in un worktree
  `../maat-pkNN`), mai su `main`. Un worktree collegato e il tree principale non si mescolano: ognuno fa le sue cose.
- Commit **solo** sul branch di lavoro, uno per piano chiuso. **Mai** push, **mai** merge su `main`, **mai** tag
  pubblicati, **mai** `git reset --hard`/`rebase`/`stash`: push, tag e integrazione li fa solo l'utente.
- Il **banco di prova** è il progetto guida: rigiochi e collaudi si fanno su una sua **copia** (un clone in una
  cartella temporanea, con le run dir dei cicli chiusi), mai sul suo tree, che resta in sola lettura. Nessun accesso
  alla produzione, nessun sync verso ambienti remoti, nessuna scrittura su DB, nessuna installazione, salvo quelle che
  il piano autorizza esplicitamente o che l'utente conferma (il plugin al passo 1).
- **Mai la modalità fast** (`fastMode`) e nessuna leva che richieda spesa: decisione dell'utente.
- I rigiochi di collaudo girano con `--no-dev`.
- Scrivere file con Write/Edit, mai con heredoc Python (byte invisibili). Fine riga LF.

## I 9 passi (per ogni piano)

1. **Preparazione**
   - Se il worktree non esiste: `git worktree add ../maat-pkNN -b wip/pkNN main` dalla radice del repo maat; se esiste,
     entrarci e verificare che `git branch --show-current` sia il branch del piano.
   - Nessun ciclo vivo sulla copia del banco di prova: `cd <copia> && bash <repo maat>/plugins/maat/scripts/run-phase.sh
     --lock-status` deve dire `libero`, e nessun `.claude/.ai-workflow/spec-*.run/log/*.running` senza il suo `.exit`.
     Altrimenti: se il piano modifica file che quel ciclo usa, aspettare (Monitor) o STOP con il motivo.
   - **Il plugin di questa sessione viene da una versione fissa** (regola «il harness in modifica si testa, non si
     usa»). Controlli, tutti in sola lettura:
     - `~/.claude/plugins/installed_plugins.json` (fonte verificata in pk01, D6): la voce `maat` valida per questa
       cartella (scope `user`, oppure `project`/`local` con `projectPath` uguale alla cartella), con `version`,
       `installPath` e `gitCommitSha`. `claude plugin list --json` può dare lo stesso, ma il suo formato **non è
       ancora verificato**: in caso di dubbio vale il file. Gli agenti `maat:*` vengono da `installPath`, **tranne** con
       un marketplace da cartella: lì il codice gira dalla cartella sorgente (D6 f), che va quindi controllata come
       al punto seguente.
     - La sorgente del marketplace `maat` (`~/.claude/plugins/known_marketplaces.json` ed `extraKnownMarketplaces`
       nelle impostazioni del progetto): git o URL con il `ref` di un **tag** ⇒ va bene. **Cartella** ⇒ va bene solo se è
       una cartella bloccata al tag (`git -C <cartella> describe --exact-match --tags HEAD` riesce e `git -C <cartella>
       status --porcelain` è vuoto, come una cartella `maat-vX.Y.Z`) e non è né questo worktree né il tree principale del repo maat.
       `maat-doctor.sh` lo segnala con la riga ATTENZIONE «plugin installato da un marketplace da cartella»: quella riga
       chiede proprio questa verifica.
     - La riga di comando del processo `claude` di questa sessione (sola lettura: `ps -o args=` su Linux e Mac,
       `Get-CimInstance Win32_Process` su Windows) non contiene `--plugin-dir` verso il repo maat o un suo worktree.
       Se non si riesce a leggerla, chiederlo all'utente.

     **STOP** se il plugin viene dal branch in modifica (marketplace da cartella che punta al repo o a un suo worktree,
     `--plugin-dir` sul branch, `ref` che è un branch e non un tag) o se non è installato. Nel messaggio: il comando per
     installarlo da un tag e lo **scope**. Forma consigliata, **provata** il 2026-10-30 (installazione e passaggio a
     un tag nuovo): la sorgente GitHub con il tag, `claude plugin marketplace add
     https://github.com/Diegoiorio/maat.git#vX.Y.Z --scope local` e `claude plugin install maat@maat --scope local`.
     In alternativa, senza rete: una cartella bloccata al tag (`git -C <repo maat> worktree add --detach
     ../maat-vX.Y.Z vX.Y.Z`, poi `marketplace add <quella cartella>`). Lo scope consigliato è `local`, lanciato
     dalla cartella del repo maat: scrive in `.claude/settings.local.json` di questa cartella e in `~/.claude/plugins/` (cache,
     `installed_plugins.json`, `known_marketplaces.json`). `--scope user` scriverebbe invece in `~/.claude/settings.json`
     e varrebbe per tutti i progetti; `--scope project` in `.claude/settings.json` del repo, che è tracciato. Installare
     **si fa solo con la conferma dell'utente**, e l'installazione si dichiara nel rapporto (serve al collaudo, punto c).
   - **Guardia di sessione.** Se il plugin installato è abilitato in questa sessione, la sua guardia è agganciata
     (`maat-doctor.sh`: «guardia agganciata»). Se non lo è, dirlo nel rapporto e comportarsi comunque come se lo fosse:
     nessun comando fra quelli delle regole ferme.
   - **Annotare lo stato di partenza**, per il collaudo (passo 6, punti b e c): `git status --porcelain` e `git stash list`
     del tree del progetto guida; gli sha256 di `~/.claude/settings.json` e di `~/.claude/plugins/installed_plugins.json`,
     e le voci di `~/.claude/plugins/known_marketplaces.json` **senza** i campi di data dell'ultimo aggiornamento. Non
     tutta `~/.claude/plugins/`: Claude Code ci scrive da solo durante la sessione (cache, aggiornamento dei
     marketplace), e quelle scritture non sono un cambiamento del flusso.
2. **Prerequisiti**
   - Il piano deve avere la riga `**Plan status: APPROVED**`. Se manca (o dice altro) ⇒ STOP: «il piano non è
     approvato». Il flusso H non approva piani.
   - Leggere la riga `Prerequisiti:` del piano ed eseguire `git log --oneline --grep "pkXX"` sul branch per ciascuno. Uno
     mancante ⇒ STOP: «esegui prima pkXX».
   - Leggere tutta la sezione «Note da piani precedenti».
3. **Implementazione a blocchi** — dividere i «Passi di implementazione» in 1–3 blocchi coerenti (se il piano indica già
   i blocchi, si usano quelli) e lanciare un agente `maat:plan-implementer` per blocco, in ordine. A ciascuno passare:
   - il percorso del piano, precisando: «il piano è la sezione `## Passi di implementazione`; il requisito è tutto ciò
     che la precede, “Note da piani precedenti” comprese, che prevalgono; ignora i riferimenti a `spec-<name>.md` delle
     tue istruzioni»;
   - modalità `full` (o `completion` se il branch ha già modifiche di questo piano da un tentativo interrotto);
   - «Blocco k/N — sono tuoi solo i passi x–y»;
   - «i gate sono i test del plugin: le suite dei file che tocchi e quelle nuove del piano (sezione `## Test`), lanciate
     come dice `docs/TESTING-harness.md`; non le suite di un progetto, salvo che il piano le nomini»;
   - il report del blocco precedente come orientamento (il codice vince sul report).

   Deviazione dal piano, `Bloccato su` diverso da `nessuno`, o secondo `PARZIALE` ⇒ STOP.
4. **Test del plugin**
   - Durante l'implementazione e le correzioni si lanciano **solo le suite dei file toccati** (e quelle che ne
     dipendono), una alla volta: `bash plugins/maat/scripts/<nome>.test.sh`. Sempre anche `genericita.test.sh` e
     `maat-paths.test.sh`.
   - **A fine piano, un giro completo** di tutte le suite del pacchetto (`plugins/maat/scripts/*.test.sh`,
     `plugins/maat/skills/**/*.test.sh` e `test-review-surface.sh`), su Windows e su Linux, come dice
     `docs/TESTING-harness.md` («Windows e Linux», «Il giro completo»): le lunghe (`cycle-state`, `run-phase`, `driver`)
     in parallelo in background, raccolte prima di decidere, oppure una alla volta come fa lo script del giro. La review
     legge gli esiti di quel giro e rilancia solo ciò che deve verificare.
   - Più i test nuovi del piano, con le loro **controprove per mutazione**: la mutazione si applica (su una copia), il
     test diventa rosso, la mutazione si toglie. Nel rapporto vanno il comando e l'esito.
   - Un rosso ⇒ correggere (un giro di `maat:plan-implementer` in `fix`) e ripetere; al secondo rosso sullo stesso test
     ⇒ STOP.
5. **Review indipendente** — agente `maat:implementation-reviewer` con: il piano (come spec + piano), il diff del branch
   rispetto al commit precedente, gli esiti dei test del passo 4. Blocker/major ⇒ `maat:plan-implementer` in `fix` con
   solo quei finding, poi nuova review. **Massimo 3 giri**; al terzo senza APPROVED ⇒ STOP con i finding aperti.
   Minor/nit: annotati nel rapporto, non applicati.
6. **Collaudo di rilasciabilità** — i punti della sezione `## Collaudo` del piano, più questi **tre punti comuni**,
   sempre:
   - a. **prova del revert:** in una copia usa e getta (un worktree del repo maat sullo stato del piano), le modifiche
     del piano si tolgono (`git revert --no-commit` del commit del piano, oppure il diff applicato al contrario): le
     suite dei piani precedenti devono tornare verdi; poi la copia si cancella;
   - b. **progetto guida intatto:** nel suo tree `git status --porcelain` e `git stash list` uguali a quelli annotati al
     passo 1;
   - c. **stato utente:** `~/.claude/settings.json`, `installed_plugins.json` e le voci di `known_marketplaces.json`
     (senza le date) uguali a quelli annotati al passo 1, salvo le
     installazioni previste dal piano o confermate al passo 1, e dichiarate.

   Quelli che il piano assegna all'utente (per esempio un'installazione da seguire a mano) si elencano come «da fare
   con l'utente», non si simulano. Un punto fallito ⇒ nessun commit, il branch torna al commit precedente (`git checkout
   -- .` nel worktree e rimozione dei soli file nuovi del piano), STOP con rapporto.
7. **Commit** sul branch di lavoro: `pkNN: <titolo del piano>` + corpo con esito review, collaudo e misura, + le righe
   di attribuzione richieste dalla sessione. Mai `--no-verify`.
8. **Revisione dei piani successivi** — per ogni piano elencato in «Dopo l'implementazione, rivedi»: rileggerlo e, se
   questa parte ha cambiato qualcosa che usa (interfaccia, file, comando, formato, nome), aggiungere in cima al piano
   successivo, in `docs/piani/` sullo stesso branch, una sezione `## Note da piani precedenti` con: cosa è cambiato, in
   quale commit, e come si adatta il passo interessato. Non riscrivere i passi approvati: annotare. Se l'adattamento
   cambia la sostanza del piano ⇒ segnalarlo nel rapporto come decisione per l'utente.
9. **Rapporto** — aggiungere una sezione a `docs/piani/maat-report.md`: piano, commit, esito review (giri), collaudo
   (punti del piano e i tre comuni), misura del beneficio, piani annotati, minor/nit aperti, installazioni fatte (con lo
   scope), tempo e quota consumati, righe proposte per `CHANGELOG.md`.

## STOP (fermano il piano e tutta la catena di piani richiesti)

Piano non approvato · prerequisito mancante · plugin della sessione non da una versione fissa · ciclo vivo sulla copia
del banco di prova · deviazione dal piano · test del plugin rosso due volte · 3 giri di review senza APPROVED · collaudo
fallito · adattamento sostanziale di un piano successivo · quota oltre soglia. Ogni STOP scrive il motivo nel rapporto e
dice all'utente cosa decidere o eseguire.

## Quota (abbonamento, nessuna spesa)

Leggere gli eventi di quota disponibili (`rate_limit_event` nei log dei rigiochi, o l'indicazione della sessione):
- sopra ~75% della finestra da 5 ore ⇒ pausa fino al reset (Monitor su un'attesa, non polling attivo);
- sopra ~30% della quota settimanale ⇒ STOP con rapporto, per lasciare quota al resto del lavoro.
I rigiochi di collaudo sono **per fase** e su cicli piccoli del banco di prova, uno per piano.

## Risposta finale

```text
Flusso H — <piani richiesti>
Esito: <per piano: COMMITTATO <sha> | STOP (<passo>: <motivo>) | NON AVVIATO (catena fermata)>
Review: <giri, finding chiusi>   Collaudo: <punti del piano + 3 comuni: esito | da fare con l'utente: …>
Misura: <beneficio osservato vs atteso>
Piani annotati: <pkXX: cosa>   Decisioni per te: <nessuna | elenco>
Plugin: <versione e sorgente del plugin usato; installazioni fatte, con lo scope>
Rapporto: docs/piani/maat-report.md
Branch: <wip/pkNN> (nessun push, nessun merge, nessun tag pubblicato: l'integrazione la decidi tu)
```
