"""One expandable cluster row on the ranked queue - the money-shot element."""

import from ..types { ClusterSummary }
import from .ResolutionBadge { ResolutionBadge }
import from .StatPill { StatPill }

def:pub ClusterRow(cluster: ClusterSummary, expanded: bool, onToggle: Callable[[], None], onGeneratePr: Callable[[str], None], onOpenDetail: Callable[[str], None]) -> JsxElement {
    def handle_toggle(_e: MouseEvent) { onToggle(); }
    def handle_generate(e: MouseEvent) { e.stopPropagation(); onGeneratePr(cluster.id); }
    def handle_open_detail(e: MouseEvent) { e.stopPropagation(); onOpenDetail(cluster.id); }

    return <div className="rounded-xl border border-[var(--color-border)] bg-[var(--color-surface)] overflow-hidden">
        <div
            onClick={handle_toggle}
            className="w-full flex items-center gap-6 px-5 py-4 text-left hover:bg-[var(--color-surface-raised)] transition-colors cursor-pointer"
        >
            <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2 mb-1">
                    <span className="rounded bg-[var(--color-accent-soft)] text-[var(--color-accent)] text-[11px] font-semibold px-1.5 py-0.5">
                        CLUSTER · {str(cluster.issue_count)} issues
                    </span>
                    <span className="text-xs text-zinc-500 font-mono">{cluster.target_path}</span>
                </div>
                <h3 className="text-base font-semibold text-zinc-100 truncate">{cluster.title}</h3>
            </div>

            <StatPill value={str(cluster.blast_radius) + (" file" if cluster.blast_radius == 1 else " files")} label="blast radius" emphasis={True} />
            <StatPill value={f"{cluster.urgency:.2f}"} label="urgency" />

            <button onClick={handle_generate} className="shrink-0 rounded-lg bg-[var(--color-accent)] text-white text-sm font-semibold px-4 py-2 hover:opacity-90">
                Generate PR
            </button>
        </div>

        {if expanded {
            <div className="border-t border-[var(--color-border)] divide-y divide-[var(--color-border)]">
                {for issue in cluster.issues {
                    <div key={issue.id} className="flex items-center justify-between gap-4 px-5 py-3 pl-10">
                        <div className="flex items-center gap-2 min-w-0">
                            <span className="text-xs text-zinc-500 font-mono shrink-0">{issue.external_id}</span>
                            <span className="text-sm text-zinc-300 truncate">{issue.title}</span>
                        </div>
                        <div className="flex items-center gap-3 shrink-0">
                            <span className="text-xs text-zinc-500">sev {str(issue.severity)}</span>
                            <ResolutionBadge method={issue.resolution_method} />
                        </div>
                    </div>
                }}
                <button key="view-detail" onClick={handle_open_detail} className="w-full text-left px-5 py-3 pl-10 text-sm font-medium text-[var(--color-accent)] hover:bg-[var(--color-surface-raised)]">
                    View graph &amp; root cause →
                </button>
            </div>
        }}
    </div>;
}
