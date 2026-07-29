"""The ranked queue - the most important screen (CLAUDE.md 8, beat 2).

LIVE DATA: walker/get_queue on mount, walker/set_weights when a ranking slider
moves (then a refetch), walker/generate_pr on click. No client-side sort - the
order here IS the order get_queue returns, clusters/singletons already ranked by
urgency descending.
"""

# __invalidateEndpoint is the jac client runtime's cache control. It is needed
# here because the runtime caches every NON-writer walker response for 60s
# (`defaultTtlMs`, client_runtime_core.js) keyed by walker + args - so a poll
# calling get_queue with the same full_name just gets handed the first
# response back, and the queue looked frozen until a hard reload dropped the
# whole JS cache. The runtime only auto-invalidates when a WRITER runs in this
# same tab; our background ingest writes on the server for minutes after its
# one client call, so nothing ever clears it. See load_queue below.
import from "@jac/runtime" { useNavigate, useLocation, __invalidateEndpoint }
import from react { useEffect }
sv import from ...main {
    get_queue,
    generate_pr,
    generate_pr_for_issue,
    set_weights,
    get_active_repo
}
import from ..components.ClusterRow { ClusterRow }
import from ..components.SingletonRow { SingletonRow }
import from ..components.SettingsPanel { SettingsPanel }

# Which repo this dashboard is showing comes from the URL the repo picker
# navigated to (/queue?repo=owner/name); a bare /queue (reload, direct visit)
# falls back to walker/get_active_repo - the most recently selected one. No
# repo name is hardcoded anywhere on this screen.
# The repo picker appends &ingesting=1 when it kicked off a background
# ingest, which is this screen's cue to keep refetching while issues land.
def _is_ingesting(search: str) -> bool {
    return "ingesting=1" in search;
}

def _repo_from_search(search: str) -> str {
    raw = search[1:] if search.startswith("?") else search;
    for part in raw.split("&") {
        if part.startswith("repo=") {
            return part[5:].replace("%2F", "/");
        }
    }
    return "";
}

def _issue_summary_to_dict(i: any) -> dict {
    return {
        "id": i.id,
        "external_id": i.external_id,
        "title": i.title,
        "severity": i.severity,
        "resolution_method": i.resolution_method
    };
}

def _cluster_to_dict(c: any) -> dict {
    return {
        "id": c.id,
        "title": c.title,
        "target_path": c.target_path,
        "blast_radius": c.blast_radius,
        "issue_count": c.issue_count,
        "max_severity": c.max_severity,
        "urgency": c.urgency,
        "fix_confidence": c.fix_confidence,
        "issues": [_issue_summary_to_dict(i) for i in c.issues],
        "pr_number": c.pr_number,
        "pr_url": c.pr_url
    };
}

def _singleton_to_dict(s: any) -> dict {
    return {
        "id": s.id,
        "external_id": s.external_id,
        "title": s.title,
        "target_path": s.target_path,
        "blast_radius": s.blast_radius,
        "severity": s.severity,
        "urgency": s.urgency,
        "resolution_method": s.resolution_method,
        "parked": False,
        "pr_number": s.pr_number,
        "pr_url": s.pr_url
    };
}

# Parked issues live at the bottom of the same standalone list rather than in a
# panel of their own. They resolved onto no file, so there is no blast radius,
# urgency or severity to show - SingletonRow renders "-" for each of those and
# drops the PR button, since there's no code node to patch.
def _unresolved_to_dict(u: any) -> dict {
    return {
        "id": u.id,
        "external_id": u.external_id,
        "title": u.title,
        "target_path": "",
        "blast_radius": 0,
        "severity": 0,
        "urgency": 0.0,
        "resolution_method": "none",
        "parked": True,
        "pr_number": 0,
        "pr_url": ""
    };
}

