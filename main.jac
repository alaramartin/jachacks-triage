"""API surface - every walker:pub endpoint lives here (CLAUDE.md #6).
SHARED FILE - highest merge-conflict risk. One endpoint per person per commit.
Pull before you touch it. Never reformat the whole file. See CLAUDE.md #9."""

import from graph.nodes {
    GithubAuth,
    Repo,
    File,
    Issue,
    Cluster,
    PullRequest,
    Unresolved,
    Settings,
    owns,
    resolves_to,
    parked,
    grouped_in,
    cluster_targets,
    fixes
}
import from integrations.ast_parser { build_code_substrate, count_import_edges }
import from integrations.js_parser { discover_js_files }
import from agents.blast_radius { compute_blast_radius, build_dependency_graph }
import from agents.triage_agent { resolve_issue, assess_severity, estimate_diff_size }
import from agents.ranking {
    on_issue_resolved,
    weighted_urgency,
    weighted_cluster_urgency
}
import from agents.pr_agent {
    build_pr_for_cluster,
    build_pr_for_issue,
    preview_issue_fix,
    IssueFixPreview
}
import os;
import time;
import from integrations.github {
    fetch_open_issues,
    RemoteIssue,
    oauth_configured,
    authorize_url,
    exchange_code_for_token,
    get_authenticated_user,
    GithubUser,
    list_repos,
    get_repo,
    parse_repo_full_name,
    clone_repo,
    count_open_issues,
    RepoSummary,
    CloneResult,
    GITHUB_TOKEN,
    APP_URL
}

# ============================== GitHub session helpers ==============================
# The OAuth token lives on a single root-attached GithubAuth node and is read
# back here, then passed explicitly into integrations/github.jac. Nothing
# reports the token itself - it never crosses the wire to the browser.
# The explicit isinstance re-check is belt-and-braces: with a STALE .jac/cache
# for graph.nodes, `[root-->][?:Type]` silently stops narrowing and hands back
# nodes of the wrong type (a `[?:GithubAuth]` read returning a `Repo`). The
# real fix for that is `rm -rf .jac/cache` after any schema edit (see PLAN.md),
# but re-filtering here costs nothing and turns a crash into an empty result.
def _auth_node() -> GithubAuth | None {
    for n in [root-->][?:GithubAuth] {
        if isinstance(n, GithubAuth) {
            return n;
        }
    }
    return None;
}

def _all_repos() -> list[Repo] {
    return [
        r
        for r in [root-->][?:Repo]
        if isinstance(r, Repo)
    ];
}

def _session_token() -> str {
    auth: GithubAuth | None = _auth_node();
    return auth.access_token if auth is not None else "";
}

def _repo_by_name(name: str) -> Repo | None {
    for r in _all_repos() {
        if r.full_name == name {
            return r;
        }
    }
    return None;
}

"""The Repo that owns `n` (an Issue/Cluster/PullRequest), walking the `owns`
edge backwards. Beats the old `[root-->][?:Repo][0]` assumption now that more
than one repo can be indexed at a time."""
def _owning_repo(n: any) -> Repo | None {
    owners: list[Repo] = [
        o
        for o in [n<-:owns:<-][?:Repo]
        if isinstance(o, Repo)
    ];
    if len(owners) > 0 {
        return owners[0];
    }
    fallback: list[Repo] = _all_repos();
    return fallback[0] if len(fallback) > 0 else None;
}

"""Most recently selected repo - what /queue falls back to when the URL
carries no ?repo=. Returns None before any repo has been picked."""
def _active_repo() -> Repo | None {
    all_repos: list[Repo] = _all_repos();
    if len(all_repos) == 0 {
        return None;
    }
    best: Repo = all_repos[0];
    for r in all_repos {
        if r.last_selected > best.last_selected {
            best = r;
        }
    }
    return best;
}

# ============================== Showcase mode ==============================
# The public JacHammer deploy runs with TRIAGE_SHOWCASE=1. Every by llm() call
# in Triage targets a LOCAL Ollama (jac.toml, agents/pr_agent.jac) and a hosted
# pod has no Ollama and no API key, so in showcase mode the app deliberately
# stops at the repo picker: login and "Your projects" are real and live, and
# every walker that would reach an LLM refuses immediately instead of hanging
# the pod for minutes. Unset locally => nothing below changes behavior at all.
glob SHOWCASE: bool = os.environ.get("TRIAGE_SHOWCASE", "") not in [
         "",
         "0",
         "false"
     ];
glob DEMO_VIDEO_URL: str = os.environ.get("TRIAGE_DEMO_VIDEO_URL", "");

# How long a Repo.ingesting_since lock is honored before being treated as
# abandoned. Generous: a big repo legitimately takes an hour at ~9s/issue.
glob INGEST_LOCK_TIMEOUT: float = 3600.0;

# When this server process started. An ingest lock can only ever be held by a
# run inside THIS process, so any lock predating startup is by definition dead
# - the process was killed or restarted mid-run and its `finally` never ran.
# Without this, a routine Ctrl-C during ingestion locks that repo out for a
# full hour, which is not an acceptable dev-loop failure mode.
glob PROCESS_STARTED_AT: float = time.time();
glob SHOWCASE_MESSAGE: str = "This is the hosted showcase build - triage runs on a local model, so indexing, "
     "clustering and PR generation are disabled here. Watch the demo video instead.";

