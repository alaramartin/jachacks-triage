"""The 'couldn't confidently place' bucket - a credibility beat, never hidden."""

import from ..types { UnresolvedIssue }

def:pub UnresolvedList(issues: list[UnresolvedIssue]) -> JsxElement {
    return <div className="rounded-xl border border-dashed border-zinc-700 bg-zinc-900/40 px-5 py-4">
        <h3 className="text-sm font-semibold text-zinc-400 mb-2">
            Couldn't confidently place ({str(len(issues))})
        </h3>
        <p className="text-xs text-zinc-600 mb-3">Confidence below threshold - we don't guess. These are parked, not dropped.</p>
        <div className="flex flex-col gap-1.5">
            {for issue in issues {
                <div key={issue.id} className="flex items-center gap-2 text-sm text-zinc-500">
                    <span className="font-mono text-xs">{issue.external_id}</span>
                    <span>{issue.title}</span>
                </div>
            }}
        </div>
    </div>;
}
