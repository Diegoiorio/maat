# Worker `chiusura` — the e2e of a chain

Launched in a closure phase (`NN-chiusura`, the mother's run directory) only when the rings have
`[e2e-locator:` lines and the driver's `full` gates on the final tree are green; the prompt ends with
`E2E DELLA CATENA: <spec…>`. Invoke the declared remote verification (`verifica_remota` in `.claude/maat.json`) with `--e2e <spec>` once per spec, under the same guard as every
phase. End with `ESITO FASE chiusura: OK — e2e PASS (<spec…>)` or `ESITO FASE chiusura: STOP — <reason>`, and
**no** JSON block (this phase is not in the schema). The driver writes `chiusura.txt`; you write nothing else.