# ============================== GitHub auth + repo selection ==============================
# Single round trip for the login screen: is anyone logged in, and if not,
# where do we send the browser? `authenticated` is the only thing the client
# gates on; `source` distinguishes a real OAuth session from the .env
# GITHUB_TOKEN fallback (which keeps the demo runnable on a machine where no
# OAuth app has been registered).
walker:pub github_status {
    has redirect_uri: str = "";

    can check with Root entry {
        callback: str = self.redirect_uri if self.redirect_uri else APP_URL;
        auth: GithubAuth | None = _auth_node();

        if auth is not None and auth.signed_out {
            # Explicitly logged out - do NOT fall back to the .env token, or
            # the logout button silently does nothing.
            report {
                "authenticated": False,
                "source": "none",
                "login": "",
                "name": "",
                "avatar_url": "",
                "oauth_configured": oauth_configured(),
                "token_available": bool(GITHUB_TOKEN),
                "showcase": SHOWCASE,
                "demo_video_url": DEMO_VIDEO_URL,
                "authorize_url": authorize_url(callback) if oauth_configured() else ""
            };
            disengage;
        }

        # A node with no token is a cleared session (github_logout, then
        # github_use_env_token) - fall through to the .env fallback below
        # rather than reporting an "oauth" session with an empty login.
        if auth is not None and auth.access_token {
            report {
                "authenticated": True,
                "source": "oauth",
                "login": auth.login,
                "name": auth.name,
                "avatar_url": auth.avatar_url,
                "oauth_configured": oauth_configured(),
                "token_available": bool(GITHUB_TOKEN),
                "showcase": SHOWCASE,
                "demo_video_url": DEMO_VIDEO_URL,
                "authorize_url": authorize_url(callback) if oauth_configured() else ""
            };
            disengage;
        }

        if GITHUB_TOKEN {
            user: GithubUser = get_authenticated_user();
            if not user.error {
                report {
                    "authenticated": True,
                    "source": "token",
                    "login": user.login,
                    "name": user.name,
                    "avatar_url": user.avatar_url,
                    "oauth_configured": oauth_configured(),
                    "token_available": bool(GITHUB_TOKEN),
                    "showcase": SHOWCASE,
                    "demo_video_url": DEMO_VIDEO_URL,
                    "authorize_url": authorize_url(callback)
                        if oauth_configured()
                        else ""
                };
                disengage;
            }
        }

        report {
            "authenticated": False,
            "source": "none",
            "login": "",
            "name": "",
            "avatar_url": "",
            "oauth_configured": oauth_configured(),
            "token_available": bool(GITHUB_TOKEN),
            "showcase": SHOWCASE,
            "demo_video_url": DEMO_VIDEO_URL,
            "authorize_url": authorize_url(callback) if oauth_configured() else ""
        };
    }
}

# Second half of the OAuth dance: the browser comes back to APP_URL with
# ?code=..., the client hands the code here, and we trade it for a token
# server-side (the client secret never reaches the browser).
walker:pub github_login {
    has code: str;
    has redirect_uri: str = "";

    can login with Root entry {
        callback: str = self.redirect_uri if self.redirect_uri else APP_URL;
        exchanged = exchange_code_for_token(self.code, callback);
        if exchanged.error {
            report {"ok": False, "error": exchanged.error};
            disengage;
        }

        user: GithubUser = get_authenticated_user(exchanged.access_token);
        if user.error {
            report {"ok": False, "error": user.error};
            disengage;
        }

        auth: GithubAuth | None = _auth_node();
        if auth is None {
            auth = root ++> GithubAuth();
        }
        auth.login = user.login;
        auth.name = user.name;
        auth.avatar_url = user.avatar_url;
        auth.access_token = exchanged.access_token;
        auth.connected_at = time.time();
        auth.signed_out = False;

        report {
            "ok": True,
            "login": user.login,
            "name": user.name,
            "avatar_url": user.avatar_url
        };
    }
}

# Clears the session rather than deleting the node: the node's `signed_out`
# flag is what stops github_status from re-authenticating off the .env
# GITHUB_TOKEN fallback. Deleting it would make "log out" a no-op on any
# machine that has that token set.
walker:pub github_logout {
    can logout with Root entry {
        auth: GithubAuth | None = _auth_node();
        if auth is None {
            auth = root ++> GithubAuth();
        }
        auth.login = "";
        auth.name = "";
        auth.avatar_url = "";
        auth.access_token = "";
        auth.signed_out = True;
        report {"ok": True};
    }
}

# The way back in after logging out on a machine with no OAuth app registered
# but a .env GITHUB_TOKEN present - it just clears the signed-out flag so the
# fallback applies again. Not a login in any real sense, which is why the
# login screen labels it as the configured token rather than as an account.
walker:pub github_use_env_token {
    can resume with Root entry {
        if not GITHUB_TOKEN {
            report {"ok": False, "error": "no GITHUB_TOKEN configured"};
            disengage;
        }
        auth: GithubAuth | None = _auth_node();
        if auth is not None {
            auth.signed_out = False;
        }
        user: GithubUser = get_authenticated_user();
        if user.error {
            report {"ok": False, "error": user.error};
            disengage;
        }
        report {"ok": True, "login": user.login};
    }
}

# "Your projects" - every repo the logged-in account can actually act on
# (owned, collaborator, or org member), straight from the GitHub API. No
# fabricated list: with no token this reports zero repos and says why.
walker:pub list_my_repos {
    can list with Root entry {
        token: str = _session_token();
        if not token and not GITHUB_TOKEN {
            report {"ok": False, "error": "not logged in", "repos": []};
            disengage;
        }

        indexed: set[str] = {r.full_name for r in _all_repos()};
        rows: list[dict] = [];
        for r in list_repos(token) {
            # `r.open_issues` is GitHub's open_issues_count, which counts PULL
            # REQUESTS as well as issues - a repo with one open PR and no
            # issues reads as "1", which is exactly the confusion this fixes.
            # The real count costs an extra paginated call, so it is only paid
            # when the cheap number is non-zero: issues + PRs == 0 means there
            # are provably no issues, and most repos are in that state.
            real_issues: int = 0;
            if r.open_issues > 0 {
                real_issues = count_open_issues(r.full_name, token);
            }
            rows.append(
                {
                    "full_name": r.full_name,
                    "description": r.description,
                    "language": r.language,
                    "stars": r.stars,
                    "open_issues": real_issues,
                    "private": r.private,
                    "can_push": r.can_push,
                    "default_branch": r.default_branch,
                    "indexed": r.full_name in indexed
                }
            );
        }
        report {"ok": True, "repos": rows};
    }
}

