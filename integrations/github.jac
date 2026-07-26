"""GitHub OAuth + PR creation. Owner: Person 2.

Phase B: token exchange + list_repos are real (need GITHUB_CLIENT_ID /
GITHUB_CLIENT_SECRET in .env - see .env.example) but unused on the demo path -
OAuth login is a documented scope cut (PLAN.md: RepoPickerScreen hardcodes
the single demo repo regardless of login, so real OAuth would change nothing
downstream). Phase C authenticates PR creation with a plain Personal Access
Token (GITHUB_TOKEN in .env) instead - same real GitHub API, far less to
build this close to the deadline."""
import json;
import base64;
import os;
import time;
import from urllib.request { Request, urlopen }
import from urllib.parse { urlencode }
import from urllib.error { HTTPError }

glob GITHUB_CLIENT_ID: str = os.environ.get("GITHUB_CLIENT_ID", "");
glob GITHUB_CLIENT_SECRET: str = os.environ.get("GITHUB_CLIENT_SECRET", "");
glob GITHUB_TOKEN: str = os.environ.get("GITHUB_TOKEN", "");

obj GithubTokenResult {
    has access_token: str = "";
    has error: str = "";
}

def exchange_code_for_token(code: str) -> GithubTokenResult {
    if not GITHUB_CLIENT_ID or not GITHUB_CLIENT_SECRET {
        return GithubTokenResult(
            error="GITHUB_CLIENT_ID/GITHUB_CLIENT_SECRET not configured - see .env.example"
        );
    }

    payload: dict = {
        "client_id": GITHUB_CLIENT_ID,
        "client_secret": GITHUB_CLIENT_SECRET,
        "code": code,

    };
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

obj RepoSummary {
    has full_name: str = "";
    has default_branch: str = "main";
    has private: bool = False;
}

def list_repos(access_token: str) -> list[RepoSummary] {
    req = Request(
        "https://api.github.com/user/repos?per_page=100&sort=updated",
        headers={
            "Authorization": f"Bearer {access_token}",
            "Accept": "application/vnd.github+json",

        }
    );

    try {
        resp = urlopen(req);
        rows: list[dict] = json.loads(resp.read().decode("utf-8"));
    } except HTTPError {
        return [];
    }

    return [
        RepoSummary(
            full_name=r["full_name"],
            default_branch=r.get("default_branch", "main"),
            private=r.get("private", False)
        ) for r in rows
    ];
}

obj PullRequestResult {
    has ok: bool = True;
    has pr_number: int = 0;
    has pr_url: str = "";
    has error: str = "";
}

def _auth_headers() -> dict {
    return {
        "Authorization": f"Bearer {GITHUB_TOKEN}",
        "Accept": "application/vnd.github+json",

    };
}

def _api_get(url: str) -> dict | None {
    req = Request(url, headers=_auth_headers());
    try {
        resp = urlopen(req);
        return json.loads(resp.read().decode("utf-8"));
    } except HTTPError {
        return None;
    }
}

obj ApiSendResult {
    has data: dict | None = None;
    has error: str = "";
}

def _api_send(url: str, method: str, payload: dict) -> ApiSendResult {
    data: bytes = json.dumps(payload).encode("utf-8");
    headers: dict = _auth_headers();
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

"""Base commit SHA for `branch` on `full_name`, or None if the branch/repo
can't be read (bad token, wrong repo, network)."""
def _branch_head_sha(full_name: str, branch: str) -> str | None {
    ref: dict | None = _api_get(
        f"https://api.github.com/repos/{full_name}/git/ref/heads/{branch}"
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
    new_content: str = ""
) -> PullRequestResult {
    if not GITHUB_TOKEN {
        return PullRequestResult(
            ok=False, error="GITHUB_TOKEN not configured - see .env.example"
        );
    }

    base_sha: str | None = _branch_head_sha(full_name, default_branch);
    if base_sha is None {
        return PullRequestResult(
            ok=False,
            error=f"couldn't read {default_branch} on {full_name} - check GITHUB_TOKEN scope/repo name"
        );
    }

    branch_name: str = f"triage/fix-{int(time.time())}";
    ref_result: ApiSendResult = _api_send(
        f"https://api.github.com/repos/{full_name}/git/refs",
        "POST",
        {"ref": f"refs/heads/{branch_name}", "sha": base_sha}
    );
    if ref_result.error {
        return PullRequestResult(ok=False, error=ref_result.error);
    }

    if path and new_content {
        existing: dict | None = _api_get(
            f"https://api.github.com/repos/{full_name}/contents/{path}?ref={branch_name}"
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
            content_payload
        );
        if put_result.error {
            return PullRequestResult(ok=False, error=put_result.error);
        }
    }

    pr_result: ApiSendResult = _api_send(
        f"https://api.github.com/repos/{full_name}/pulls",
        "POST",
        {"title": title, "body": body, "head": branch_name, "base": default_branch}
    );
    if pr_result.error or pr_result.data is None {
        return PullRequestResult(
            ok=False, error=pr_result.error or "GitHub returned no PR data"
        );
    }

    pr: dict = pr_result.data;
    return PullRequestResult(ok=True, pr_number=pr["number"], pr_url=pr["html_url"]);
}
