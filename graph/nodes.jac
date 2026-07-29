"""Single source of truth for the Triage graph schema. See CLAUDE.md #4.
Owner: Person 1. Schema changes go through P1, announce in chat before editing."""

# The logged-in GitHub session. Attaches directly to root (it spans repos, so
# it is deliberately NOT owned by a Repo), and at most one exists at a time -
# github_login upserts it, github_logout deletes it.
node GithubAuth {
    has login: str = "";
    has name: str = "";
    has avatar_url: str = "";
    has access_token: str = "";  # never leaves the server - no walker reports it
    has connected_at: float = 0.0;
    # Set by github_logout. Without it, logging out is a no-op on any machine
    # that has a .env GITHUB_TOKEN: github_status would just re-authenticate
    # from that fallback and the login screen would bounce straight back to
    # /repos. A signed-out node suppresses the fallback until the next login.
    has signed_out: bool = False;
}

node Repo {
    has full_name: str;
    has default_branch: str = "main";
    has file_count: int = 0;
    # Unix ts of the last select_repo on this Repo. get_active_repo picks the
    # max, so a reload of /queue with no ?repo= lands on what you last opened.
    has last_selected: float = 0.0;
    # On-disk path this repo was indexed from (reindex_repo's repo_path).
    # Read by triage/clustering/pr_agent to load real source off disk instead
    # of each hardcoding the "seed/repo" demo convention.
    has repo_path: str = "";
    # GitHub's real open-ISSUE count (pull requests excluded) as of the last
    # select_repo/ingest. -1 = never checked. Stored so get_queue can tell an
    # empty queue apart from an un-ingested one WITHOUT hitting the GitHub API
    # on every read - "this repo has no issues" and "this repo has 40 issues
    # nobody triaged yet" look identical otherwise.
    has open_issue_count: int = -1;
}

node File {
    has path: str;  # e.g. "core/validation.py" - repo-relative, always POSIX slashes
    has language: str = "python";
    has loc: int = 0;
    has blast_radius: int = -1;  # -1 = not yet computed. Written by Agent 2 (blast_radius.jac)
}

node Issue {
    has external_id: str;  # "SEED-01" for seed data, GitHub number for real
    has title: str;
    has body: str;
    has created_at: str;  # ISO8601
    # --- written by Agent 1 (Triage) ---
    has severity: int = 0;  # 1-10, from by llm()
    has estimated_diff_lines: int = 0;  # from by llm()
    has resolution_confidence: float = 0.0;
    has resolution_method: str = "";  # "explicit" | "llm" | "none"
    has root_cause_guess: str = "";
    # --- (reach) social signals, populated by Person 2 from seed data ---
    has reactions: int = 0;
    has comment_velocity: int = 0;
    # --- written by Agent 4 (Ranking) ---
    has urgency: float = 0.0;
}

node Cluster {
    has cluster_key: str;  # == the target File's path. One cluster per code node.
    has title: str = "";  # by llm() summary of the shared root cause
    has root_cause_summary: str = "";
    has blast_radius: int = 0;  # copied from target File by Agent 3/4
    has issue_count: int = 0;
    has urgency: float = 0.0;
    has fix_confidence: float = 0.0;  # how mechanically simple the fix looks, 0.0-1.0
    has proposed_fix_summary: str = "";  # by llm(), set alongside root_cause_summary - powers get_cluster_detail
}

node PullRequest {
    has number: int = 0;
    has url: str = "";
    has status: str = "open";
    has title: str = "";
    has body: str = "";
    has patch: str = "";
}

node Unresolved {  # exactly ONE of these per Repo. The parking lot.
    has count: int = 0;
}

node Settings {  # (reach) one per Repo - weighted ranking, PLAN.md Phase C
    has w_blast: float = 6.0;
    has w_sev: float = 3.0;
    has w_diff: float = 1.0;
    has w_reactions: float = 0.0;
    has w_comment_velocity: float = 0.0;
}

# --- Edges ---
# `owns` fans out to five different node types, so it stays untyped - readers
# narrow with [?:File] / [?:Issue] / etc. at the call site (see jac-node-edge-patterns).
edge owns {}  # Repo -> File | Issue | Cluster | Unresolved | PullRequest | Settings


# Single-target edges are declared with typed endpoints so every traversal
# infers the right node type with no per-read [?:...] filter needed.
edge imports: File --> File {}  # DIRECTION IS CRITICAL. See CLAUDE.md #4.3.

edge resolves_to: Issue --> File {}
edge grouped_in: Issue --> Cluster {}
edge cluster_targets: Cluster --> File {}
edge parked: Unresolved --> Issue {}
edge fixes: PullRequest --> Cluster {}
