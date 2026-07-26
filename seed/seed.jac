"""Load seed/issues.json into the graph via ingest_issue, in order.

Requires `jac start main.jac --dev` (or --no-client) already running - `jac run`
gets its own isolated root, NOT the server's anonymous/guest root, so this talks
to the live server over HTTP instead of spawning the walker in-process (verified
against a running server: the two roots do not share graph state).

Run from the repo root, server already up:

    jac run seed/seed.jac

Idempotent only insofar as ingest_issue is - re-running adds duplicate Issue
nodes, so call reset_demo first if you want a clean re-seed."""
import json;
import from urllib.request { Request, urlopen }

glob BASE_URL: str = "http://localhost:8000";

def _post(path: str, payload: dict) -> dict {
    data: bytes = json.dumps(payload).encode("utf-8");
    req = Request(f"{BASE_URL}{path}", data=data, headers={"Content-Type": "application/json"}, method="POST");
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
# it is worse - it silently re-ingests all 20 issues into the LIVE graph and
# leaves you with duplicates. Guarding it makes the suite runnable as one
# command and makes seeding an explicit `jac run seed/seed.jac` action.
with entry:__main__ {
    fh = open("seed/issues.json", "r");
    issues: list[dict] = json.load(fh);
    fh.close();

    for issue in issues {
        outcome: dict = _post("/walker/ingest_issue", {
            "external_id": issue["external_id"],
            "title": issue["title"],
            "body": issue["body"],
            "created_at": issue["created_at"],
            "reactions": issue.get("reactions", 0),
            "comment_velocity": issue.get("comment_velocity", 0),
        });
        print(f"{issue['external_id']}: {outcome}");
    }
}