# Point Triage at a repo - one the user owns, or any public repo pasted as a
# link ("choose another repo"). Clones the source so the AST parser has
# something real to walk, then builds the code substrate. Deliberately does
# NOT ingest issues: that costs three LLM calls per issue, so the client runs
# it as a separate, progress-reported step (ingest_from_github).
walker:pub select_repo {
    has repo_url: str;

    can select with Root entry {
        if SHOWCASE {
            report {"ok": False, "error": SHOWCASE_MESSAGE};
            disengage;
        }
        # Collapse any pre-existing duplicate Repo nodes BEFORE looking this
        # one up, so we can't attach files to one node while get_queue reads
        # another. See _collapse_duplicate_repos.
        _collapse_duplicate_repos();

        token: str = _session_token();
        full_name: str = parse_repo_full_name(self.repo_url);
        if not full_name {
            report {
                "ok": False,
                "error": f"couldn't read a repo out of [{self.repo_url}] - try owner/name or a github.com link"
            };
            disengage;
        }

        info: RepoSummary | None = get_repo(full_name, token);
        if info is None {
            report {
                "ok": False,
                # Echo BOTH what was typed and what it parsed to: when a paste
                # drags in surrounding text the two differ visibly, which is
                # far more useful than "check the name".
                # Delimit with brackets, not quotes: a `'` placed directly
                # after a `}` gets eaten by Jac's f-string handling.
                "error": f"GitHub has no repo [{full_name}] (read from your input [{self.repo_url}]) - check the name, or that your account can see it"
            };
            disengage;
        }

        cloned: CloneResult = clone_repo(info.full_name, info.default_branch, token);
        if cloned.error {
            report {"ok": False, "error": cloned.error};
            disengage;
        }

        repo: Repo | None = _repo_by_name(info.full_name);
        if repo is None {
            # NO `[0]` unwrap - see the note in reindex_repo and PLAN.md's
            # environment-split table before "fixing" this either way.
            repo = root ++> Repo(full_name=info.full_name);
        }
        repo.default_branch = info.default_branch;
        repo.repo_path = cloned.path;
        repo.last_selected = time.time();

        already_indexed: list[File] = [repo->:owns:->][?:File];
        files_indexed: int = 0;
        import_edges: int = 0;
        python_files: int = 0;
        js_files: int = 0;
        # A repo indexed BEFORE TypeScript/JS support keeps its Python-only
        # substrate forever, because this branch short-circuits. Rebuild it -
        # but only when doing so destroys nothing: no JS/TS File nodes exist,
        # the checkout actually has some, and no Issue has resolved onto any of
        # these files yet (deleting File nodes would orphan resolves_to edges).
        # A repo that HAS triaged issues keeps its substrate; re-indexing that
        # safely means re-running the cascade, which belongs behind an explicit
        # user action, not a silent side effect of opening the repo.
        stale_substrate: bool = False;
        if len(already_indexed) > 0 {
            indexed_js: int = len([f for f in already_indexed if f.language != "python"]);
            stale_substrate = indexed_js == 0
                and len([repo->:owns:->][?:Issue]) == 0
                and len(discover_js_files(cloned.path)) > 0;
            if stale_substrate {
                for f in already_indexed {
                    del f;
                }
            }
        }

        if len(already_indexed) > 0 and not stale_substrate {
            files_indexed = repo.file_count;
            import_edges = count_import_edges(already_indexed);
            python_files = len([f for f in already_indexed if f.language == "python"]);
            js_files = files_indexed - python_files;
        } else {
            stats: dict[str, int] = build_code_substrate(cloned.path, repo);
            files_indexed = stats["files_indexed"];
            import_edges = stats["import_edges"];
            python_files = stats["python_files"];
            js_files = stats["js_files"];
        }

        # Two things the UI needs to be honest about a repo that isn't yours:
        # a repo in a language we can't parse is an empty queue with no
        # explanation, and a repo you can't push to means PRs will be opened
        # from a fork (integrations/github.jac's create_pull_request).
        warning: str = "";
        if files_indexed == 0 {
            warning = f"{info.full_name} has no Python, TypeScript or JavaScript files to index - those are the languages Triage can build a code graph from, so there's nothing to rank against.";
        }

        # The real issue count, NOT RepoSummary.open_issues - that field
        # includes pull requests and would overstate the queue. Cached onto the
        # Repo so get_queue can explain an empty queue without an API call.
        open_issues: int = count_open_issues(info.full_name, token);
        repo.open_issue_count = open_issues;

        report {
            "ok": True,
            "full_name": info.full_name,
            "default_branch": info.default_branch,
            "description": info.description,
            "files_indexed": files_indexed,
            "import_edges": import_edges,
            "open_issues": open_issues,
            "issues_in_graph": len([repo->:owns:->][?:Issue]),
            "can_push": info.can_push,
            "python_files": python_files,
            "js_files": js_files,
            "warning": warning
        };
    }
}

# Which repo the dashboard should show when the URL doesn't say (a reload of
# /queue, or a direct visit). Most recently selected wins.
walker:pub get_active_repo {
    can pick with Root entry {
        repo: Repo | None = _active_repo();
        if repo is None {
            report {"ok": False, "full_name": "", "file_count": 0};
            disengage;
        }
        report {
            "ok": True,
            "full_name": repo.full_name,
            "file_count": repo.file_count,
            "issues_in_graph": len([repo->:owns:->][?:Issue])
        };
    }
}

