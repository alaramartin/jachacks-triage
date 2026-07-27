"""GitHub OAuth + repo access + PR creation. Owner: Person 2.

REAL OAuth (no longer a scope cut): `authorize_url` -> GitHub consent screen ->
`exchange_code_for_token` -> `get_authenticated_user`. The resulting token is
stored server-side on a GithubAuth node (see graph/nodes.jac) and threaded
through every call here as an explicit `token` argument - nothing in this file
mutates global state, so a logged-in session and the fallback .env
GITHUB_TOKEN can coexist.

Token precedence everywhere: the explicit `token` argument wins; if it's
empty we fall back to GITHUB_TOKEN from .env. That fallback is what keeps the
demo runnable on a machine where no OAuth app has been registered."""
import json;
import base64;
import os;
import time;
import subprocess;
import from urllib.request { Request, urlopen }
import from urllib.parse { urlencode }
import from urllib.error { HTTPError }

glob GITHUB_CLIENT_ID: str = os.environ.get("GITHUB_CLIENT_ID", "");
glob GITHUB_CLIENT_SECRET: str = os.environ.get("GITHUB_CLIENT_SECRET", "");
glob GITHUB_TOKEN: str = os.environ.get("GITHUB_TOKEN", "");

# `repo` (not `public_repo`) because Triage opens PRs on the repo you pick,
# which may be private; `read:user` powers the "logged in as ..." chip.
glob OAUTH_SCOPES: str = "read:user repo";

# Where the browser lands after GitHub's consent screen. Must match the
# "Authorization callback URL" on the OAuth app registration.
glob APP_URL: str = os.environ.get("TRIAGE_APP_URL", "http://localhost:8000");

# Where cloned repos land so the AST parser has real source to walk. Anything
# under here is disposable - deleting it just forces a re-clone.
glob WORKSPACE_ROOT: str = os.environ.get("TRIAGE_WORKSPACE", ".workspace");

def oauth_configured() -> bool {
    return bool(GITHUB_CLIENT_ID) and bool(GITHUB_CLIENT_SECRET);
}

"""The GitHub consent-screen URL to send the browser to. `redirect_uri` must
match (or sit under) the callback URL registered on the OAuth app."""
def authorize_url(redirect_uri: str, state: str = "") -> str {
    params: dict = {
        "client_id": GITHUB_CLIENT_ID,
        "redirect_uri": redirect_uri,
        "scope": OAUTH_SCOPES,
        "state": state,

    };
    return f"https://github.com/login/oauth/authorize?{urlencode(params)}";
}

obj GithubTokenResult {
    has access_token: str = "";
    has error: str = "";
}

def exchange_code_for_token(code: str, redirect_uri: str = "") -> GithubTokenResult {
    if not oauth_configured() {
        return GithubTokenResult(
            error="GITHUB_CLIENT_ID/GITHUB_CLIENT_SECRET not configured - see .env.example"
        );
    }

    payload: dict = {
        "client_id": GITHUB_CLIENT_ID,
        "client_secret": GITHUB_CLIENT_SECRET,
        "code": code,

    };
    if redirect_uri {
        payload["redirect_uri"] = redirect_uri;
    }
    data: bytes = urlencode(payload).encode("utf-8");
    req = Request(
        "https://github.com/login/oauth/access_token",
        data=data,
        headers={"Accept": "application/json"},
        method="POST"
    );

    try {
        resp = urlopen(req);
        body = json.loads(resp.read().decode("utf-8"));
    } except HTTPError as e {
        return GithubTokenResult(error=f"GitHub token exchange failed: {e}");
    }

    token: str = body.get("access_token", "");
    if not token {
        return GithubTokenResult(
            error=body.get("error_description", "no access_token in GitHub response")
        );
    }
    return GithubTokenResult(access_token=token);
}

obj GithubUser {
    has login: str = "";
    has name: str = "";
    has avatar_url: str = "";
    has html_url: str = "";
    has error: str = "";
}

"""Who a token belongs to. Also doubles as the token-validity check - an
expired or revoked token comes back with `error` set and an empty login."""
def get_authenticated_user(token: str = "") -> GithubUser {
    active: str = token if token else GITHUB_TOKEN;
    if not active {
        return GithubUser(error="no GitHub token available");
    }
    row: dict | None = _api_get("https://api.github.com/user", active);
    if row is None {
        return GithubUser(
            error="GitHub rejected the token (expired, revoked or wrong scopes)"
        );
    }
    return GithubUser(
        login=row.get("login", ""),
        name=row.get("name") or row.get("login", ""),
        avatar_url=row.get("avatar_url", ""),
        html_url=row.get("html_url", "")
    );
}

