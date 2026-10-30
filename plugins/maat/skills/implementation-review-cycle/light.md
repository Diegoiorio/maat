# Modalità `--light` — il giro veloce da fare SEMPRE dopo un'implementazione

**Quando usarla.** Subito dopo aver implementato un piano approvato e aver visto i gate verdi.
Non sostituisce la review completa: è il minimo indispensabile, e costa un solo giro d'agente.

**Perché esiste** (misurato, 2026-08-05, spec `qa-debug-pt4`). Il piano aveva superato **7 giri** di
`spec-plan-reviewer`, e l'implementazione aveva **3357 test backend + 1047 frontend + 162 e2e verdi**.
Un singolo giro `--light` ha comunque trovato **una falla reale**: un requisito che nascondeva una
sezione a un ruolo aveva una **quarta superficie** — una rotta gemella non gattata, raggiungibile con
un click — che nessuno dei 7 giri aveva previsto e che nessun test poteva prendere, perché i test
verificavano le tre superfici *già trovate*.

Il principio: **i test verificano ciò che hai pensato di controllare.** La review vede ciò che non
sapevi di dover guardare. Sono reti diverse, e nessuna delle due basta da sola.

**Come si esegue.** Un solo giro di `implementation-reviewer`, nessuna iterazione, mandato stretto,
sulla superficie calcolata da `review-surface.sh snapshot` (Step 1) — anche in `--light` il
`git diff` nudo non basta. Nel prompt dell'agente vanno SEMPRE questi quattro elementi:

1. **Dichiara i gate verdi con i numeri VERI**, e vieta esplicitamente di cercare ciò che quei gate
   avrebbero già preso (refusi, stile, copertura in generale). Senza questo, l'agente spende il giro a
   ri-verificare cose già verificate.
   ⚠️ **E dichiara anche il livello in vigore e le suite NON girate.** A `min`/`std` le suite dei
   moduli non toccati non sono partite: dire «i gate sono verdi» di suite che nessuno ha eseguito è
   peggio che tacere, perché vieta al giro di guardare proprio dove non guarda nient'altro. Vale
   l'elemento 1 della versione inglese sopra, che governa **ogni** prompt di `implementation-reviewer`.
2. **Chiedi SOLO le classi che i test non possono vedere:**
   - **raggio d'azione** — chi altro consuma i file condivisi che ho toccato, e si rompe?
   - **superfici dimenticate** — se il cambio nasconde/gatta qualcosa, esiste un'altra strada per
     arrivarci che non ho trovato?
   - **interazioni e anelli** — middleware, redirect, guardie che combinandosi producono un rimbalzo
     o un ciclo.
   - **integrità dei test** — se i `Test signals` dello snapshot non sono `none`: il test è stato
     cambiato per seguire la spec o per adattarsi all'implementazione?
3. **Soglia di segnalazione stretta**: solo ciò che porterebbe a cambiare il codice. Se una cosa è
   teorica o richiede una condizione che non si verifica, non va segnalata. Chiedi di dire
   esplicitamente «classe N: nulla» quando una classe è pulita, così l'assenza di finding è un dato e
   non un'ambiguità.
4. **Istruzione anti-stallo**: se non riesce a completare, deve dichiarare il motivo e fino a dove è
   arrivato invece di terminare in silenzio.

⚠️ **Dopo aver applicato i finding, RILANCIA i test** — quelli dei moduli toccati, non tutto.
Applicando i finding di questa review si introducono regressioni come in qualunque altra modifica:
nella sessione di riferimento la correzione di un finding ha rotto 5 test (un mock di modulo che non
copriva un export nuovo). È la controprova del principio di sopra, nell'altra direzione.

In `--light` non si scrive la sezione `## Review implementazione` a meno che non emergano finding
bloccanti: il giro veloce vive nella conversazione, e **non** porta mai a `IMPLEMENTED`. Se la
scrive, **non** scrive la riga `Reviewed snapshot:`: il giro veloce ha guardato solo le classi
strette, quindi non è una base su cui una review successiva possa limitarsi al delta — il giro
pieno che segue è a scope pieno. Il budget di
iterazioni è **1**, non 3. La risposta dichiara comunque `Verification:` con la stessa semantica del
ramo pieno, così un giro veloce senza test non si legge come verificato.
