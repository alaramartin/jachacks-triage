"""Seed the graph from the REAL GitHub issue queue on the indexed repo, via
ingest_from_github, instead of a local issues.json fixture. Real issues live
at github.com/alaramartin/triage-demo/issues - this script no longer reads
anything off disk for issue content.

Requires `jac start main.jac --dev` (or --no-client) already running - `jac run`
gets its own isolated root, NOT the server's anonymous/guest root, so this talks
to the live server over HTTP instead of spawning the walker in-process (verified
against a running server: the two roots do not share graph state).

Run from the repo root, server already up (reindex_repo already called so a
Repo node exists):

    jac run seed/seed.jac

Idempotent: ingest_from_github skips issues it has already ingested (matched
by GitHub issue number), so re-running just picks up newly opened issues.
Call reset_demo first if you want a fully clean re-seed."""
import json;
import os;
import from urllib.request { Request, urlopen }

# The API port depends on how the server was started:
#   jac start main.jac --no-client  -> API on 8000 (the default below)
#   jac start main.jac --dev        -> app on 8000, API on 8001
# Override without editing this file:  TRIAGE_API=http://localhost:8001 jac run seed/seed.jac
glob BASE_URL: str = os.environ.get("TRIAGE_API", "http://localhost:8000");
# Override to seed against a different repo's issue queue without editing
# this file. Empty means "the most recently selected repo" (get_active_repo) -
# so if you have been exploring another repo through the UI, set this
# explicitly to alaramartin/triage-demo before re-seeding the demo.
glob GITHUB_REPO: str = os.environ.get("TRIAGE_GITHUB_REPO", "");

def _post(path: str, payload: dict) -> dict {
    data: bytes = json.dumps(payload).encode("utf-8");
    req = Request(
        f"{BASE_URL}{path}",
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST"
    );
    resp = urlopen(req);
    envelope = json.loads(resp.read().decode("utf-8"));
    reports = envelope["data"]["reports"];
    if len(reports) > 0 {
        return reports[0];
    }
    return envelope;
}

# `entry:__main__`, NOT a plain `entry`: a plain entry block runs on every
# import, which means `jac test -d .` executes this file's HTTP calls during
# collection. With no server up that crashes the whole suite; with a server up
# it is worse - it silently re-fetches the live issue queue during collection.
# Guarding it makes the suite runnable as one command and makes seeding an
# explicit `jac run seed/seed.jac` action.
with entry:__main__ {
    outcome: dict = _post("/walker/ingest_from_github", {"full_name": GITHUB_REPO});
    print(json.dumps(outcome, indent=2));
}
