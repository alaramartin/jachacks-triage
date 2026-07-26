"""Cluster detail + graph visualization (CLAUDE.md §8, beat 3 - the graph hero shot).

LIVE DATA: fetches walker/get_cluster_detail for the route's :id on mount and
walker/generate_pr on click.
"""

import from "@jac/runtime" { useNavigate, useParams }
sv import from ..main { get_cluster_detail, generate_pr }
import from .components.ResolutionBadge { ResolutionBadge }
import from .components.StatPill { StatPill }
import from .components.GraphView { GraphView }

def _issue_detail_to_dict(i: any) -> dict {
    return {
        "id": i.id,
        "external_id": i.external_id,
        "title": i.title,
        "body": i.body,
        "severity": i.severity,
        "resolution_method": i.resolution_method
    };
}

def:pub ClusterView -> JsxElement {
    has detail: dict | None = None,
        loading: bool = True,
        load_error: str | None = None,
        pr_result: dict | None = None;

    nav = useNavigate();
    params = useParams();
    route_id = params["id"];

    async can with [route_id] entry {
        loading = True;
        load_error = None;
        result = root spawn get_cluster_detail(cluster_id=route_id as str);
        if result.reports and len(result.reports) > 0 {
            resp = result.reports[0];
            # get_cluster_detail reports EITHER a ClusterDetailResponse OR a
            # plain {"ok": False, "error": ...} dict (CLAUDE.md §6) - bracket
            # access is safe on both (undefined, not a throw, when absent).
            if resp["ok"] == False {
                load_error = resp["error"] as str;
                detail = None;
            } else {
                detail = {
                    "id": resp.id,
                    "title": resp.title,
                    "root_cause_summary": resp.root_cause_summary,
                    "target_path": resp.target_path,
                    "blast_radius": resp.blast_radius,
                    "urgency": resp.urgency,
                    "fix_confidence": resp.fix_confidence,
                    "proposed_fix_summary": resp.proposed_fix_summary,
                    "issues": [_issue_detail_to_dict(i) for i in resp.issues],
                    "graph": resp.graph,
                    "existing_pr": resp.existing_pr
                };
            }
        } else {
            load_error = "Couldn't reach the server.";
        }
        loading = False;
    }

    def handle_back(_e: MouseEvent) {
        nav("/queue");
    }

    async def handle_generate_pr(_e: MouseEvent) {
        if detail is None {
            return;
        }
        result = root spawn generate_pr(cluster_id=detail["id"] as str);
        if result.reports and len(result.reports) > 0 {
            pr_result = result.reports[0];
        }
    }

    def dismiss_banner(_e: MouseEvent) {
        pr_result = None;
    }

    if loading {
        return <div className="min-h-screen flex items-center justify-center text-zinc-500 text-sm">
            Loading cluster...
        </div>;
    }

    if detail is None {
        return <div className="min-h-screen flex flex-col items-center justify-center gap-3 text-sm">
            <span className="text-red-400">{load_error or "Cluster not found."}</span>
            <button onClick={lambda -> None { nav("/queue"); }} className="text-zinc-500 hover:text-zinc-200">
                ← Back to queue
            </button>
        </div>;
    }

    urgency = detail["urgency"] as float;
    fix_confidence = detail["fix_confidence"] as float;
    issues = detail["issues"] as list[dict];

    return
        <div className="min-h-screen px-6 py-8 max-w-4xl mx-auto">
            <button
                onClick={handle_back}
                className="text-sm text-zinc-500 hover:text-zinc-200 mb-4"
            >
                ← Back to queue
            </button>
            <div className="flex items-center gap-2 mb-2">
                <span className="text-xs text-zinc-500 font-mono">
                    {detail["target_path"]}
                </span>
            </div>
            <h1 className="text-2xl font-bold text-zinc-100 mb-4">{detail["title"]}</h1>
            <div className="flex gap-2 mb-6">
                <StatPill
                    value={str(detail["blast_radius"]) + " of 18 files"}
                    label="blast radius"
                    emphasis={True}
                />
                <StatPill value={f"{urgency:.2f}"} label="urgency"/>
                <StatPill
                    value={f"{(fix_confidence * 100.0):.0f}%"}
                    label="fix confidence"
                />
            </div>
            <div
                className="rounded-xl border border-[var(--color-border)] bg-[var(--color-surface)] p-4 mb-6 flex justify-center"
            >
                <GraphView graph={detail["graph"]}/>
            </div>
            <div
                className="rounded-xl border border-[var(--color-border)] bg-[var(--color-surface)] p-5 mb-4"
            >
                <h2 className="text-sm font-semibold text-zinc-300 mb-2">Root cause</h2>
                <p className="text-sm text-zinc-400 leading-relaxed">
                    {detail["root_cause_summary"]}
                </p>
            </div>
            <div
                className="rounded-xl border border-[var(--color-border)] bg-[var(--color-surface)] p-5 mb-4"
            >
                <h2 className="text-sm font-semibold text-zinc-300 mb-2">
                    Proposed fix
                </h2>
                <p className="text-sm text-zinc-400 leading-relaxed">
                    {detail["proposed_fix_summary"]}
                </p>
            </div>
            <div
                className="rounded-xl border border-[var(--color-border)] bg-[var(--color-surface)] overflow-hidden mb-6"
            >
                <h2 className="text-sm font-semibold text-zinc-300 px-5 pt-4 pb-2">
                    Member issues ({str(len(issues))})
                </h2>
                <div className="divide-y divide-[var(--color-border)]">
                    {for issue in issues {
                        <div
                            key={issue["id"]}
                            className="px-5 py-3 flex items-center justify-between gap-4"
                        >
                            <div className="min-w-0">
                                <div className="flex items-center gap-2">
                                    <span className="text-xs text-zinc-500 font-mono">
                                        {issue["external_id"]}
                                    </span>
                                    <ResolutionBadge
                                        method={issue["resolution_method"]}
                                    />
                                </div>
                                <div className="text-sm text-zinc-300 truncate">
                                    {issue["title"]}
                                </div>
                            </div>
                            <span className="text-xs text-zinc-500 shrink-0">
                                sev {str(issue["severity"])}
                            </span>
                        </div>
                    }}
                </div>
            </div>
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
            <button
                onClick={handle_generate_pr}
                className="rounded-lg bg-[var(--color-accent)] text-white text-sm font-semibold px-5 py-3 hover:opacity-90"
            >
                Generate PR
            </button>
        </div>;
}
