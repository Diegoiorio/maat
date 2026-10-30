# Descrizione dei comandi nelle richieste di permesso (R11.1)

Il campo `description` dei tool Bash e PowerShell è ciò che l'utente legge quando Claude Code gli chiede il permesso.
Nei flussi Maat della sessione principale scrivilo così, nella lingua di `.claude/maat.json` → `lingua` (default it):

1. **Una frase**: cosa fa il comando e che effetto ha, cioè cosa cambia e dove (locale, ambiente di prova,
   produzione, servizio esterno).
2. **I comandi principali**, uno per voce, nella forma `nome — cosa fa qui`. Solo quelli che contano: ometti
   `cd`, `tail`, `2>&1` e simili, salvo che cambino il senso.
3. **L'avviso** se l'azione è irreversibile o esce dalla macchina: push, scritture su un database, cancellazioni,
   rilasci, invii.

Al massimo ~5 righe. Per i comandi di sola lettura (`ls`, `git status`, `grep`) basta la frase.

Esempio — `git push origin sviluppo`:

```text
Pubblica sul repository remoto i commit locali del ramo sviluppo (esce dalla macchina, visibile al team).
· git push origin sviluppo — invia i commit del ramo al remoto «origin»
```

Limite (R11.4): fuori dai flussi Maat vale la regola del `CLAUDE.md` di ciascun progetto. Le sotto-sessioni non
mostrano richieste, perché girano senza chiedere; la regola vale comunque nei loro log.
