#!/usr/bin/env python3
"""maat_paths.py — single resolver of the two roots, Python side (pk04a-1, step 1).

Same rules as scripts/lib/maat-paths.sh:
  MAAT_ROOT     MAAT_ROOT from the environment if set, otherwise the folder above this file's folder; it must
                contain .claude-plugin/plugin.json (otherwise ErroreMaat, code 4).
  PROJECT_ROOT  FIC_REPO if set, otherwise `git rev-parse --show-toplevel` from the working directory (never
                from this file's location). Outside a git repo: ErroreMaat, code 4.
  MAAT_SCRIPTS, MAAT_SKILLS, MAAT_AGENTS, MAAT_SCHEMAS under MAAT_ROOT.
  MAAT_WORK     PROJECT_ROOT/<cartelle.lavoro> (maat.json, read with maat-config.py; default .claude/.ai-workflow).

Importers set `sys.dont_write_bytecode = True` BEFORE the import: no __pycache__ under MAAT_ROOT.
Run directly it prints «NOME=valore», one per line, like `bash lib/maat-paths.sh`; exit 4 without a project.
Paths with forward slashes (C:/… on Windows).
"""
import os
import subprocess
import sys

LAVORO_DEFAULT = ".claude/.ai-workflow"
CHIAVI = ("MAAT_ROOT", "PROJECT_ROOT", "MAAT_SCRIPTS", "MAAT_SKILLS", "MAAT_AGENTS", "MAAT_SCHEMAS", "MAAT_WORK")


class ErroreMaat(Exception):
    codice = 4


def _fw(p):
    return p.replace("\\", "/")


def maat_root():
    env = os.environ.get("MAAT_ROOT")
    if env:
        r = _fw(env).rstrip("/")
    else:
        r = _fw(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    if not r or not os.path.isfile(os.path.join(r, ".claude-plugin", "plugin.json")):
        raise ErroreMaat("MAAT_ROOT='%s' non e' la radice di un plugin maat (manca .claude-plugin/plugin.json)" % r)
    return r


def project_root(cwd=None):
    env = os.environ.get("FIC_REPO")
    if env:
        return env
    try:
        r = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, cwd=cwd)
        top = r.stdout.strip().replace("\r", "")
        if r.returncode == 0 and top:
            return _fw(top)
    except OSError:
        pass
    raise ErroreMaat("la cartella di lavoro %s non e' in un repository git: PROJECT_ROOT non risolta "
                     "(lancia dalla cartella del progetto, o imposta FIC_REPO)" % _fw(os.path.abspath(cwd or os.getcwd())))


def maat_work(project, root=None):
    lavoro = LAVORO_DEFAULT
    if os.environ.get("MAAT_CONFIG") or os.path.isfile(os.path.join(project, ".claude", "maat.json")):
        root = root or maat_root()
        env = dict(os.environ, PROJECT_ROOT=project)
        try:
            r = subprocess.run([sys.executable, os.path.join(root, "scripts", "maat-config.py"), "leggi",
                                "cartelle.lavoro", "--default", LAVORO_DEFAULT],
                               capture_output=True, text=True, env=env)
            v = r.stdout.strip().replace("\r", "")
            if r.returncode == 0 and v:
                lavoro = v
            else:
                sys.stderr.write("maat: cartelle.lavoro non letta da maat.json: uso il default %s\n" % lavoro)
        except OSError:
            sys.stderr.write("maat: cartelle.lavoro non letta da maat.json: uso il default %s\n" % lavoro)
    return project + "/" + lavoro.rstrip("/")


def risolvi(cwd=None):
    """All the variables; ErroreMaat (code 4) without a plugin or without a project."""
    root = maat_root()
    project = project_root(cwd)
    return {"MAAT_ROOT": root, "PROJECT_ROOT": project, "MAAT_SCRIPTS": root + "/scripts",
            "MAAT_SKILLS": root + "/skills", "MAAT_AGENTS": root + "/agents", "MAAT_SCHEMAS": root + "/schemas",
            "MAAT_WORK": maat_work(project, root)}


def main():
    try:
        v = risolvi()
    except ErroreMaat as e:
        sys.stderr.write("maat: %s\n" % e)
        return e.codice
    for k in CHIAVI:
        print("%s=%s" % (k, v[k]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