# ============================== Person 1 — Graph & Agents ==============================
walker:pub reindex_repo {
    has repo_path: str;
    has full_name: str;

    can build with Root entry {
        if SHOWCASE {
            report {"ok": False, "error": SHOWCASE_MESSAGE};
            disengage;
        }
        _collapse_duplicate_repos();
        existing: list[Repo] = [root-->][?:Repo, full_name==self.full_name];
        repo: Repo;
        if len(existing) > 0 {
            repo = existing[0];
        } else {
            # NO `[0]` here - on the demo machine (jac 0.34.7) `++>` returns the
            # bare node; indexing it fails. P1's and P3's machines return a list
            # and DO need `[0]`. See PLAN.md's environment-split table before
            # "fixing" this in either direction.
            repo = root ++> Repo(full_name=self.full_name);
        }
        # Remember where this repo lives on disk so ingest_issue, clustering
        # and pr_agent can read real source instead of assuming "seed/repo".
        repo.repo_path = self.repo_path;

        already_indexed: list[File] = [repo->:owns:->][?:File];
        if len(already_indexed) > 0 {
            # Idempotent: reindex_repo is safe to call repeatedly during rehearsal
            # without duplicating File nodes or resetting computed blast radii.
            report {
                "ok": True,
                "files_indexed": repo.file_count,
                "import_edges": count_import_edges(already_indexed)
            };
        } else {
            stats: dict[str, int] = build_code_substrate(self.repo_path, repo);
            report {
                "ok": True,
                "files_indexed": stats["files_indexed"],
                "import_edges": stats["import_edges"]
            };
        }
    }
}

walker:pub reset_demo {
    can wipe with Root entry {
        for repo in [root-->][?:Repo] {
            for i in [repo->:owns:->][?:Issue] {
                del i;
            }
            for c in [repo->:owns:->][?:Cluster] {
                del c;
            }
            for p in [repo->:owns:->][?:PullRequest] {
                del p;
            }
            for u in [repo->:owns:->][?:Unresolved] {
                del u;
            }
        }
        report {"ok": True};
    }
}

walker:pub debug_blast {
    has path: str;

    can find with Root entry {
        for repo in [root-->][?:Repo] {
            matches: list[File] = [repo->:owns:->][?:File, path==self.path];
            if len(matches) > 0 {
                report compute_blast_radius(matches[0]);
                disengage;
            }
        }
        report -1;
    }
}

# ======================= Person 2 — Ingestion, LLM & PR action =======================
# Shared by ingest_issue (one issue at a time, e.g. the live-ingestion demo
# beat) and ingest_from_github (a whole repo's open issues at once) so both
# entry points run the exact same Agent 1->2->3->4 cascade and can't drift.
"""The Issue already on `repo` with this external_id, or None.

Checked immediately before each write, NOT once per batch: an ingest run holds
its "already present" snapshot for minutes while it makes three LLM calls per
issue, so a snapshot taken at the start is stale by the time most issues are
written. This is the last line of defence behind the Repo-level ingest lock."""
def _existing_issue(repo: Repo, external_id: str) -> Issue | None {
    if not external_id {
        return None;
    }
    for i in [repo->:owns:->][?:Issue] {
        if i.external_id == external_id {
            return i;
        }
    }
    return None;
}

def _ingest_one(
    repo: Repo,
    external_id: str,
    title: str,
    body: str,
    created_at: str,
    reactions: int,
    comment_velocity: float
) -> dict {
    duplicate: Issue | None = _existing_issue(repo, external_id);
    if duplicate is not None {
        resolved: list[File] = [duplicate->:resolves_to:->][?:File];
        return {
            "issue_id": jid(duplicate),
            "resolved_to": resolved[0].path if len(resolved) > 0 else None,
            "resolution_method": duplicate.resolution_method,
            "skipped_duplicate": True
        };
    }

    files: list[File] = [repo->:owns:->][?:File];
    file_paths: list[str] = [f.path for f in files];

    resolution = resolve_issue(title, body, file_paths, repo_root=repo.repo_path);
    severity: int = assess_severity(title, body);
    diff_lines: int = estimate_diff_size(title, body);

    issue: Issue = Issue(
        external_id=external_id,
        title=title,
        body=body,
        created_at=created_at,
        severity=severity,
        estimated_diff_lines=diff_lines,
        resolution_confidence=resolution.confidence,
        resolution_method=resolution.method,
        reactions=reactions,
        comment_velocity=comment_velocity,
    );
    repo +>:owns:+> issue;

    if resolution.path is None {
        unresolved_matches: list[Unresolved] = [repo->:owns:->][?:Unresolved];
        unresolved: Unresolved;
        if len(unresolved_matches) > 0 {
            unresolved = unresolved_matches[0];
        } else {
            unresolved = Unresolved();
            repo +>:owns:+> unresolved;
        }
        unresolved +>:parked:+> issue;
        unresolved.count += 1;
        return {
            "issue_id": jid(issue),
            "resolved_to": None,
            "resolution_method": "none",
            "parked": True
        };
    }

    target_matches: list[File] = [
        f
        for f in files
        if f.path == resolution.path
    ];
    target: File = target_matches[0];
    issue +>:resolves_to:+> target;

    # Agent 2 -> 3 -> 4 cascade (blast radius -> clustering -> ranking),
    # triggered the same way CLAUDE.md #5 describes: writing the resolves_to
    # edge, then downstream agents re-read graph state fresh rather than
    # being handed values directly.
    on_issue_resolved(issue, target, repo);

    clustered_into: str | None = None;
    issue_clusters: list[Cluster] = [issue->:grouped_in:->];
    if len(issue_clusters) > 0 {
        clustered_into = issue_clusters[0].cluster_key;
    }

    return {
        "issue_id": jid(issue),
        "resolved_to": target.path,
        "resolution_method": resolution.method,
        "confidence": resolution.confidence,
        "severity": severity,
        "clustered_into": clustered_into,
        "urgency": issue.urgency
    };
}

walker:pub ingest_issue {
    has external_id: str;
    has title: str;
    has body: str;
    has created_at: str;
    has reactions: int = 0;
    has comment_velocity: float = 0.0;
    # Which indexed repo this issue belongs to; defaults to the most recently
    # selected one, which is what the live-ingestion demo beat wants.
    has full_name: str = "";

    can ingest with Root entry {
        if SHOWCASE {
            report {"ok": False, "error": SHOWCASE_MESSAGE};
            disengage;
        }
        repo: Repo | None = _repo_by_name(self.full_name)
            if self.full_name
            else _active_repo();
        if repo is None {
            report {"ok": False, "error": "no repo indexed - call select_repo first"};
            disengage;
        }

        report _ingest_one(
            repo,
            self.external_id,
            self.title,
            self.body,
            self.created_at,
            self.reactions,
            self.comment_velocity
        );
    }
}

