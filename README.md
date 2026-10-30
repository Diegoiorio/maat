<p align="center">
  <img src="plugins/maat/assets/maat-logo-orizzontale-chiaro.svg" alt="Maat — Multi-Agent Assurance Toolkit" width="360">
</p>

# Maat — Multi-Agent Assurance Toolkit

**Maat è un plugin di Claude Code che fa lavorare gli agenti come un buon team.** Tu descrivi la modifica che vuoi.
Maat la porta fino al codice scritto e rivisto, e si ferma quando serve una tua decisione.

## Cosa fa

Gli dai una **spec**, cioè un file di testo che descrive la modifica. Con un solo comando Maat esegue cinque tappe, in
ordine:

1. **Piano.** Un agente scrive il piano, un altro lo critica. Si ripete finché il piano viene approvato.
2. **Codice.** Un agente scrive il codice seguendo il piano e lancia i test del progetto.
3. **Review.** Un agente diverso confronta il codice con il piano e con la spec.
4. **Correzioni.** Se la review trova problemi seri, il codice si corregge e si rivede.
5. **Firma.** L'esito finale: tutto fatto, oppure cosa resta da verificare.

Ogni tappa gira in una sessione separata di Claude: nessun agente giudica il proprio lavoro.

Mentre lavora, Maat:

- **blocca i comandi pericolosi**: produzione, push e comandi git che cambiano lo stato, installazioni;
- **non fa mai commit**: il codice resta modificato nella cartella, e il commit lo fai tu dopo averlo guardato;
- **riprende da dove era**: se si interrompe, rilanci lo stesso comando.

