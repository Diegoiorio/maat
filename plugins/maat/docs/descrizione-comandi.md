# Describing commands in permission requests (R11.1)

The `description` field of the Bash and PowerShell tools is what the user reads when Claude Code asks for permission
to run a command. In every session of a project that uses Maat, write it like this, in the language set by `lingua`
in `.claude/maat.json` (default: English):

1. **One sentence**: what the command does and what it changes, and where (this machine, a test environment,
   production, an external service).
2. **The main commands**, one per item, as `name — what it does here`. Only the ones that matter: leave out `cd`,
   `tail`, `2>&1` and the like, unless they change the meaning.
3. **A warning** when the action cannot be undone or leaves the machine: push, database writes, deletions,
   releases, messages sent.

At most about 5 lines. For read-only commands (`ls`, `git status`, `grep`) the sentence is enough.

Example — `git push origin main`:

```text
Publishes the local commits of the main branch to the remote repository (leaves the machine, visible to the team).
· git push origin main — sends the branch's commits to the remote "origin"
```

The plugin's `SessionStart` hook (`scripts/session-start.sh`) loads this rule into every session, so it also applies
outside the Maat flows. Sub-sessions of a cycle run without asking, so they show no prompts; the rule still applies
to their logs.