# Pulls a repo's OPEN issues straight from the GitHub REST API and runs each
# one through the same Agent 1 cascade as ingest_issue - this is what lets
# Triage point at any real repo's real issue queue instead of a canned
# issues.json fixture (CLAUDE.md's "nothing should be hardcoded" rule).
# Safe to call repeatedly: issues already present (matched by external_id,
# which is the GitHub issue number) are skipped rather than duplicated.
walker:pub ingest_from_github {
    has full_name: str = "";
    # 0 = every open issue (what the seed repo wants). The client caps this
    # when you point Triage at a big public repo, because each issue costs
    # three local LLM calls - 400 of them is an hour, not a demo.
    has limit: int = 0;
    # Escape hatch for a lock this process genuinely believes is live but
    # isn't. Deliberately NOT wired to the UI - two concurrent ingests is the
    # bug this lock exists to prevent.
    has force: bool = False;

    can ingest with Root entry {
        if SHOWCASE {
            report {"ok": False, "error": SHOWCASE_MESSAGE};
            disengage;
        }
        repo: Repo | None = _repo_by_name(self.full_name)
            if self.full_name
            else _active_repo();
        if repo is None {
            report {
                "ok": False,
                "error": "that repo isn't indexed yet - run select_repo (or reindex_repo) first"
            };
            disengage;
        }
        target_full_name: str = repo.full_name;

        # One ingest per repo at a time. Without this, a retried request or a
        # second click starts a run whose "already ingested" view is minutes
        # stale, and every issue the first run hasn't reached yet gets written
        # twice. Observed in the wild: 20 GitHub issues -> 64 Issue nodes.
        now: float = time.time();
        lock_is_live: bool = repo.ingesting_since > PROCESS_STARTED_AT
            and (now - repo.ingesting_since) < INGEST_LOCK_TIMEOUT;
        if lock_is_live and not self.force {
            report {
                "ok": False,
                "error": f"{target_full_name} is already being triaged - wait for that run to finish",
                "already_ingesting": True
            };
            disengage;
        }
        repo.ingesting_since = now;

        results: list[dict] = [];
        skipped: int = 0;
        remote_issues: list[RemoteIssue] = [];
        try {
            remote_issues = fetch_open_issues(
                target_full_name, self.limit, _session_token()
            );
            for ri in remote_issues {
                outcome: dict = _ingest_one(
                    repo,
                    ri.external_id,
                    ri.title,
                    ri.body,
                    ri.created_at,
                    ri.reactions,
                    ri.comment_velocity
                );
                # _ingest_one re-checks per issue and reports rather than
                # writing when the issue is already here, so the skip count
                # stays accurate without a separate pre-pass snapshot.
                if outcome.get("skipped_duplicate", False) {
                    skipped += 1;
                } else {
                    results.append(outcome);
                }
            }
        } finally {
            # Always release, including on a mid-run failure - a stuck lock
            # would make the repo permanently un-ingestable until it aged out.
            repo.ingesting_since = 0.0;
        }

        # An uncapped run just enumerated the repo's entire open-issue list, so
        # it is the freshest count we will ever have. A capped run saw only a
        # slice and must not overwrite it.
        if self.limit <= 0 {
            repo.open_issue_count = len(remote_issues);
        }

        report {
            "ok": True,
            "repo": target_full_name,
            "fetched": len(remote_issues),
            "ingested": len(results),
            "skipped_existing": skipped,
            "results": results
        };
    }
}

# generate_pr is human-triggered ONLY (CLAUDE.md #2: no automatic PR generation).
# All GitHub-specific + LLM-fix domain logic lives in agents/pr_agent.jac
# (Person 2) - this walker just resolves the cluster/repo and reports the result.
walker:pub generate_pr {
    has cluster_id: str;

    can generate with Root entry {
        if SHOWCASE {
            report {"ok": False, "error": SHOWCASE_MESSAGE};
            disengage;
        }
        cluster: any = None;
        try {
            cluster = jobj(self.cluster_id);
        } except Exception {
            cluster = None;
        }
        if not isinstance(cluster, Cluster) {
            report {"ok": False, "error": "cluster not found"};
            disengage;
        }

        repo: Repo | None = _owning_repo(cluster);
        if repo is None {
            report {"ok": False, "error": "no repo indexed"};
            disengage;
        }

        targets: list[File] = [cluster->:cluster_targets:->][?:File];
        target_path: str = cluster.cluster_key;
        if len(targets) > 0 {
            target_path = targets[0].path;
        }

        result = build_pr_for_cluster(cluster, repo, _session_token());
        if not result.ok {
            report {"ok": False, "error": result.error};
            disengage;
        }

        title: str = f"fix: {cluster.cluster_key}";
        if cluster.title {
            title = f"fix({target_path}): {cluster.title}";
        }

        pr: PullRequest = PullRequest(
            number=result.pr_number,
            url=result.pr_url,
            status="open",
            title=title,
            body=cluster.root_cause_summary,
        );
        repo +>:owns:+> pr;
        pr +>:fixes:+> cluster;

        report {
            "ok": True,
            "pr_number": result.pr_number,
            "pr_url": result.pr_url,
            "title": title,
            "files_changed": [target_path],
            # True when we had no push access and contributed from a fork.
            "forked": result.forked,
            "head_repo": result.head_repo
        };
    }
}

