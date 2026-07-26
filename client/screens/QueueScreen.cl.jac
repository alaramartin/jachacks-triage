"""The ranked queue - the most important screen (CLAUDE.md §8, beat 2).

LIVE DATA: fetches walker/get_queue on mount and walker/generate_pr on click.
No client-side sort - the order here IS the order get_queue returns,
clusters/singletons already ranked by urgency descending.
"""

import from "@jac/runtime" { useNavigate }
sv import from ...main { get_queue, generate_pr }
import from ..components.ClusterRow { ClusterRow }
import from ..components.SingletonRow { SingletonRow }
import from ..components.UnresolvedList { UnresolvedList }

# Single demo repo, same convention used throughout (reindex_repo's full_name
# in CLAUDE.md §6 and every seed/seed.jac ingestion call) - there is no live
# multi-repo GitHub listing (OAuth is an accepted, documented scope cut).
glob DEMO_REPO: str = "triage-demo/shipyard";

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
        pr_result: dict | None = None;

    nav = useNavigate();

    async can with entry {
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

    def dismiss_banner(_e: MouseEvent) {
        pr_result = None;
    }

    if loading {
        return <div className="min-h-screen flex items-center justify-center text-zinc-500 text-sm">
            Loading queue...
        </div>;
    }

    if queue is None {
        return <div className="min-h-screen flex items-center justify-center text-red-400 text-sm">
            {load_error or "Couldn't load the queue."}
        </div>;
    }

    clusters = queue["clusters"] as list[dict];
    singletons = queue["singletons"] as list[dict];
    unresolved = queue["unresolved"] as list[dict];

    return
        <div className="min-h-screen px-6 py-8 max-w-4xl mx-auto">
            <div className="flex items-baseline justify-between mb-1">
                <h1 className="text-2xl font-bold text-zinc-100">
                    {queue["repo"]}
                </h1>
                <span className="text-xs text-zinc-500">
                    {str(queue["file_count"])} files
                </span>
            </div>
            <p className="text-sm text-zinc-500 mb-6">
                Ranked by structural blast radius, not by how the issue is worded.
            </p>
            {if pr_result is not None and pr_result["ok"] {
                <div
                    key="pr-success"
                    className="mb-4 rounded-lg border border-emerald-500/40 bg-emerald-500/10 px-4 py-3 flex items-center justify-between"
                >
                    <span className="text-sm text-zinc-200">
                        PR #
                        {str(pr_result["pr_number"])}{" "}
                        opened -{" "}
                        <a
                            href={pr_result["pr_url"]}
                            target="_blank"
                            className="underline text-emerald-300"
                        >
                            review on GitHub
                        </a>
                    </span>
                    <button
                        onClick={dismiss_banner}
                        className="text-xs text-zinc-400 hover:text-zinc-100"
                    >
                        dismiss
                    </button>
                </div>
            }}
            {if pr_result is not None and not pr_result["ok"] {
                <div
                    key="pr-error"
                    className="mb-4 rounded-lg border border-red-500/40 bg-red-500/10 px-4 py-3 flex items-center justify-between"
                >
                    <span className="text-sm text-red-200">
                        Couldn't open PR: {pr_result["error"]}
                    </span>
                    <button
                        onClick={dismiss_banner}
                        className="text-xs text-zinc-400 hover:text-zinc-100"
                    >
                        dismiss
                    </button>
                </div>
            }}
            <div className="flex flex-col gap-3">
                {for cluster in clusters {
                    <ClusterRow
                        key={cluster["id"]}
                        cluster={cluster}
                        expanded={expanded_id == cluster["id"]}
                        onToggle={lambda { toggle_cluster(cluster["id"] as str); }}
                        onGeneratePr={handle_generate_pr}
                        onOpenDetail={handle_open_detail}
                    />
                }}
                {for issue in singletons {
                    <SingletonRow key={issue["id"]} issue={issue}/>
                }}
            </div>
            <div className="mt-6">
                <UnresolvedList issues={unresolved}/>
            </div>
        </div>;
}
