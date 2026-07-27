"""One cluster row on the ranked queue - the money-shot element.

Sketch layout: stacked issue chips on the left, the shared root cause in the
middle, and (behind a vertical divider) the two actions on the right - green
GENERATE PR over an orange View detail. Clicking the middle expands the member
issues with severity + how each was resolved.
"""

import from .ResolutionBadge { ResolutionBadge }
import from .IssueChip { IssueChip }

def:pub ClusterRow(
    cluster: dict,
    rank: int,
    repo: str,
    expanded: bool,
    onToggle: Callable[[], None],
    onGeneratePr: Callable[[str], None],
    onOpenDetail: Callable[[str], None]
) -> JsxElement {
    blast_radius = cluster["blast_radius"];
    urgency = cluster["urgency"] as float;
    issues = cluster["issues"] as list[dict];
    top = rank == 1;

    # Keep the chip stack from running away on a big cluster - the sketch shows
    # three or four, and the count is already on the badge.
    visible = issues[:4];
    overflow = len(issues) - len(visible);

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

    border_cls = "border-[var(--color-orange)]/45" if top else "border-[var(--color-border)]";

    return
        <div
            className={"rounded-2xl border bg-[var(--color-surface)] overflow-hidden transition-colors " + border_cls}
        >
            <div
                onClick={handle_toggle}
                onKeyDown={handle_toggle_key}
                role="button"
                tabIndex={0}
                aria-expanded={expanded}
                className="flex flex-col lg:flex-row lg:items-stretch cursor-pointer hover:bg-[var(--color-surface-raised)] transition-colors focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-[var(--color-orange)]"
            >
                <div className="flex flex-wrap lg:flex-col gap-2 p-5 shrink-0 lg:w-56">
                    {for issue in visible {
                        <IssueChip
                            key={issue["id"]}
                            external_id={issue["external_id"] as str}
                            title={issue["title"] as str}
                            repo={repo}
                        />
                    }}
                    {if overflow > 0 {
                        <span
                            key="overflow"
                            className="px-3 py-1 font-mono text-[11px] text-[#5b616e]"
                        >
                            +{str(overflow)} more
                        </span>
                    }}
                </div>
                <div className="flex-1 min-w-0 px-5 py-5 lg:pl-2">
                    <div className="flex items-center gap-2 flex-wrap">
                        <span
                            className="rounded-full bg-[var(--color-orange-soft)] px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.1em] text-[var(--color-orange)]"
                        >
                            {"#" + str(rank)} · cluster of {str(cluster["issue_count"])}
                        </span>
                        <span className="font-mono text-xs text-[var(--color-text-muted)] truncate">
                            {cluster["target_path"]}
                        </span>
                    </div>
                    <h3 className="mt-2 text-[17px] font-semibold leading-snug text-[var(--color-text)]">
                        {cluster["title"]}
                    </h3>
                    <div className="mt-3 flex items-center gap-5 text-xs text-[var(--color-text-muted)]">
                        <span>
                            <span className="text-lg font-bold text-[var(--color-orange)]">
                                {str(blast_radius)}
                            </span>
                            {" file downstream" if blast_radius == 1 else " files downstream"}
                        </span>
                        <span>
                            <span className="text-lg font-semibold text-[var(--color-text)]">
                                {f"{urgency:.2f}"}
                            </span>
                            {" urgency"}
                        </span>
                        <span className="hidden sm:inline">
                            max sev {str(cluster["max_severity"])}
                        </span>
                    </div>
                </div>
                <div
                    className="flex flex-row lg:flex-col justify-center gap-2.5 p-5 shrink-0 border-t lg:border-t-0 lg:border-l border-[var(--color-border)]"
                >
                    <button
                        onClick={handle_generate}
                        className="rounded-lg bg-[var(--color-green)] px-4 py-2.5 text-[13px] font-semibold uppercase tracking-wide text-[#07130d] transition-colors hover:bg-[#54e79c]"
                    >
                        Generate PR
                    </button>
                    <button
                        onClick={handle_open_detail}
                        className="rounded-lg border border-[var(--color-orange)]/60 px-4 py-2.5 text-[13px] font-medium text-[var(--color-orange)] transition-colors hover:bg-[var(--color-orange-soft)]"
                    >
                        View detail
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
                            className="flex items-center justify-between gap-4 px-5 py-3"
                        >
                            <div className="flex items-center gap-3 min-w-0">
                                <span className="font-mono text-xs text-[#5b616e] shrink-0">
                                    {issue["external_id"]}
                                </span>
                                <span className="text-sm text-[var(--color-text-muted)] truncate">
                                    {issue["title"]}
                                </span>
                            </div>
                            <div className="flex items-center gap-3 shrink-0">
                                <span className="text-xs text-[#5b616e]">
                                    sev {str(issue["severity"])}
                                </span>
                                <ResolutionBadge method={issue["resolution_method"]}/>
                            </div>
                        </div>
                        for issue in issues
                    ]}
                </div>
            }}
        </div>;
}
