"""One singleton issue row - same language as a cluster row, deliberately
quieter and more compact (no orange, no action buttons) so the eye lands on the
clusters first."""

import from .ResolutionBadge { ResolutionBadge }
import from .IssueChip { IssueChip }

def:pub SingletonRow(issue: dict, repo: str = "") -> JsxElement {
    blast_radius = issue["blast_radius"];
    urgency = issue["urgency"] as float;

    return
        <div
            className="rounded-xl border border-[var(--color-border)] bg-[var(--color-surface)] flex flex-wrap items-center gap-x-5 gap-y-2 px-5 py-3.5"
        >
            <IssueChip
                external_id={issue["external_id"] as str}
                title={issue["title"] as str}
                repo={repo}
            />
            <div className="flex-1 min-w-0">
                <div className="text-[15px] text-[var(--color-text)] truncate">
                    {issue["title"]}
                </div>
                <div className="mt-1 flex items-center gap-2">
                    <span className="font-mono text-xs text-[var(--color-text-muted)] truncate">
                        {issue["target_path"]}
                    </span>
                    <ResolutionBadge method={issue["resolution_method"]}/>
                </div>
            </div>
            <div
                className="flex items-center gap-5 shrink-0 text-xs text-[var(--color-text-muted)]"
            >
                <span>
                    <span className="text-base font-semibold text-[var(--color-text)]">
                        {str(blast_radius)}
                    </span>
                    {" file downstream" if blast_radius == 1 else " files downstream"}
                </span>
                <span>
                    <span className="text-base font-semibold text-[var(--color-text)]">
                        {f"{urgency:.2f}"}
                    </span>
                    {" urgency"}
                </span>
                <span className="w-12 text-right">sev {str(issue["severity"])}</span>
            </div>
        </div>;
}
