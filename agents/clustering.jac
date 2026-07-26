"""Agent 3 - Clustering. Fires (CLAUDE.md #5) when a `resolves_to` edge lands
on a File that already has >=1 other incoming `resolves_to` edge.

CLAUDE.md #4.5 - the over-clustering guard is mandatory, not optional:
step 1 groups candidates by shared target File (pure graph read, done by the
caller just creating the edge); step 2 gates that group with `by llm()` - do
these issues actually share ONE root cause? SEED-15 (typo) and SEED-16 (perf)
both resolve to services/orders.py and must NOT cluster."""

import from graph.nodes {
    Repo,
    File,
    Issue,
    Cluster,
    owns,
    resolves_to,
    grouped_in,
    cluster_targets
}

obj RootCauseGate {
    has same_root_cause: bool;
    has title: str;  # short title IF same_root_cause, else ""
    has root_cause_summary: str;  # 1-3 sentences IF same_root_cause, else ""
    has proposed_fix_summary:
        str;  # 1 sentence, mechanical fix suggestion IF same_root_cause, else ""
}

sem RootCauseGate = "Whether a set of bug reports, all resolved to the same source file, share one underlying root cause - plus a title and explanation when they do.";
sem RootCauseGate.same_root_cause = "True only if EVERY issue below is best explained by the SAME underlying bug in the target file - not just the same file. A typo fix and a performance problem in the same file are NOT the same root cause; a None-handling bug and a related unicode-truncation bug in the same function ARE.";
sem RootCauseGate.title = "A short (<12 word) title naming the shared root cause. Empty string if same_root_cause is False.";
sem RootCauseGate.root_cause_summary = "1-3 sentences: what's actually broken in the target file and why all these reports trace back to it. Empty string if same_root_cause is False.";
sem RootCauseGate.proposed_fix_summary = "One sentence describing a plausible, mechanically simple code-level fix for the shared root cause (e.g. 'Add a None guard and normalize unicode before length checks.'). Empty string if same_root_cause is False.";

def assess_root_cause(target_path: str, issue_summaries: list[str]) -> RootCauseGate by llm();
sem assess_root_cause = "Decide whether a group of bug reports that all point at the same source file share one underlying root cause, or are unrelated problems that happen to live in the same file.";
sem assess_root_cause.target_path = "The shared source file all these issues resolve to.";
sem assess_root_cause.issue_summaries = "One string per issue, formatted '<external_id>: <title> - <body>'.";

"""The graph-state trigger point: call right after a `resolves_to` edge
lands on `target`. Re-evaluates clustering from ALL issues currently
resolving to `target` (not just the new one) - the LLM gate always sees
the full current group, so re-ingestion is idempotent."""
def maybe_cluster(target: File) -> Cluster | None {
    members: list[Issue] = [target<-:resolves_to:<-];
    existing: list[Cluster] = [target<-:cluster_targets:<-];

    if len(members) < 2 {
        return existing[0] if len(existing) > 0 else None;
    }

    summaries: list[str] = [f"{m.external_id}: {m.title} - {m.body}" for m in members];
    gate: RootCauseGate = assess_root_cause(target.path, summaries);

    if not gate.same_root_cause {
        # Over-clustering guard tripped - drop any stale grouping so members
        # fall back to being singletons.
        for m in members {
            for e in [edge m->:grouped_in:->] {
                del e;
            }
        }
        for c in existing {
            if len([c<-:grouped_in:<-]) == 0 {
                del c;
            }
        }
        return None;
    }

    cluster: Cluster;
    if len(existing) > 0 {
        cluster = existing[0];
    } else {
        repos: list[Repo] = [target<-:owns:<-][?:Repo];
        cluster = (repos[0] +>:owns:+> Cluster(cluster_key=target.path))[0];
        cluster +>:cluster_targets:+> target;
    }

    cluster.title = gate.title;
    cluster.root_cause_summary = gate.root_cause_summary;
    cluster.proposed_fix_summary = gate.proposed_fix_summary;
    cluster.issue_count = len(members);
    cluster.blast_radius = target.blast_radius;
    max_diff: int = max([m.estimated_diff_lines for m in members]);
    cluster.fix_confidence = _fix_confidence(max_diff);

    for m in members {
        if len([m->:grouped_in:->]) == 0 {
            m +>:grouped_in:+> cluster;
        }
    }

    return cluster;
}

def _fix_confidence(max_diff_lines: int) -> float {
    # Mechanically simple fixes (small diffs) score high; sprawling ones score low.
    score: float = 1.0 - min(max_diff_lines / 150.0, 0.9);
    scaled: int = int(score * 100);
    return scaled / 100.0;
}
