"""The ranked queue - the most important screen (CLAUDE.md 8, beat 2).

LIVE DATA: walker/get_queue on mount, walker/set_weights when a ranking slider
moves (then a refetch), walker/generate_pr on click. No client-side sort - the
order here IS the order get_queue returns, clusters/singletons already ranked by
urgency descending.
"""

import from "@jac/runtime" { useNavigate }
sv import from ...main { get_queue, generate_pr, set_weights }
import from ..components.ClusterRow { ClusterRow }
import from ..components.SingletonRow { SingletonRow }
import from ..components.UnresolvedList { UnresolvedList }
import from ..components.SettingsPanel { SettingsPanel }

# Single demo repo, same convention used throughout (reindex_repo's full_name
# in CLAUDE.md 6 and every seed/seed.jac ingestion call) - there is no live
# multi-repo GitHub listing (OAuth is a documented work in progress).
glob DEMO_REPO: str = "alaramartin/triage-demo";

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
        "issues": [_issue_summary_to_dict(i) for i in c.issues]
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
        "resolution_method": s.resolution_method
    };
}

def _unresolved_to_dict(u: any) -> dict {
    return {"id": u.id, "external_id": u.external_id, "title": u.title};
}

def:pub QueueScreen -> JsxElement {
    has queue: dict | None = None,
        loading: bool = True,
        load_error: str | None = None,
        expanded_id: str | None = None,
        pr_result: dict | None = None,
        settings_open: bool = False,
        w_blast: float = 6.0,
        w_sev: float = 3.0,
        w_diff: float = 1.0;

    nav = useNavigate();

    async def load_queue {
        result = root spawn get_queue(full_name=DEMO_REPO);
        if result.reports and len(result.reports) > 0 {
            resp = result.reports[0];
            queue = {
                "repo": resp.repo,
                "file_count": resp.file_count,
                "clusters": [_cluster_to_dict(c) for c in resp.clusters],
                "singletons": [_singleton_to_dict(s) for s in resp.singletons],
                "unresolved": [_unresolved_to_dict(u) for u in resp.unresolved]
            };
        } else {
            load_error = "Couldn't reach the server - is reindex_repo done?";
        }
        loading = False;
    }

    async can with entry {
        await load_queue();
    }

    def toggle_cluster(cluster_id: str) {
        expanded_id = None if expanded_id == cluster_id else cluster_id;
    }

    async def handle_generate_pr(cluster_id: str) {
        result = root spawn generate_pr(cluster_id=cluster_id);
        if result.reports and len(result.reports) > 0 {
            pr_result = result.reports[0] as dict;
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
            full_name=DEMO_REPO, w_blast=next_blast, w_sev=next_sev, w_diff=next_diff
        );
        await load_queue();
    }

    def dismiss_banner(_e: MouseEvent) {
        pr_result = None;
    }

    if loading {
        return <div className="min-h-screen flex items-center justify-center text-sm text-[var(--color-text-muted)]">
            Loading queue...
        </div>;
    }

    if queue is None {
        return <div className="min-h-screen flex items-center justify-center text-sm text-[var(--color-orange)]">
            {load_error or "Couldn't load the queue."}
        </div>;
    }

    repo_name = queue["repo"] as str;
    # get_queue already returns clusters urgency-descending, so position IS rank.
    clusters = [
        {"rank": i + 1, "cluster": c}
        for (i, c) in enumerate(queue["clusters"] as list[dict])
    ];
    singletons = queue["singletons"] as list[dict];
    unresolved = queue["unresolved"] as list[dict];

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
                        {str(queue["file_count"])} files indexed · ranked by structural blast radius, not by how the issue is worded.
                    </p>
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
                    />
                }}
            </div>
            {if len(singletons) > 0 {
                <h2
                    key="singles-h"
                    className="mt-10 mb-3 text-[11px] font-semibold uppercase tracking-[0.12em] text-[var(--color-text-muted)]"
                >
                    Standalone issues
                </h2>
            }}
            <div className="flex flex-col gap-3">
                {for issue in singletons {
                    <SingletonRow key={issue["id"]} issue={issue} repo={repo_name}/>
                }}
            </div>
            {if len(unresolved) > 0 {
                <div key="unresolved" className="mt-10">
                    <UnresolvedList issues={unresolved}/>
                </div>
            }}
        </div>;
}