obj RepoSummary {
    has full_name: str = "";
    has default_branch: str = "main";
    has private: bool = False;
    has description: str = "";
    has language: str = "";
    has stars: int = 0;
    has open_issues: int = 0;
    has updated_at: str = "";
    has can_push: bool = False;
}

def _repo_summary(r: dict) -> RepoSummary {
    perms: dict = r.get("permissions") or {};
    return RepoSummary(
        full_name=r.get("full_name", ""),
        default_branch=r.get("default_branch", "main"),
        private=r.get("private", False),
        description=r.get("description") or "",
        language=r.get("language") or "",
        stars=r.get("stargazers_count", 0),
        open_issues=r.get("open_issues_count", 0),
        updated_at=r.get("updated_at", ""),
        can_push=perms.get("push", False)
    );
}

"""Every repo the logged-in user can act on - owned, collaborator, or via org
membership. Sorted by GitHub's own "recently pushed" order, which is a decent
proxy for "the project you actually care about today"."""
def list_repos(access_token: str = "") -> list[RepoSummary] {
    active: str = access_token if access_token else GITHUB_TOKEN;
    out: list[RepoSummary] = [];
    page: int = 1;
    while page <= 3 {
        rows: list[dict] | None = _api_get_list(
            "https://api.github.com/user/repos"
            f"?per_page=100&page={page}&sort=pushed"
            "&affiliation=owner,collaborator,organization_member",
            active
        );
        if rows is None or len(rows) == 0 {
            break;
        }
        for r in rows {
            out.append(_repo_summary(r));
        }
        if len(rows) < 100 {
            break;
        }
        page += 1;
    }
    return out;
}

"""One repo by `owner/name`, whether or not the user owns it - this is the
"paste any repo link" path. None means GitHub wouldn't serve it (typo,
private without access, or rate-limited)."""
def get_repo(full_name: str, token: str = "") -> RepoSummary | None {
    row: dict | None = _api_get(f"https://api.github.com/repos/{full_name}", token);
    if row is None {
        return None;
    }
    return _repo_summary(row);
}

"""GitHub owner and repo names are limited to these characters, so anything
else marks the end of the name. Trimming to this is what stops a paste with
trailing prose ("owner/repo151 files indexed. Triaging...") from being sent
to the API as a repo name that obviously cannot exist."""
def _trim_to_name(segment: str) -> str {
    out: str = "";
    for ch in segment {
        if ch.isalnum() or ch in "._-" {
            out += ch;
        } else {
            break;
        }
    }
    return out;
}

"""Normalize anything a human might paste into `owner/name`:
a browser URL (with or without /issues, /tree/main, .git, trailing slash),
an SSH remote, or an already-bare owner/name. Empty string = unparseable."""
def parse_repo_full_name(raw: str) -> str {
    text: str = raw.strip();
    if not text {
        return "";
    }
    # Only ever consider the first whitespace-delimited token - a paste that
    # dragged along surrounding text should not become part of the repo name.
    text = text.split()[0];
    if text.startswith("git@") {
        text = text.split(":", 1)[-1];
    }
    for prefix in ["https://", "http://", "www.", "github.com/"] {
        if text.startswith(prefix) {
            text = text[len(prefix):];
        }
    }
    if text.startswith("github.com/") {
        text = text[len("github.com/"):];
    }
    if text.endswith(".git") {
        text = text[:-4];
    }
    parts: list[str] = [
        p
        for p in text.split("/")
        if p
    ];
    if len(parts) < 2 {
        return "";
    }
    owner: str = _trim_to_name(parts[0]);
    name: str = _trim_to_name(parts[1]);
    if not owner or not name {
        return "";
    }
    return f"{owner}/{name}";
}

obj CloneResult {
    has path: str = "";
    has error: str = "";
}

"""Shallow-clone `full_name` into the workspace so the AST parser has real
source to walk. An existing clone is reused as-is (re-cloning jaclang on every
demo run is a minute we don't have); delete the directory to force a refresh.
The token, if any, is injected into the URL for private-repo access and
scrubbed out of any error text before it leaves this function."""
def clone_repo(
    full_name: str, default_branch: str = "", token: str = ""
) -> CloneResult {
    active: str = token if token else GITHUB_TOKEN;
    dest: str = os.path.join(WORKSPACE_ROOT, full_name.replace("/", "__"));
    if os.path.isdir(os.path.join(dest, ".git")) {
        return CloneResult(path=dest);
    }
    os.makedirs(WORKSPACE_ROOT, exist_ok=True);

    url: str = f"https://github.com/{full_name}.git";
    if active {
        url = f"https://x-access-token:{active}@github.com/{full_name}.git";
    }
    cmd: list[str] = ["git", "clone", "--depth", "1", "--single-branch"];
    if default_branch {
        cmd += ["--branch", default_branch];
    }
    cmd += [url, dest];

    try {
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=300);
    } except Exception as e {
        return CloneResult(error=f"git clone failed to start: {e}");
    }
    if proc.returncode != 0 {
        detail: str = (proc.stderr or "").strip();
        if active {
            detail = detail.replace(active, "***");
        }
        return CloneResult(error=f"git clone of {full_name} failed: {detail}");
    }
    return CloneResult(path=dest);
}

