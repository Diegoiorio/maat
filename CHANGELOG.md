# Changelog

Formato: una sezione per versione (`MAJOR.MINOR.PATCH`), la più recente in alto.

## 1.1.0 — prima versione pubblica

Prima versione pubblicata, con licenza MIT. Il codice del plugin è quello della 1.0.0, usata finora in privato; per la
pubblicazione cambiano licenza, autore, esempi e dati di prova.

- **Licenza MIT**, autore Diego Iorio; nel README una sezione «Responsabilità».
- **Esempi e test senza dati di progetti reali:** host, indirizzi IP e percorsi di prova sono finti (`example.com`,
  `example.org`, `example.internal`, indirizzi della documentazione RFC 5737 e reti private). Gli esempi si chiamano
  `examples/nuxt-fastapi.maat.json` e `examples/bash-node.maat.json`; la fixture della guardia
  `tests/guard-esempio.cases`; la suite `scripts/bash-node.test.sh`.
- **`genericita.test.sh`:** i nomi propri del progetto guida si leggono da un file locale non tracciato
  (`.genericita-nomi`, o `MAAT_NOMI_RISERVATI`); le controprove usano un nome finto.
- **`tools/giro-completo.sh`:** il giro completo delle suite (Linux, poi Windows), con worktree e ramo obbligatori.

### Cosa contiene

- **Ciclo completo** `/maat:full-implementation-cycle <spec>`: piano rivisto fino all'approvazione, implementazione,
  review indipendente, correzioni, firma (`IMPLEMENTED`, `NEEDS_VERIFICATION` o `STOP` con il motivo). Ogni fase in una
  sotto-sessione separata; ripresa automatica rilanciando lo stesso comando; catene di spec; `--worktree`.
- **Cicli singoli:** `/maat:plan-review-cycle`, `/maat:plan-review-cycle-light`, `/maat:implementation-review-cycle`.
- **Setup guidato** `/maat:setup` e **diagnosi** `scripts/maat-doctor.sh`.
- **Configurazione per progetto** in `.claude/maat.json` (moduli, comandi di test e lint, guardia, percorsi da non
  toccare), con schema, profili pronti ed esempi.
- **Guardia di sessione e di fase:** blocca produzione, git che cambia stato, installazioni, accesso remoto.
- **Gate e controprove:** i test scelti per i file toccati, controprove per mutazione, firma con le prove.
- **Driver in Python** certificato equivalente al codice bash su cicli reali (`scripts/driver.equiv`).
- **Piattaforme:** Windows con e senza WSL, Linux; percorsi con spazi e lettere accentate.
- **Documentazione:** README, guida ai flussi (`docs/GUIDA-FLUSSI.html`), guida ai test (`docs/TESTING-harness.md`),
  flusso H per sviluppare Maat (`.claude/skills/flusso-h/`).