def:pub QueueScreen -> JsxElement {
    has queue: dict | None = None,
        loading: bool = True,
        load_error: str | None = None,
        expanded_id: str | None = None,
        pr_result: dict | None = None,
        settings_open: bool = False,
        active_repo: str = "",
        # Background-ingest polling. `stable_polls` counts consecutive refetches
        # that saw no new issues; three in a row means ingestion has finished
        # (or died), so we stop refetching rather than poll forever.
        ingesting: bool = False,
        issue_total: int = -1,
        stable_polls: int = 0,
        # Bumped by every poll so the polling effect's dependency list always
        # changes and it re-arms with fresh state - even on a failed refetch,
        # which changes neither issue_total nor stable_polls.
        poll_tick: int = 0,
        # id -> True while its walker is in flight, so the button can show a
        # spinner. Drafting a PR takes ten-plus seconds (real source read, a
        # full-file by llm() rewrite, then the GitHub call).
        generating: dict = {},
        w_blast: float = 6.0,
        w_sev: float = 3.0,
        w_diff: float = 1.0;

    nav = useNavigate();
    location = useLocation();

    async def load_queue(full_name: str) {
        if not full_name {
            load_error = "No repository selected yet - pick one from Your projects.";
            loading = False;
            return;
        }
        # Always go to the server. Without this the 60s client-side response
        # cache makes every poll a no-op and the "refreshes as they land"
        # promise on screen is a lie.
        __invalidateEndpoint("walker:get_queue");
        result = root spawn get_queue(full_name=full_name);
        if result.reports and len(result.reports) > 0 {
            resp = result.reports[0];
            queue = {
                "repo": resp.repo,
                "file_count": resp.file_count,
                "open_issue_count": resp.open_issue_count,
                "clusters": [_cluster_to_dict(c) for c in resp.clusters],
                "singletons": [_singleton_to_dict(s) for s in resp.singletons],
                "unresolved": [_unresolved_to_dict(u) for u in resp.unresolved]
            };
            seen = len(resp.singletons) + len(resp.unresolved);
            for c in resp.clusters {
                seen = seen + len(c.issues);
            }
            if seen == issue_total {
                stable_polls = stable_polls + 1;
            } else {
                stable_polls = 0;
            }
            issue_total = seen;
        } else {
            load_error = "Couldn't reach the server - is reindex_repo done?";
        }
        loading = False;
    }

    async can with entry {
        name = _repo_from_search(location.search);
        if not name {
            active = root spawn get_active_repo();
            if active.reports and len(active.reports) > 0 {
                name = active.reports[0]["full_name"];
            }
        }
        active_repo = name;
        ingesting = _is_ingesting(location.search);
        await load_queue(name);
    }

    # Refetch every 5s while a background ingest is running, so issues appear
    # in the ranked queue as they are triaged instead of after a blank wait.
    #
    # A single-shot setTimeout that RE-ARMS itself through the dependency list,
    # not a setInterval. A long-lived interval callback closes over the state
    # values from the render that created it and never sees another one - the
    # previous version's `stable_polls >= 3` stop condition read a permanently
    # stale 0 and so could never fire, leaving the poll running forever. Here
    # every poll bumps `poll_tick`, which is a dependency, so the effect tears
    # down and re-runs with current state each time and the stop condition is
    # evaluated against real values.
    useEffect(
        lambda {
            if not ingesting {
                return lambda { None; };
            }
            # Three consecutive refetches that saw no new issue = ingestion has
            # finished (or died). Stop, and drop the banner.
            if stable_polls >= 3 {
                ingesting = False;
                return lambda { None; };
            }
            timer = setTimeout(
                lambda {
                    poll_tick = poll_tick + 1;
                    load_queue(active_repo);
                },
                5000
            );
            return lambda { clearTimeout(timer); };
        },
        [ingesting, active_repo, issue_total, stable_polls, poll_tick]
    );

    def toggle_cluster(cluster_id: str) {
        expanded_id = None if expanded_id == cluster_id else cluster_id;
    }

    def mark_generating(target_id: str, on: bool) {
        next_generating: dict = {};
        for (k, v) in generating.items() {
            next_generating[k] = v;
        }
        if on {
            next_generating[target_id] = True;
        } else {
            next_generating[target_id] = False;
        }
        generating = next_generating;
    }

    # On success we refetch rather than patching state by hand: get_queue now
    # reports pr_number/pr_url off the `fixes` edge, so the row moves itself
    # into Drafted PRs and stays there across a reload.
    # The result banner (PR opened, or the reason it wasn't) renders at the top
    # of the page, but the button that triggered it can be far down a long
    # queue - so without this the click appears to do nothing. Generation takes
    # over a minute, which makes a silent finish especially confusing.
    def scroll_to_banner {
        window.scrollTo({"top": 0, "behavior": "smooth"});
    }

    # The `finally` is load-bearing: if the walker 500s, `root spawn` throws,
    # and without it mark_generating(id, False) never runs - the button sits on
    # "Generating" forever with nothing on screen explaining why. That is
    # precisely how the broken fix model presented for weeks.
    async def handle_generate_pr(cluster_id: str) {
        mark_generating(cluster_id, True);
        try {
            result = root spawn generate_pr(cluster_id=cluster_id);
            if result.reports and len(result.reports) > 0 {
                pr_result = result.reports[0] as dict;
                scroll_to_banner();
            }
            await load_queue(active_repo);
        } except Exception as e {
            pr_result = {"ok": False, "error": str(e)};
            scroll_to_banner();
        } finally {
            mark_generating(cluster_id, False);
        }
    }

    async def handle_generate_issue_pr(issue_id: str) {
        mark_generating(issue_id, True);
        try {
            result = root spawn generate_pr_for_issue(issue_id=issue_id);
            if result.reports and len(result.reports) > 0 {
                pr_result = result.reports[0] as dict;
                scroll_to_banner();
            }
            await load_queue(active_repo);
        } except Exception as e {
            pr_result = {"ok": False, "error": str(e)};
            scroll_to_banner();
        } finally {
            mark_generating(issue_id, False);
        }
    }

    def handle_open_detail(cluster_id: str) {
        nav("/cluster/" + cluster_id);
    }

    def toggle_settings {
        settings_open = not settings_open;
    }

    async def handle_weight_change(key: str, value: float) {
        next_blast = value if key == "w_blast" else w_blast;
        next_sev = value if key == "w_sev" else w_sev;
        next_diff = value if key == "w_diff" else w_diff;
        w_blast = next_blast;
        w_sev = next_sev;
        w_diff = next_diff;
        root spawn set_weights(
            full_name=active_repo, w_blast=next_blast, w_sev=next_sev, w_diff=next_diff
        );
        await load_queue(active_repo);
    }

    def dismiss_banner(_e: MouseEvent) {
        pr_result = None;
    }

    if loading {
        return
            <div
                className="min-h-screen flex items-center justify-center text-sm text-[var(--color-text-muted)]"
            >
                Loading queue...
            </div>;
    }

    if queue is None {
        return
            <div
                className="min-h-screen flex items-center justify-center text-sm text-[var(--color-orange)]"
            >
                {load_error or "Couldn't load the queue."}
            </div>;
    }

    repo_name = queue["repo"] as str;

    # Anything with a PR on it drops out of the working queue and into Drafted
    # PRs at the bottom - the maintainer is done with it.
    def _is_drafted(row: dict) -> bool {
        return (row["pr_url"] as str) != "";
    }

    all_clusters = queue["clusters"] as list[dict];
    live_clusters = [
        c
        for c in all_clusters
        if not _is_drafted(c)
    ];
    # get_queue returns clusters urgency-descending, so position IS rank - but
    # rank the LIVE ones, so #1 is always the top of the working queue.
    clusters = [{"rank": i + 1, "cluster": c} for (i, c) in enumerate(live_clusters)];
    # One "standalone issues" section: ranked singletons first, then the parked
    # ones we wouldn't guess a file for.
    all_standalone = (queue["singletons"] as list[dict]) + (
        queue["unresolved"] as list[dict]
    );
    standalone = [
        i
        for i in all_standalone
        if not _is_drafted(i)
    ];
    drafted_clusters = [
        c
        for c in all_clusters
        if _is_drafted(c)
    ];
    drafted_issues = [
        i
        for i in all_standalone
        if _is_drafted(i)
    ];
    drafted_count = len(drafted_clusters) + len(drafted_issues);

    # An empty queue is ambiguous on its own, so say which kind of empty it is
    # rather than rendering a page with nothing on it. `open_issue_count` is
    # GitHub's real count (PRs excluded) as of the last select/ingest; -1 means
    # we have never checked, which is its own honest answer.
    total_rows = len(all_clusters) + len(all_standalone);
    known_open = queue["open_issue_count"] as int;
    empty_message = "";
    if total_rows == 0 and not ingesting {
        if known_open == 0 {
            empty_message = "This repository has no open issues. Nothing to triage - which is the good outcome.";
        } elif known_open > 0 {
            empty_message = f"This repository has {str(known_open)} open issues on GitHub, but none have been triaged into the graph yet. Re-open it from Your projects to start ingestion.";
        } else {
            empty_message = "No issues have been triaged into this repository's queue yet. Re-open it from Your projects to start ingestion.";
        }
    }

    return
        <div className="min-h-screen px-6 sm:px-12 py-10 max-w-6xl mx-auto">
            <div className="flex items-start justify-between gap-6">
                <div className="min-w-0">
                    <button
                        onClick={lambda (_e: MouseEvent) -> None { nav("/repos"); }}
                        className="text-xs text-[var(--color-text-muted)] transition-colors hover:text-[var(--color-text)]"
                    >
                        ← Your projects
                    </button>
                    <h1
                        className="mt-2 text-2xl font-semibold tracking-tight text-[var(--color-text)] truncate"
                    >
                        {repo_name}
                    </h1>
                    <p className="mt-1 text-sm text-[var(--color-text-muted)]">
                        {str(
                            queue["file_count"]
                        )} files indexed · ranked by structural blast radius, not by how the issue is worded.
                    </p>
                    {ingesting
                    and <p className="mt-2 text-sm text-[var(--color-green)]">
                        Triaging the rest of the queue in the background - {str(
                            issue_total
                        )} issues placed so far, this list refreshes as they land.
                    </p>}
                </div>
                <div className="shrink-0 pt-1">
                    <SettingsPanel
                        w_blast={w_blast}
                        w_sev={w_sev}
                        w_diff={w_diff}
                        open={settings_open}
                        onToggle={toggle_settings}
                        onChange={handle_weight_change}
                    />
                </div>
            </div>
            {if pr_result is not None and pr_result["ok"] {
                <div
                    key="pr-success"
                    className="mt-6 rounded-xl border border-[var(--color-green)]/40 bg-[var(--color-green-soft)] px-4 py-3 flex items-center justify-between"
                >
                    <span className="text-sm text-[var(--color-text)]">
                        PR #
                        {str(pr_result["pr_number"])}{" "}
                        opened -{" "}
                        <a
                            href={pr_result["pr_url"]}
                            target="_blank"
                            rel="noreferrer"
                            className="underline text-[var(--color-green)]"
                        >
                            review on GitHub
                        </a>
                    </span>
                    <button
                        onClick={dismiss_banner}
                        className="text-xs text-[var(--color-text-muted)] hover:text-[var(--color-text)]"
                    >
                        dismiss
                    </button>
                </div>
            }}
            {if pr_result is not None and not pr_result["ok"] {
                <div
                    key="pr-error"
                    className="mt-6 rounded-xl border border-[var(--color-orange)]/40 bg-[var(--color-orange-soft)] px-4 py-3 flex items-center justify-between"
                >
                    <span className="text-sm text-[var(--color-orange)]">
                        Couldn't open PR: {pr_result["error"]}
                    </span>
                    <button
                        onClick={dismiss_banner}
                        className="text-xs text-[var(--color-text-muted)] hover:text-[var(--color-text)]"
                    >
                        dismiss
                    </button>
                </div>
            }}
            {empty_message
            and <div
                className="mt-10 rounded-xl border border-[var(--color-border)] bg-[var(--color-surface)] px-6 py-10 text-center"
            >
                <p className="text-sm text-[var(--color-text)]">{empty_message}</p>
                <button
                    onClick={lambda (_e: MouseEvent) -> None { nav("/repos"); }}
                    className="mt-4 text-xs text-[var(--color-text-muted)] underline underline-offset-2 transition-colors hover:text-[var(--color-orange)]"
                >
                    Pick another repository
                </button>
            </div>}
            <div className="mt-8 flex flex-col gap-3">
                {for row in clusters {
                    cluster = row["cluster"] as dict;
                    <ClusterRow
                        key={cluster["id"]}
                        cluster={cluster}
                        rank={row["rank"] as int}
                        repo={repo_name}
                        expanded={expanded_id == cluster["id"]}
                        onToggle={lambda { toggle_cluster(cluster["id"] as str); }}
                        onGeneratePr={handle_generate_pr}
                        onOpenDetail={handle_open_detail}
                        generating={generating[cluster["id"]] == True}
                    />
                }}
            </div>
            {if len(standalone) > 0 {
                <h2
                    key="singles-h"
                    className="mt-10 mb-3 text-[11px] font-semibold uppercase tracking-[0.12em] text-[var(--color-text-muted)]"
                >
                    Standalone issues
                </h2>
            }}
            <div className="flex flex-col gap-3">
                {for issue in standalone {
                    <SingletonRow
                        key={issue["id"]}
                        issue={issue}
                        repo={repo_name}
                        onGeneratePr={handle_generate_issue_pr}
                        generating={generating[issue["id"]] == True}
                    />
                }}
            </div>
            {if drafted_count > 0 {
                <div key="drafted">
                    <h2
                        className="mt-10 mb-1 text-[11px] font-semibold uppercase tracking-[0.12em] text-[var(--color-green)]"
                    >
                        Drafted PRs ({str(drafted_count)})
                    </h2>
                    <p className="mb-3 text-xs text-[var(--color-text-muted)]">
                        Waiting on you to review and merge on GitHub. Triage never merges anything itself.
                    </p>
                    <div className="flex flex-col gap-3">
                        {for cluster in drafted_clusters {
                            <ClusterRow
                                key={cluster["id"]}
                                cluster={cluster}
                                rank={0}
                                repo={repo_name}
                                expanded={expanded_id == cluster["id"]}
                                onToggle={lambda { toggle_cluster(
                                    cluster["id"] as str
                                ); }}
                                onGeneratePr={handle_generate_pr}
                                onOpenDetail={handle_open_detail}
                                drafted={True}
                            />
                        }}
                        {for issue in drafted_issues {
                            <SingletonRow
                                key={issue["id"]}
                                issue={issue}
                                repo={repo_name}
                                onGeneratePr={handle_generate_issue_pr}
                                drafted={True}
                            />
                        }}
                    </div>
                </div>
            }}
        </div>;
}
