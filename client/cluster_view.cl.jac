"""Cluster detail + graph visualization (CLAUDE.md §8, beat 3 - the graph hero shot).

MOCK DATA: renders `mock_cluster_detail` (cluster A / core/validation.py) from
mock_data.cl.jac regardless of the route param, since Phase A only hand-built
one cluster's detail mock. Person 1's real get_cluster_detail (Phase C, ~4:15)
replaces this with a live per-id fetch - see PLAN.md Person 3 Phase C step 1.
"""

import from "@jac/runtime" { useNavigate, useParams }
import from .mock_data { mock_cluster_detail }
import from .components.ResolutionBadge { ResolutionBadge }
import from .components.StatPill { StatPill }
import from .components.GraphView { GraphView }

def:pub ClusterView() -> JsxElement {
    has pr_result: dict | None = None;

    nav = useNavigate();
    params = useParams();
    route_id = params["id"];
    detail = mock_cluster_detail;
    is_mock_fallback = route_id != detail["id"];
    urgency = detail["urgency"] as float;
    fix_confidence = detail["fix_confidence"] as float;
    issues = detail["issues"] as list[dict];

    def handle_back(_e: MouseEvent) {
        nav("/queue");
    }

    def handle_generate_pr(_e: MouseEvent) {
        # MOCK - same {ok, pr_number, pr_url} / {ok: false, error} shape as
        # walker/generate_pr (CLAUDE.md §6); swap for `await generate_pr(detail["id"])`
        # in Phase C, same branch below.
        pr_result = {"ok": True, "pr_number": 7, "pr_url": "https://github.com/triage-demo/shipyard/pull/7"};
    }

    def dismiss_banner(_e: MouseEvent) {
        pr_result = None;
    }

    return <div className="min-h-screen px-6 py-8 max-w-4xl mx-auto">
        <button onClick={handle_back} className="text-sm text-zinc-500 hover:text-zinc-200 mb-4">← Back to queue</button>

        {if is_mock_fallback {
            <p className="text-xs text-amber-500/80 mb-3">Showing mock detail for cluster A - live per-cluster detail arrives in Phase C.</p>
        }}

        <div className="flex items-center gap-2 mb-2">
            <span className="text-xs text-zinc-500 font-mono">{detail["target_path"]}</span>
        </div>
        <h1 className="text-2xl font-bold text-zinc-100 mb-4">{detail["title"]}</h1>

        <div className="flex gap-2 mb-6">
            <StatPill value={str(detail["blast_radius"]) + " of 18 files"} label="blast radius" emphasis={True} />
            <StatPill value={f"{urgency:.2f}"} label="urgency" />
            <StatPill value={f"{(fix_confidence * 100.0):.0f}%"} label="fix confidence" />
        </div>

        <div className="rounded-xl border border-[var(--color-border)] bg-[var(--color-surface)] p-4 mb-6 flex justify-center">
            <GraphView graph={detail["graph"]} />
        </div>

        <div className="rounded-xl border border-[var(--color-border)] bg-[var(--color-surface)] p-5 mb-4">
            <h2 className="text-sm font-semibold text-zinc-300 mb-2">Root cause</h2>
            <p className="text-sm text-zinc-400 leading-relaxed">{detail["root_cause_summary"]}</p>
        </div>

        <div className="rounded-xl border border-[var(--color-border)] bg-[var(--color-surface)] p-5 mb-4">
            <h2 className="text-sm font-semibold text-zinc-300 mb-2">Proposed fix</h2>
            <p className="text-sm text-zinc-400 leading-relaxed">{detail["proposed_fix_summary"]}</p>
        </div>

        <div className="rounded-xl border border-[var(--color-border)] bg-[var(--color-surface)] overflow-hidden mb-6">
            <h2 className="text-sm font-semibold text-zinc-300 px-5 pt-4 pb-2">Member issues ({str(len(issues))})</h2>
            <div className="divide-y divide-[var(--color-border)]">
                {for issue in issues {
                    <div key={issue["id"]} className="px-5 py-3 flex items-center justify-between gap-4">
                        <div className="min-w-0">
                            <div className="flex items-center gap-2">
                                <span className="text-xs text-zinc-500 font-mono">{issue["external_id"]}</span>
                                <ResolutionBadge method={issue["resolution_method"]} />
                            </div>
                            <div className="text-sm text-zinc-300 truncate">{issue["title"]}</div>
                        </div>
                        <span className="text-xs text-zinc-500 shrink-0">sev {str(issue["severity"])}</span>
                    </div>
                }}
            </div>
        </div>

        {if pr_result is not None and pr_result["ok"] {
            <div key="pr-success" className="mb-4 rounded-lg border border-emerald-500/40 bg-emerald-500/10 px-4 py-3 flex items-center justify-between">
                <span className="text-sm text-zinc-200">
                    PR #{str(pr_result["pr_number"])} opened - <a href={pr_result["pr_url"]} target="_blank" className="underline text-emerald-300">review on GitHub</a>
                </span>
                <button onClick={dismiss_banner} className="text-xs text-zinc-400 hover:text-zinc-100">dismiss</button>
            </div>
        }}
        {if pr_result is not None and not pr_result["ok"] {
            <div key="pr-error" className="mb-4 rounded-lg border border-red-500/40 bg-red-500/10 px-4 py-3 flex items-center justify-between">
                <span className="text-sm text-red-200">Couldn't open PR: {pr_result["error"]}</span>
                <button onClick={dismiss_banner} className="text-xs text-zinc-400 hover:text-zinc-100">dismiss</button>
            </div>
        }}

        <button onClick={handle_generate_pr} className="rounded-lg bg-[var(--color-accent)] text-white text-sm font-semibold px-5 py-3 hover:opacity-90">
            Generate PR
        </button>
    </div>;
}
