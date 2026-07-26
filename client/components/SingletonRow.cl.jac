"""One singleton issue row on the ranked queue - same visual weight as a cluster row."""

import from .ResolutionBadge { ResolutionBadge }
import from .StatPill { StatPill }

def:pub SingletonRow(issue: dict) -> JsxElement {
    blast_radius = issue["blast_radius"];
    urgency = issue["urgency"] as float;

    return <div className="rounded-xl border border-[var(--color-border)] bg-[var(--color-surface)] flex items-center gap-6 px-5 py-4">
        <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2 mb-1">
                <span className="text-xs text-zinc-500 font-mono">{issue["external_id"]}</span>
                <span className="text-xs text-zinc-500 font-mono">· {issue["target_path"]}</span>
                <ResolutionBadge method={issue["resolution_method"]} />
            </div>
            <h3 className="text-base font-medium text-zinc-200 truncate">{issue["title"]}</h3>
        </div>

        <StatPill value={str(blast_radius) + (" file" if blast_radius == 1 else " files")} label="blast radius" />
        <StatPill value={f"{urgency:.2f}"} label="urgency" />
        <span className="text-xs text-zinc-500 w-14 text-right shrink-0">sev {str(issue["severity"])}</span>
    </div>;
}