obj PullRequestResult {
    has ok: bool = True;
    has pr_number: int = 0;
    has pr_url: str = "";
    has error: str = "";
}

# An empty `token` falls back to .env's GITHUB_TOKEN; unauthenticated (both
# empty) still works for public repos, just at GitHub's 60-req/hour anon rate.
def _auth_headers(token: str = "") -> dict {
    active: str = token if token else GITHUB_TOKEN;
    headers: dict = {"Accept": "application/vnd.github+json"};
    if active {
        headers["Authorization"] = f"Bearer {active}";
    }
    return headers;
}

def _api_get(url: str, token: str = "") -> dict | None {
    req = Request(url, headers=_auth_headers(token));
    try {
        resp = urlopen(req);
        return json.loads(resp.read().decode("utf-8"));
    } except Exception {
        return None;
    }
}

def _api_get_list(url: str, token: str = "") -> list[dict] | None {
    req = Request(url, headers=_auth_headers(token));
    try {
        resp = urlopen(req);
        return json.loads(resp.read().decode("utf-8"));
    } except Exception {
        return None;
    }
}

obj ApiSendResult {
    has data: dict | None = None;
    has error: str = "";
}

def _api_send(url: str, method: str, payload: dict, token: str = "") -> ApiSendResult {
    data: bytes = json.dumps(payload).encode("utf-8");
    headers: dict = _auth_headers(token);
    headers["Content-Type"] = "application/json";
    req = Request(url, data=data, headers=headers, method=method);
    try {
        resp = urlopen(req);
        return ApiSendResult(data=json.loads(resp.read().decode("utf-8")));
    } except HTTPError as e {
        detail: str = e.read().decode("utf-8") if e.fp else str(e);
        return ApiSendResult(error=f"GitHub API {method} {url} -> {e.code}: {detail}");
    }
}

obj RemoteIssue {
    has external_id: str = "";
    has title: str = "";
    has body: str = "";
    has created_at: str = "";
    has reactions: int = 0;
    has comment_velocity: int = 0;
}

"""Live open issues on `full_name`, read straight from the GitHub REST API -
this is what makes the dashboard work against ANY repo (not just the seed
repo) once auth is wired up, not just the one we ingested at demo time.
Pull requests share the issues endpoint on GitHub (they show up with a
`pull_request` key) and are filtered out here since Triage only triages
issues. `comment_velocity` isn't a GitHub field - it's derived as comments
per day-since-created (min 1 day denominator) so a fresh flood of comments
reads as "hot" the same way engagement genuinely would.

`limit` (0 = no cap) exists because every ingested issue costs three local
LLM calls: pointing Triage at a repo with 400 open issues would take an hour.
When capped we ask GitHub for the most recently *updated* issues, so a big
repo shows its live queue rather than whatever was filed in 2014."""
def fetch_open_issues(
    full_name: str, limit: int = 0, token: str = ""
) -> list[RemoteIssue] {
    out: list[RemoteIssue] = [];
    page: int = 1;
    order: str = "created&direction=asc" if limit <= 0 else "updated&direction=desc";
    while page <= 10 {
        rows: list[dict] | None = _api_get_list(
            f"https://api.github.com/repos/{full_name}/issues"
            f"?state=open&per_page=100&page={page}&sort={order}",
            token
        );
        if rows is None or len(rows) == 0 {
            break;
        }
        for r in rows {
            if "pull_request" in r {
                continue;
            }
            created_at: str = r.get("created_at", "");
            comments: int = r.get("comments", 0);
            days_open: float = _days_since(created_at);
            velocity: int = round(comments / days_open) if days_open > 0 else comments;
            reaction_block: dict = r.get("reactions", {});
            out.append(
                RemoteIssue(
                    external_id=str(r["number"]),
                    title=r.get("title", ""),
                    body=r.get("body") or "",
                    created_at=created_at,
                    reactions=reaction_block.get("total_count", 0),
                    comment_velocity=velocity,
                )
            );
            if limit > 0 and len(out) >= limit {
                return out;
            }
        }
        if len(rows) < 100 {
            break;
        }
        page += 1;
    }
    return out;
}