# Same human-only trigger as generate_pr, for a standalone issue that never
# clustered. The cluster stays the headline unit of action (CLAUDE.md #2) -
# this just means a lone issue isn't a dead end in the UI.
walker:pub generate_pr_for_issue {
    has issue_id: str;

    can generate with Root entry {
        if SHOWCASE {
            report {"ok": False, "error": SHOWCASE_MESSAGE};
            disengage;
        }
        issue: any = None;
        try {
            issue = jobj(self.issue_id);
        } except Exception {
            issue = None;
        }
        if not isinstance(issue, Issue) {
            report {"ok": False, "error": "issue not found"};
            disengage;
        }

        repo: Repo | None = _owning_repo(issue);
        if repo is None {
            report {"ok": False, "error": "no repo indexed"};
            disengage;
        }

        targets: list[File] = [issue->:resolves_to:->][?:File];
        target_path: str = targets[0].path if len(targets) > 0 else "";

        result = build_pr_for_issue(issue, repo, _session_token());
        if not result.ok {
            report {"ok": False, "error": result.error};
            disengage;
        }

        title: str = f"fix({target_path}): {issue.title}"
            if target_path
            else f"fix: {issue.title}";

        pr: PullRequest = PullRequest(
            number=result.pr_number,
            url=result.pr_url,
            status="open",
            title=title,
            body=issue.title,
        );
        repo +>:owns:+> pr;
        # CLAUDE.md #4.2 documents `fixes` as PullRequest -> Cluster; a
        # standalone issue has no Cluster, so the same edge lands on the Issue.
        # Nothing reads it in the other direction, so this is additive.
        pr +>:fixes:+> issue;

        report {
            "ok": True,
            "pr_number": result.pr_number,
            "pr_url": result.pr_url,
            "title": title,
            "files_changed": [target_path],
            "forked": result.forked,
            "head_repo": result.head_repo
        };
    }
}

# Powers the hover card on the queue's standalone rows: two sentences, "the
# issue" and "the fix". Same by llm() call generate_pr_for_issue uses to derive
# a root cause, so what you read on hover is what the PR gets built from.
walker:pub get_issue_fix_preview {
    has issue_id: str;

    can preview with Root entry {
        if SHOWCASE {
            report {"ok": False, "error": SHOWCASE_MESSAGE};
            disengage;
        }
        issue: any = None;
        try {
            issue = jobj(self.issue_id);
        } except Exception {
            issue = None;
        }
        if not isinstance(issue, Issue) {
            report {"ok": False, "error": "issue not found"};
            disengage;
        }

        targets: list[File] = [issue->:resolves_to:->][?:File];
        if len(targets) == 0 {
            report {"ok": False, "error": "issue isn't resolved onto a file"};
            disengage;
        }

        # Same rule as generate_pr: an LLM failure is a reported error, never a
        # 500 that leaves the client hanging.
        try {
            preview: IssueFixPreview = preview_issue_fix(
                targets[0].path, issue.title, issue.body
            );
        } except Exception as e {
            report {"ok": False, "error": f"couldn't reach the model: {e}"};
            disengage;
        }
        report {
            "ok": True,
            "issue_summary": preview.issue_summary,
            "fix_summary": preview.fix_summary
        };
    }
}

# ======================= Person 1 — Queue + Cluster Detail (Phase B/C) =======================
obj IssueSummary {
    has id: str;
    has external_id: str;
    has title: str;
    has severity: int;
    has resolution_method: str;
}

obj ClusterView {
    has id: str;
    has title: str;
    has target_path: str;
    has blast_radius: int;
    has issue_count: int;
    has max_severity: int;
    has urgency: float;
    has fix_confidence: float;
    has issues: list[IssueSummary];
    # A PR already drafted for this cluster (via the `fixes` edge). Empty url
    # means none - the UI files those with a PR into its "Drafted PRs" section,
    # so the state survives a page reload instead of living only in React.
    has pr_number: int = 0;
    has pr_url: str = "";
}

obj SingletonView {
    has id: str;
    has external_id: str;
    has title: str;
    has target_path: str;
    has blast_radius: int;
    has severity: int;
    has urgency: float;
    has resolution_method: str;
    has pr_number: int = 0;
    has pr_url: str = "";
}

obj UnresolvedView {
    has id: str;
    has external_id: str;
    has title: str;
}

"""The repo's stored ranking weights, echoed back with the queue they ranked.

Sent WITH the queue rather than from a separate endpoint so the panel opens on
what actually produced the order on screen - the sliders used to mount on
hardcoded defaults, so a saved preference silently reverted on every reload
and the displayed positions could disagree with the real ranking."""
obj WeightsView {
    has w_blast: float;
    has w_sev: float;
    has w_diff: float;
    has w_reactions: float;
    has w_comment_velocity: float;
}

def _weights_view(s: Settings) -> WeightsView {
    return WeightsView(
        w_blast=s.w_blast,
        w_sev=s.w_sev,
        w_diff=s.w_diff,
        w_reactions=s.w_reactions,
        w_comment_velocity=s.w_comment_velocity
    );
}

obj QueueResponse {
    has repo: str;
    has file_count: int;
    has clusters: list[ClusterView];
    has singletons: list[SingletonView];
    has unresolved: list[UnresolvedView];
    has weights: WeightsView;
    # GitHub's real open-issue count as of the last select/ingest, or -1 if
    # never checked. Lets the UI say WHY a queue is empty - no issues exist vs
    # issues exist but none have been triaged - instead of rendering nothing.
    has open_issue_count: int = -1;
}

