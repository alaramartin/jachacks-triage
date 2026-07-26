"""One expandable cluster row on the ranked queue - the money-shot element."""

import from .ResolutionBadge { ResolutionBadge }
import from .StatPill { StatPill }

def:pub ClusterRow(
    cluster: dict,
    expanded: bool,
    onToggle: Callable[[], None],
    onGeneratePr: Callable[[str], None],
    onOpenDetail: Callable[[str], None]
) -> JsxElement {
    blast_radius = cluster["blast_radius"];
    urgency = cluster["urgency"] as float;
    issues = cluster["issues"] as list[dict];

    def handle_toggle(_e: MouseEvent) {
        onToggle();
    }
    def handle_toggle_key(e: KeyboardEvent) {
        if e.key == "Enter" or e.key == " " {
            e.preventDefault();
            onToggle();
        }
    }
    def handle_generate(e: MouseEvent) {
        e.stopPropagation();
        onGeneratePr(cluster["id"] as str);
    }
    def handle_open_detail(e: MouseEvent) {
        e.stopPropagation();
        onOpenDetail(cluster["id"] as str);
    }

    return
        <div
            className="rounded-xl border border-[var(--color-border)] bg-[var(--color-surface)] overflow-hidden"
        >
            <div
                onClick={handle_toggle}
                onKeyDown={handle_toggle_key}
                role="button"
                tabIndex={0}
                aria-expanded={expanded}
                className="w-full flex flex-wrap items-center gap-x-6 gap-y-3 px-5 py-4 text-left hover:bg-[var(--color-surface-raised)] transition-colors cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-accent)]"
            >
                <div className="flex-1 min-w-0 basis-full sm:basis-0">
                    <div className="flex items-center gap-2 mb-1">
                        <span
                            className="rounded bg-[var(--color-accent-soft)] text-[var(--color-accent)] text-[11px] font-semibold px-1.5 py-0.5"
                        >
                            CLUSTER · {str(cluster["issue_count"])} issues
                        </span>
                        <span className="text-xs text-zinc-500 font-mono truncate">
                            {cluster["target_path"]}
                        </span>
                    </div>
                    <h3 className="text-base font-semibold text-zinc-100 truncate">
                        {cluster["title"]}
                    </h3>
                </div>
                <div className="flex items-center gap-6 shrink-0">
                    <StatPill
                        value={str(blast_radius) + (
                            " file" if blast_radius == 1 else " files"
                        )}
                        label="blast radius"
                        emphasis={True}
                    />
                    <StatPill value={f"{urgency:.2f}"} label="urgency"/>
                    <button
                        onClick={handle_generate}
                        className="shrink-0 rounded-lg bg-[var(--color-accent)] text-white text-sm font-semibold px-4 py-2 hover:opacity-90"
                    >
                        Generate PR
                    </button>
                </div>
            </div>
            {if expanded {
                <div
                    className="border-t border-[var(--color-border)] divide-y divide-[var(--color-border)]"
                >
                    {[
                        <div
                            key={issue["id"]}
                            className="flex items-center justify-between gap-4 px-5 py-3 pl-10"
                        >
                            <div className="flex items-center gap-2 min-w-0">
                                <span
                                    className="text-xs text-zinc-500 font-mono shrink-0"
                                >
                                    {issue["external_id"]}
                                </span>
                                <span className="text-sm text-zinc-300 truncate">
                                    {issue["title"]}
                                </span>
                            </div>
                            <div className="flex items-center gap-3 shrink-0">
                                <span className="text-xs text-zinc-500">
                                    sev {str(issue["severity"])}
                                </span>
                                <ResolutionBadge method={issue["resolution_method"]}/>
                            </div>
                        </div>
                        for issue in issues
                    ]}
                    <button
                        key="view-detail"
                        onClick={handle_open_detail}
                        className="w-full text-left px-5 py-3 pl-10 text-sm font-medium text-[var(--color-accent)] hover:bg-[var(--color-surface-raised)]"
                    >
                        View graph &amp; root cause →
                    </button>
                </div>
            }}
        </div>;
}
