"""Cluster detail + graph visualization (CLAUDE.md 8, beat 3 - the graph hero shot).

Sketch layout: the cluster's description up top, then one large bordered panel
holding the graph as the hero of the page. Everything else (root cause, proposed
fix, member issues) sits underneath it.

LIVE DATA: fetches walker/get_cluster_detail for the route's :id on mount and
walker/generate_pr on click.
"""

import from "@jac/runtime" { useNavigate, useParams }
sv import from ..main { get_cluster_detail, generate_pr }
import from .components.ResolutionBadge { ResolutionBadge }
import from .components.StatPill { StatPill }
import from .components.GraphView { GraphView }
import from .components.Spinner { Spinner }

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
        pr_result: dict | None = None,
        pr_pending: bool = False;

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
            # plain {"ok": False, "error": ...} dict (CLAUDE.md 6) - bracket
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
        pr_pending = True;
        # `finally` so a walker error can never strand the button on
        # "Generating" - same fix as QueueScreen's handlers.
        try {
            result = root spawn generate_pr(cluster_id=detail["id"] as str);
            if result.reports and len(result.reports) > 0 {
                pr_result = result.reports[0] as dict;
            }
        } except Exception as e {
            pr_result = {"ok": False, "error": str(e)};
        } finally {
            pr_pending = False;
            # Same reason as QueueScreen: the result banner is at the top of
            # the page and the button that triggered it may not be.
            window.scrollTo({"top": 0, "behavior": "smooth"});
        }
    }

    def dismiss_banner(_e: MouseEvent) {
        pr_result = None;
    }

    if loading {
        return <div className="min-h-screen flex items-center justify-center text-sm text-[var(--color-text-muted)]">
            Loading cluster...
        </div>;
    }

    if detail is None {
        return <div className="min-h-screen flex flex-col items-center justify-center gap-3 text-sm">
            <span className="text-[var(--color-orange)]">
                {load_error or "Cluster not found."}
            </span>
            <button
                onClick={lambda -> None { nav("/queue"); }}
                className="text-[var(--color-text-muted)] hover:text-[var(--color-text)]"
            >
                ← Back to queue
            </button>
        </div>;
    }

    urgency = detail["urgency"] as float;
    fix_confidence = detail["fix_confidence"] as float;
    issues = detail["issues"] as list[dict];
    # Real data from get_cluster_detail - null until a human has clicked
    # Generate PR for this cluster at least once.
    existing_pr = detail["existing_pr"] as dict | None;

    return
        <div className="min-h-screen px-6 sm:px-12 py-10 max-w-5xl mx-auto">
            <button
                onClick={handle_back}
                className="text-xs text-[var(--color-text-muted)] transition-colors hover:text-[var(--color-text)]"
            >
                ← Back to queue
            </button>
            <div className="mt-3 flex flex-wrap items-start justify-between gap-6">
                <div className="min-w-0 max-w-2xl">
                    <span className="font-mono text-xs text-[var(--color-orange)]">
                        {detail["target_path"]}
                    </span>
                    <h1
                        className="mt-1.5 text-2xl font-semibold leading-snug tracking-tight text-[var(--color-text)]"
                    >
                        {detail["title"]}
                    </h1>
                    <p className="mt-2 text-sm leading-relaxed text-[var(--color-text-muted)]">
                        {str(len(issues))} issues, one root cause.
                    </p>
                </div>
                <div className="flex shrink-0 flex-col items-end gap-2">
                    <button
                        onClick={handle_generate_pr}
                        disabled={pr_pending}
                        className="flex items-center gap-2 rounded-lg bg-[var(--color-green)] px-5 py-2.5 text-[13px] font-semibold uppercase tracking-wide text-[#07130d] transition-colors hover:bg-[#54e79c] disabled:cursor-wait disabled:hover:bg-[var(--color-green)]"
                    >
                        {if pr_pending {
                            <Spinner key="sp"/>
                        }}
                        {"Generating" if pr_pending else "Generate PR"}
                    </button>
                    {if existing_pr is not None {
                        <a
                            key="existing-pr"
                            href={existing_pr["url"] as str}
                            target="_blank"
                            rel="noreferrer"
                            className="text-xs text-[var(--color-text-muted)] underline transition-colors hover:text-[var(--color-green)]"
                        >
                            PR #{str(existing_pr["number"])} already open
                        </a>
                    }}
                </div>
            </div>
            {if pr_result is not None and pr_result["ok"] {
                <div
                    key="pr-success"
                    className="mt-5 rounded-xl border border-[var(--color-green)]/40 bg-[var(--color-green-soft)] px-4 py-3 flex items-center justify-between"
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
                    className="mt-5 rounded-xl border border-[var(--color-orange)]/40 bg-[var(--color-orange-soft)] px-4 py-3 flex items-center justify-between"
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
            <div
                className="mt-8 rounded-2xl border border-[var(--color-border)] bg-[var(--color-surface)] overflow-hidden"
            >
                <div
                    className="flex flex-wrap items-center justify-between gap-6 border-b border-[var(--color-border)] px-6 py-4"
                >
                    <div className="flex items-center gap-8">
                        <StatPill
                            value={str(detail["blast_radius"]) + (
                                " file" if detail["blast_radius"] == 1 else " files"
                            )}
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
                        className="flex items-center gap-4 text-[11px] text-[var(--color-text-muted)]"
                    >
                        <span className="flex items-center gap-1.5">
                            <span
                                className="inline-block h-2 w-2 rounded-full bg-[var(--color-orange)]"
                            />
                            target
                        </span>
                        <span className="flex items-center gap-1.5">
                            <span
                                className="inline-block h-2 w-2 rounded-full bg-[var(--color-green)]"
                            />
                            depends on it
                        </span>
                        <span className="flex items-center gap-1.5">
                            <span
                                className="inline-block h-2 w-2 rounded-full bg-[var(--color-border-strong)]"
                            />
                            unaffected
                        </span>
                    </div>
                </div>
                <div className="px-4 py-4">
                    <GraphView graph={detail["graph"]}/>
                </div>
            </div>
            <div className="mt-6 grid gap-4 md:grid-cols-2">
                <div
                    className="rounded-2xl border border-[var(--color-border)] bg-[var(--color-surface)] p-5"
                >
                    <h2
                        className="text-[11px] font-semibold uppercase tracking-[0.12em] text-[var(--color-text-muted)]"
                    >
                        Root cause
                    </h2>
                    <p className="mt-2 text-sm leading-relaxed text-[var(--color-text)]">
                        {detail["root_cause_summary"]}
                    </p>
                </div>
                <div
                    className="rounded-2xl border border-[var(--color-border)] bg-[var(--color-surface)] p-5"
                >
                    <h2
                        className="text-[11px] font-semibold uppercase tracking-[0.12em] text-[var(--color-green)]"
                    >
                        Proposed fix
                    </h2>
                    <p className="mt-2 text-sm leading-relaxed text-[var(--color-text)]">
                        {detail["proposed_fix_summary"]}
                    </p>
                </div>
            </div>
            <div
                className="mt-4 rounded-2xl border border-[var(--color-border)] bg-[var(--color-surface)] overflow-hidden"
            >
                <h2
                    className="px-5 pt-4 pb-3 text-[11px] font-semibold uppercase tracking-[0.12em] text-[var(--color-text-muted)]"
                >
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
                                    <span className="font-mono text-xs text-[#5b616e]">
                                        {issue["external_id"]}
                                    </span>
                                    <ResolutionBadge
                                        method={issue["resolution_method"]}
                                    />
                                </div>
                                <div className="mt-0.5 text-sm text-[var(--color-text)] truncate">
                                    {issue["title"]}
                                </div>
                            </div>
                            <span className="shrink-0 text-xs text-[var(--color-text-muted)]">
                                sev {str(issue["severity"])}
                            </span>
                        </div>
                    }}
                </div>
            </div>
        </div>;
}