walker:pub get_queue {
    has full_name: str;
    has reports: list[QueueResponse] = [];

    can build with Root entry {
        matches: list[Repo] = [root-->][?:Repo, full_name==self.full_name];
        if len(matches) == 0 {
            report QueueResponse(
                repo=self.full_name,
                file_count=0,
                clusters=[],
                singletons=[],
                unresolved=[],
                weights=_weights_view(Settings()),
                open_issue_count=-1
            );
            disengage;
        }
        repo: Repo = matches[0];

        all_issues: list[Issue] = [repo->:owns:->][?:Issue];
        all_clusters: list[Cluster] = [repo->:owns:->][?:Cluster];

        # (REACH, PLAN.md Phase C step 3) Read-time re-rank against the repo's
        # current Settings - defaults to the locked blast-dominant weights if
        # set_weights was never called. Never touches the stored Issue/Cluster
        # .urgency (that stays whatever the ingest-time cascade wrote), so the
        # demo's default numbers are unaffected unless a viewer moves sliders.
        settings_matches: list[Settings] = [repo->:owns:->][?:Settings];
        settings: Settings = settings_matches[0]
            if len(settings_matches) > 0
            else Settings();
        max_reactions: int = max([i.reactions for i in all_issues], default=0);
        max_comment_velocity: float = max(
            [i.comment_velocity for i in all_issues], default=0.0
        );

        cluster_views: list[ClusterView] = [];
        clustered_issue_ids: set[str] = set();

        for c in all_clusters {
            targets: list[File] = [c->:cluster_targets:->];
            target_path: str = targets[0].path if len(targets) > 0 else "";
            members: list[Issue] = [c<-:grouped_in:<-];
            issue_views: list[IssueSummary] = [];
            max_sev: int = 0;
            for m in members {
                clustered_issue_ids.add(jid(m));
                if m.severity > max_sev {
                    max_sev = m.severity;
                }
                issue_views.append(
                    IssueSummary(
                        id=jid(m),
                        external_id=m.external_id,
                        title=m.title,
                        severity=m.severity,
                        resolution_method=m.resolution_method
                    )
                );
            }
            cluster_urgency: float = weighted_cluster_urgency(
                c.blast_radius,
                members,
                repo.file_count,
                max_reactions,
                max_comment_velocity,
                settings
            )
                if len(members) > 0
                else c.urgency;
            cluster_prs: list[PullRequest] = [c<-:fixes:<-][?:PullRequest];
            cluster_views.append(
                ClusterView(
                    id=jid(c),
                    title=c.title,
                    target_path=target_path,
                    blast_radius=c.blast_radius,
                    issue_count=c.issue_count,
                    max_severity=max_sev,
                    urgency=cluster_urgency,
                    fix_confidence=c.fix_confidence,
                    issues=issue_views,
                    pr_number=cluster_prs[0].number if len(cluster_prs) > 0 else 0,
                    pr_url=cluster_prs[0].url if len(cluster_prs) > 0 else ""
                )
            );
        }
        cluster_views.sort(
            key=lambda (c: ClusterView) { return c.urgency; }, reverse=True
        );

        singleton_views: list[SingletonView] = [];
        unresolved_views: list[UnresolvedView] = [];

        for i in all_issues {
            if jid(i) in clustered_issue_ids {
                continue;
            }
            resolved: list[File] = [i->:resolves_to:->];
            if len(resolved) > 0 {
                singleton_urgency: float = weighted_urgency(
                    resolved[0].blast_radius,
                    i.severity,
                    i.estimated_diff_lines,
                    i.reactions,
                    i.comment_velocity,
                    repo.file_count,
                    max_reactions,
                    max_comment_velocity,
                    settings
                );
                issue_prs: list[PullRequest] = [i<-:fixes:<-][?:PullRequest];
                singleton_views.append(
                    SingletonView(
                        id=jid(i),
                        external_id=i.external_id,
                        title=i.title,
                        target_path=resolved[0].path,
                        blast_radius=resolved[0].blast_radius,
                        severity=i.severity,
                        urgency=singleton_urgency,
                        resolution_method=i.resolution_method,
                        pr_number=issue_prs[0].number if len(issue_prs) > 0 else 0,
                        pr_url=issue_prs[0].url if len(issue_prs) > 0 else ""
                    )
                );
            } else {
                unresolved_views.append(
                    UnresolvedView(id=jid(i), external_id=i.external_id, title=i.title)
                );
            }
        }
        singleton_views.sort(
            key=lambda (s: SingletonView) { return s.urgency; }, reverse=True
        );

        report QueueResponse(
            repo=repo.full_name,
            file_count=repo.file_count,
            clusters=cluster_views,
            singletons=singleton_views,
            unresolved=unresolved_views,
            weights=_weights_view(settings),
            open_issue_count=repo.open_issue_count
        );
    }
}

# (REACH, PLAN.md Phase C step 3) Writes the repo's personalization weights;
# get_queue re-ranks its response against whatever is stored here. The
# ingest-time cascade (on_issue_resolved) never reads this - the demo's
# stored urgency stays blast-dominant-by-default regardless of slider state.
walker:pub set_weights {
    has full_name: str;
    has w_blast: float = 6.0;
    has w_sev: float = 3.0;
    has w_diff: float = 1.0;
    has w_reactions: float = 0.0;
    has w_comment_velocity: float = 0.0;

    can build with Root entry {
        matches: list[Repo] = [root-->][?:Repo, full_name==self.full_name];
        if len(matches) == 0 {
            report {"ok": False, "error": "no repo indexed - call reindex_repo first"};
            disengage;
        }
        repo: Repo = matches[0];

        settings_matches: list[Settings] = [repo->:owns:->][?:Settings];
        settings: Settings = settings_matches[0]
            if len(settings_matches) > 0
            else repo +>:owns:+> Settings();

        settings.w_blast = self.w_blast;
        settings.w_sev = self.w_sev;
        settings.w_diff = self.w_diff;
        settings.w_reactions = self.w_reactions;
        settings.w_comment_velocity = self.w_comment_velocity;

        report {
            "ok": True,
            "w_blast": settings.w_blast,
            "w_sev": settings.w_sev,
            "w_diff": settings.w_diff,
            "w_reactions": settings.w_reactions,
            "w_comment_velocity": settings.w_comment_velocity
        };
    }
}

obj IssueDetail {
    has id: str;
    has external_id: str;
    has title: str;
    has body: str;
    has severity: int;
    has resolution_method: str;
}

obj ClusterDetailResponse {
    has id: str;
    has title: str;
    has root_cause_summary: str;
    has target_path: str;
    has blast_radius: int;
    has urgency: float;
    has fix_confidence: float;
    has proposed_fix_summary: str;
    has issues: list[IssueDetail];
    has graph: dict[str, list];
    has existing_pr: dict[str, object] | None;
}