- Autore: [Diego Iorio](https://github.com/Diegoiorio). Licenza [MIT](LICENSE): libero da usare, modificare e
  ridistribuire.
- Guida completa ai flussi, con i diagrammi: [`docs/GUIDA-FLUSSI.html`](docs/GUIDA-FLUSSI.html) (da aprire nel browser).
- Novità di ogni versione: [`CHANGELOG.md`](CHANGELOG.md). Versione attuale: **1.1.0**.

## Prima di iniziare

| Ti serve | Versione | Come controlli |
|---|---|---|
| Claude Code | 2.1.285 o più recente | `claude --version` |
| git | 2.35 o più recente | `git --version` |
| bash (su Windows: Git Bash, incluso in Git for Windows) | 4 o più recente | `bash --version` |
| Python | 3.10 o più recente | `python --version` (su Windows: `py -3 --version`) |

Su Windows **WSL non serve**: velocizza solo i test JavaScript.

## Installazione

Maat si installa **una volta per ogni progetto** in cui vuoi usarlo.

**1. Installa il plugin.** Apri un terminale nella **cartella principale del progetto**, cioè la radice del repo git, e
lancia questi due comandi, copiandoli così come sono:

```bash
claude plugin marketplace add https://github.com/Diegoiorio/maat.git#v1.1.0 --scope project
claude plugin install maat@maat --scope project
```

- Il primo comando dice a Claude Code **da dove prendere Maat**: il repo GitHub, alla versione `v1.1.0` (la parte dopo
  `#`). Questo indirizzo è la «sorgente».
- Il secondo installa il plugin `maat` da quella sorgente.
- `--scope project` salva la scelta nel file `.claude/settings.json` del progetto. Se committi quel file, chi clona il
  progetto trova Maat già configurato.

Puoi dare gli stessi comandi anche dentro Claude Code: scrivi `/plugin` al posto di `claude plugin`.

**2. Riavvia Claude Code** nella cartella del progetto, oppure scrivi `/reload-plugins`.

**3. Configura il progetto.** Dentro Claude Code scrivi:

```text
/maat:setup
```

Il setup:

1. guarda il progetto **senza modificare niente** e riconosce linguaggi, test e lint;
2. ti mostra in una tabella i moduli e i comandi che userà: li confermi o li correggi;
3. ti chiede solo quello che non può indovinare, cioè:
   - l'indirizzo della produzione;
   - lo script di rilascio;
   - come accedi ai server;
   - i file da non toccare mai;
4. scrive `.claude/maat.json` **solo dopo la tua conferma**, prova la guardia e fa un controllo finale.

**4. Aggiungi al `.gitignore`** la cartella di lavoro di Maat, dove finiscono spec, piani e registri dei cicli:

```text
.claude/.ai-workflow/
```

**Controllo, quando vuoi.** Dalla cartella del progetto:

```bash
bash ~/.claude/plugins/cache/maat/maat/1.1.0/scripts/maat-doctor.sh
```

Il controllo non modifica niente e stampa una riga per ogni verifica:

- `OK`: va bene;
- `ATTENZIONE`: funziona, ma c'è qualcosa da sapere;
- `MANCA`: va sistemato, e la riga dice come.

## Uso

### 1. Scrivi la spec

La spec è un file Markdown nella cartella `.claude/.ai-workflow/`, con un nome come `spec-<nome>.md`, per esempio
`spec-export-csv.md`. Descrive **cosa** vuoi, non come farlo:

```markdown
# Spec: esportare i clienti in CSV

## Contesto
Perché serve e come funziona oggi (file e righe utili, se li conosci).

## Requisiti
1. Cosa deve fare, punto per punto, in modo che si possa verificare.

## Fuori ambito
Cosa non va toccato.

## Criteri di accettazione
Come si capisce che è fatto, per esempio quali test devono passare.
```

Non sai da dove partire? Chiedi a Claude: «usa l'agente `maat:spec-author` per scrivere la spec di: …», e descrivi la
modifica. L'agente legge il codice, ti fa domande se qualcosa non è chiaro e scrive il file.

### 2. Lancia il ciclo

```text
/maat:full-implementation-cycle .claude/.ai-workflow/spec-export-csv.md
```

In chat vedi solo le righe di avanzamento. Secondo la modifica, il ciclo dura da qualche minuto a qualche ora.

### 3. Leggi l'esito

| Esito | Cosa vuol dire | Cosa fai |
|---|---|---|
| `IMPLEMENTED` | Codice scritto, rivisto e verificato. | Guardi le modifiche e fai il commit. |
| `NEEDS_VERIFICATION` | La review è approvata, ma un controllo richiesto non è stato eseguito, per esempio perché il modulo non ha test. Il messaggio dice quale. | Fai tu quella verifica, poi il commit. |
| `STOP` | Maat si è fermato perché serve una persona. Il messaggio dice perché e cosa decidere. | Decidi, poi rilanci lo stesso comando: riprende da lì. |

### Opzioni utili

- `--worktree`: il ciclo lavora in una copia separata del repo, su un branch suo, così tu continui a lavorare nella
  cartella principale. Va lanciato dalla cartella principale del repo.
- `--tests=min|std|full`: quanti test eseguire, da pochi a tutti.
- `--light`: il piano viene rivisto da un solo revisore. Va bene per modifiche piccole.
- **Spec grandi:** si dividono in spec più piccole, che Maat esegue in ordine. Le prepara `maat:spec-author`.
- **Senza il ciclo completo:** `/maat:plan-review-cycle <spec>` fa solo il piano; poi
  `/maat:implementation-review-cycle <nome>` fa la review del codice che hai scritto tu.

## Configurazione

Tutto quello che riguarda il tuo progetto sta in `.claude/maat.json`, scritto da `/maat:setup`. Di solito non serve
modificarlo a mano. Se vuoi farlo:

- profili pronti per gli stack comuni: `plugins/maat/profiles/`;
- esempi completi: `plugins/maat/examples/`;
- tutte le chiavi: `plugins/maat/schemas/maat-config.schema.json`.

## Aggiornare a una versione nuova

Maat non si aggiorna mai da solo: resta alla versione scritta nella sorgente. Per passare a una versione nuova, per
esempio `v1.2.0`, dalla cartella del progetto:

```bash
claude plugin marketplace add https://github.com/Diegoiorio/maat.git#v1.2.0 --scope project
claude plugin update maat@maat --scope project
```

Poi riavvia Claude Code e lancia il controllo: la riga della versione deve dire OK. Non aggiornare mentre un ciclo è in
corso. Se lo fai, il ciclo se ne accorge, si ferma e ti chiede di confermare.

## Disinstallare

Dalla cartella del progetto:

```bash
claude plugin uninstall maat@maat --scope project
claude plugin marketplace remove maat --scope project
```

In `.claude/settings.json` restano due chiavi vuote (`enabledPlugins` ed `extraKnownMarketplaces`): sono innocue.
Anche `.claude/maat.json` e la cartella `.claude/.ai-workflow/` restano: se non ti servono più, cancellali tu.

## Piattaforme

| Piattaforma | Stato |
|---|---|
| Windows con WSL | verificato con tutti i test |
| Windows senza WSL | verificati i ripieghi senza WSL: test, controlli e diagnosi |
| Linux | verificato con tutti i test, in un Linux senza strumenti di Windows |
| Mac | previsto, non ancora provato |

I percorsi con spazi e con lettere accentate funzionano. Un solo limite: nei piani, i nomi dei file del progetto non
devono contenere spazi.

## Sviluppare Maat

Questa parte serve solo a chi modifica Maat:

- le modifiche si fanno con il **flusso H** (`.claude/skills/flusso-h/SKILL.md`), lanciando `claude` dalla cartella di
  questo repo;
- regola ferma: **il Maat che stai modificando si prova, non si usa per sviluppare**. Per provarlo a mano:
  `claude --plugin-dir <cartella del repo>/plugins/maat`;
- i test sono in [`docs/TESTING-harness.md`](docs/TESTING-harness.md).

Segnalazioni e proposte: apri una issue su GitHub.

## Responsabilità

Maat fa lavorare agenti di intelligenza artificiale che leggono e modificano il codice del tuo progetto ed eseguono
comandi sulla tua macchina. La guardia riduce i rischi, ma non li elimina.

- **Lo usi a tuo rischio.** Controlla sempre le modifiche prima del commit e non lanciarlo su progetti o macchine
  dove un errore non è rimediabile.
- Maat è fornito **«così com'è», senza garanzie di alcun tipo**. L'autore non risponde di danni, perdite di dati o
  altre conseguenze del suo uso: vedi la [licenza](LICENSE).
- Il costo delle sessioni di Claude Code che Maat avvia è a carico di chi lo usa.
- Maat è un progetto indipendente, non affiliato ad Anthropic. Claude e Claude Code sono marchi di Anthropic.

## Licenza

[MIT](LICENSE) © 2026 Diego Iorio.
