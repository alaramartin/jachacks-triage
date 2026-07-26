"""GitHub OAuth + PR creation. Owner: Person 2.

Phase B: token exchange + list_repos are real (need GITHUB_CLIENT_ID /
GITHUB_CLIENT_SECRET in .env - see .env.example). create_pull_request is a
STUB returning a fake PR so Person 3 can wire the Generate PR button end to
end before Phase C replaces it with a real GitHub API call (create branch,
commit patch, open PR)."""
import json;
import os;
import from urllib.request { Request, urlopen }
import from urllib.parse { urlencode }
import from urllib.error { HTTPError }

glob GITHUB_CLIENT_ID: str = os.environ.get("GITHUB_CLIENT_ID", "");
glob GITHUB_CLIENT_SECRET: str = os.environ.get("GITHUB_CLIENT_SECRET", "");

obj GithubTokenResult {
    has access_token: str = "";
    has error: str = "";
}

def exchange_code_for_token(code: str) -> GithubTokenResult {
    if not GITHUB_CLIENT_ID or not GITHUB_CLIENT_SECRET {
        return GithubTokenResult(error="GITHUB_CLIENT_ID/GITHUB_CLIENT_SECRET not configured - see .env.example");
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
        return GithubTokenResult(error=body.get("error_description", "no access_token in GitHub response"));
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
        )
        for r in rows
    ];
}

obj PullRequestResult {
    has ok: bool = True;
    has pr_number: int = 0;
    has pr_url: str = "";
    has error: str = "";
}

def _stable_fake_number(seed: str) -> int {
    total: int = 0;
    for ch in seed {
        total += ord(ch);
    }
    return (total % 900) + 100;
}

"""STUB (Phase B) - returns a fake but stable PR number/url so the frontend
can wire the Generate PR button before real GitHub calls exist. Phase C
replaces this body with: create branch -> commit patch -> open PR, keeping
the same signature/return shape so nothing upstream has to change."""
def create_pull_request(full_name: str, title: str, body: str) -> PullRequestResult {
    fake_number: int = _stable_fake_number(full_name + title);
    return PullRequestResult(
        ok=True,
        pr_number=fake_number,
        pr_url=f"https://github.com/{full_name}/pull/{fake_number}"
    );
}