walker:pub get_cluster_detail {
    has cluster_id: str;

    can build with Root entry {
        all_repos: list[Repo] = [root-->][?:Repo];
        matches: list[Cluster] = [];

        for r in all_repos {
            for c in [r->:owns:->][?:Cluster] {
                if jid(c) == self.cluster_id {
                    matches.append(c);
                }
            }
        }

        if len(matches) > 0 {
            cluster: Cluster = matches[0];
            targets: list[File] = [cluster->:cluster_targets:->];

            if len(targets) > 0 {
                target: File = targets[0];

                members: list[Issue] = [cluster<-:grouped_in:<-];
                issue_views: list[IssueDetail] = [];
                for m in members {
                    issue_views.append(
                        IssueDetail(
                            id=jid(m),
                            external_id=m.external_id,
                            title=m.title,
                            body=m.body,
                            severity=m.severity,
                            resolution_method=m.resolution_method
                        )
                    );
                }

                prs: list[PullRequest] = [cluster<-:fixes:<-][?:PullRequest];
                existing_pr: dict[str, object] | None = None;
                if len(prs) > 0 {
                    p: PullRequest = prs[0];
                    existing_pr = {
                        "number": p.number,
                        "url": p.url,
                        "status": p.status,
                        "title": p.title
                    };
                }

                report ClusterDetailResponse(
                    id=jid(cluster),
                    title=cluster.title,
                    root_cause_summary=cluster.root_cause_summary,
                    target_path=target.path,
                    blast_radius=cluster.blast_radius,
                    urgency=cluster.urgency,
                    fix_confidence=cluster.fix_confidence,
                    proposed_fix_summary=cluster.proposed_fix_summary,
                    issues=issue_views,
                    graph=build_dependency_graph(target),
                    existing_pr=existing_pr
                );
                disengage;
            }
        }

        report {"ok": False, "error": "cluster not found"};
    }
}

# ======================= Person 3 — Client entry point =======================
cl {
    import ".client/global.css";
    import from .client.app { app as ClientApp }

    def:pub app -> JsxElement {
        return <ClientApp/>;
    }
}

# Maintenance: collapse duplicate Repo nodes sharing a full_name, keeping the
# richest one (most issues, then most files) and deleting the rest along with
# everything they own. Duplicates get created when the "does this repo already
# exist?" check comes back empty against a STALE .jac/cache - see PLAN.md. The
# symptom is get_queue and get_active_repo disagreeing about the same repo -
# or, as seen on AzizAkturin/TeamSnorlax-UX-Agent, select_repo indexing 19
# files onto one node while get_queue reads "0 files" off the other.
"""Shared by the dedupe_repos walker and by select_repo/reindex_repo, which
run it BEFORE looking a repo up - collapsing on write is what stops the
duplicate being observable at all, rather than only cleaning up after."""
def _collapse_duplicate_repos() -> list[dict] {
    by_name: dict[str, list[Repo]] = {};
    for r in _all_repos() {
        if r.full_name not in by_name {
            by_name[r.full_name] = [];
        }
        by_name[r.full_name].append(r);
    }

    removed: list[dict] = [];
    for (name, group) in by_name.items() {
        if len(group) < 2 {
            continue;
        }
        keeper: Repo = group[0];
        for r in group {
            r_issues: int = len([r->:owns:->][?:Issue]);
            k_issues: int = len([keeper->:owns:->][?:Issue]);
            if r_issues > k_issues
            or (r_issues == k_issues and r.file_count > keeper.file_count) {
                keeper = r;
            }
        }
        keeper_id: str = jid(keeper);
        for r in group {
            if jid(r) == keeper_id {
                continue;
            }
            # Collect BEFORE deleting - deleting while walking the `owns`
            # edges invalidates the edge anchors mid-iteration.
            doomed: list = [n for n in [r->:owns:->]];
            for n in doomed {
                del n;
            }
            removed.append({"full_name": name, "owned_nodes_deleted": len(doomed)});
            del r;
        }
    }
    return removed;
}

walker:pub dedupe_repos {
    can go with Root entry {
        removed: list[dict] = _collapse_duplicate_repos();
        report {"ok": True, "duplicates_removed": len(removed), "detail": removed};
    }
}

# Maintenance: the repair half of the ingest-duplication fix. The lock and the
# per-issue re-check stop NEW duplicates; this cleans up a graph that already
# has them (20 real GitHub issues had become 64 Issue nodes). Keeps one Issue
# per external_id per repo - the one that resolved onto a file, preferentially,
# since a duplicate that parked as Unresolved carries less information - then
# repairs the cluster counts the deletions invalidate.
walker:pub dedupe_issues {
    can go with Root entry {
        _collapse_duplicate_repos();

        removed_total: int = 0;
        detail: list[dict] = [];
        for repo in _all_repos() {
            by_external: dict[str, list[Issue]] = {};
            for i in [repo->:owns:->][?:Issue] {
                key: str = i.external_id;
                if key not in by_external {
                    by_external[key] = [];
                }
                by_external[key].append(i);
            }

            removed_here: int = 0;
            for (external_id, group) in by_external.items() {
                if len(group) < 2 {
                    continue;
                }
                # Prefer a copy that actually resolved onto a code node; among
                # equals the first wins, so the surviving node is stable.
                keeper: Issue = group[0];
                for i in group {
                    if len([i->:resolves_to:->]) > 0
                    and len([keeper->:resolves_to:->]) == 0 {
                        keeper = i;
                    }
                }
                keeper_id: str = jid(keeper);
                doomed: list[Issue] = [
                    i
                    for i in group
                    if jid(i) != keeper_id
                ];
                for i in doomed {
                    del i;
                }
                removed_here += len(doomed);
            }

            # Deleting members leaves every cluster's issue_count overstated,
            # which is what the UI actually renders ("12 issues" over 5 rows).
            for c in [repo->:owns:->][?:Cluster] {
                members: list[Issue] = [c<-:grouped_in:<-];
                if len(members) == 0 {
                    del c;
                    continue;
                }
                c.issue_count = len(members);
            }

            # Same for the parking lot's counter.
            for u in [repo->:owns:->][?:Unresolved] {
                u.count = len([u->:parked:->]);
            }

            if removed_here > 0 {
                detail.append(
                    {
                        "full_name": repo.full_name,
                        "issues_deleted": removed_here,
                        "issues_remaining": len([repo->:owns:->][?:Issue])
                    }
                );
                removed_total += removed_here;
            }
        }

        report {"ok": True, "issues_deleted": removed_total, "detail": detail};
    }
}