def _days_since(iso_timestamp: str) -> float {
    if not iso_timestamp {
        return 1.0;
    }
    created = time.strptime(iso_timestamp, "%Y-%m-%dT%H:%M:%SZ");
    delta_seconds: float = time.time() - time.mktime(created);
    return max(delta_seconds / 86400.0, 1.0);
}

"""The number of genuinely open ISSUES on `full_name`.

Not the same as `RepoSummary.open_issues`: GitHub's `open_issues_count` field
counts pull requests too (jaseci-labs/Agentic-AI reports 44 there but has 37
issues and 7 PRs), so showing that number next to "issues" is just wrong.
Costs one extra API call, which is why only select_repo uses it and the repo
grid sticks with the cheap field it already got from the listing."""
def count_open_issues(full_name: str, token: str = "") -> int {
    total: int = 0;
    page: int = 1;
    while page <= 10 {
        rows: list[dict] | None = _api_get_list(
            f"https://api.github.com/repos/{full_name}/issues"
            f"?state=open&per_page=100&page={page}",
            token
        );
        if rows is None or len(rows) == 0 {
            break;
        }
        for r in rows {
            if "pull_request" not in r {
                total += 1;
            }
        }
        if len(rows) < 100 {
            break;
        }
        page += 1;
    }
    return total;
}

"""Base commit SHA for `branch` on `full_name`, or None if the branch/repo
can't be read (bad token, wrong repo, network)."""
def _branch_head_sha(full_name: str, branch: str, token: str = "") -> str | None {
    ref: dict | None = _api_get(
        f"https://api.github.com/repos/{full_name}/git/ref/heads/{branch}", token
    );
    if ref is None {
        return None;
    }
    obj_field: dict = ref["object"];
    return obj_field["sha"];
}

"""Real GitHub API PR creation (Phase C): create a fresh branch off
`default_branch`, write `new_content` to `path` on that branch via the
Contents API (a full-file write, not a diff/patch - far more reliable to
generate correctly with an LLM than a unified diff), then open a PR.
Branch name gets a timestamp suffix so re-running the demo in rehearsal
never collides with a previous run's branch."""
def create_pull_request(
    full_name: str,
    title: str,
    body: str,
    default_branch: str = "main",
    path: str = "",
    new_content: str = "",
    token: str = ""
) -> PullRequestResult {
    active: str = token if token else GITHUB_TOKEN;
    if not active {
        return PullRequestResult(
            ok=False,
            error="not authenticated with GitHub - log in, or set GITHUB_TOKEN (see .env.example)"
        );
    }

    base_sha: str | None = _branch_head_sha(full_name, default_branch, active);
    if base_sha is None {
        return PullRequestResult(
            ok=False,
            error=f"couldn't read {default_branch} on {full_name} - check your GitHub permissions on this repo"
        );
    }

    branch_name: str = f"triage/fix-{int(time.time())}";
    ref_result: ApiSendResult = _api_send(
        f"https://api.github.com/repos/{full_name}/git/refs",
        "POST",
        {"ref": f"refs/heads/{branch_name}", "sha": base_sha},
        active
    );
    if ref_result.error {
        return PullRequestResult(ok=False, error=ref_result.error);
    }

    if path and new_content {
        existing: dict | None = _api_get(
            f"https://api.github.com/repos/{full_name}/contents/{path}?ref={branch_name}",
            active
        );
        existing_sha: str | None = existing["sha"] if existing else None;
        content_payload: dict = {
            "message": title,
            "content": base64.b64encode(new_content.encode("utf-8")).decode("ascii"),
            "branch": branch_name,

        };
        if existing_sha {
            content_payload["sha"] = existing_sha;
        }
        put_result: ApiSendResult = _api_send(
            f"https://api.github.com/repos/{full_name}/contents/{path}",
            "PUT",
            content_payload,
            active
        );
        if put_result.error {
            return PullRequestResult(ok=False, error=put_result.error);
        }
    }

    pr_result: ApiSendResult = _api_send(
        f"https://api.github.com/repos/{full_name}/pulls",
        "POST",
        {"title": title, "body": body, "head": branch_name, "base": default_branch},
        active
    );
    if pr_result.error or pr_result.data is None {
        return PullRequestResult(
            ok=False, error=pr_result.error or "GitHub returned no PR data"
        );
    }

    pr: dict = pr_result.data;
    return PullRequestResult(ok=True, pr_number=pr["number"], pr_url=pr["html_url"]);
}
