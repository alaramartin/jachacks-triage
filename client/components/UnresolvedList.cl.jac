"""The 'couldn't confidently place' bucket - a credibility beat, never hidden."""

def:pub UnresolvedList(issues: list[dict]) -> JsxElement {
    return
        <div
            className="rounded-2xl border border-dashed border-[var(--color-border-strong)] px-5 py-4"
        >
            <h3
                className="text-[11px] font-semibold uppercase tracking-[0.12em] text-[var(--color-text-muted)]"
            >
                Couldn't confidently place ({str(len(issues))})
            </h3>
            <p className="mt-1.5 text-xs text-[#5b616e]">
                Confidence below threshold - we don't guess. These are parked, not dropped.
            </p>
            <div className="mt-3 flex flex-col gap-1.5">
                {for issue in issues {
                    <div
                        key={issue["id"]}
                        className="flex items-center gap-3 text-sm text-[var(--color-text-muted)]"
                    >
                        <span className="font-mono text-xs text-[#5b616e] shrink-0">
                            {issue["external_id"]}
                        </span>
                        <span className="truncate">{issue["title"]}</span>
                    </div>
                }}
            </div>
        </div>;
}
