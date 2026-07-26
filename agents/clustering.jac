"""Agent 3 - Clustering. Fires (CLAUDE.md #5) when a `resolves_to` edge lands
on a File that already has >=1 other incoming `resolves_to` edge.

CLAUDE.md #4.5 - the over-clustering guard is mandatory, not optional:
step 1 groups candidates by shared target File (pure graph read, done by the
caller just creating the edge); step 2 gates that group with `by llm()` - do
these issues actually share ONE root cause? SEED-15 (typo) and SEED-16 (perf)
both resolve to services/orders.py and must NOT cluster."""

import os;
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

"""Best-effort read of the target file's actual source (demo convention:
seed/repo/, same as main.jac's ingest_issue - see its TODO(P1) note about
storing repo_path on Repo once that schema field exists). Empty string if
unreadable - the gate degrades to text-only judgment, never errors."""
def _read_source(path: str) -> str {
    full_path: str = os.path.join("seed/repo", path);
    if not os.path.exists(full_path) {
        return "";
    }
    fh = open(full_path, "r");
    source: str = fh.read();
    fh.close();
    return source;
}

obj RootCauseGate {
    has same_root_cause: bool;
    has title: str;  # short title IF same_root_cause, else ""
    has root_cause_summary: str;  # 1-3 sentences IF same_root_cause, else ""
    has proposed_fix_summary: str;  # 1 sentence, mechanical fix suggestion IF same_root_cause, else ""
}

sem RootCauseGate = "Whether a set of bug reports, all resolved to the same source file, share one underlying root cause - plus a title and explanation when they do.";
sem RootCauseGate.same_root_cause = "True if EVERY issue below is best explained by ONE identifiable pattern of sloppiness in the target file that a single focused PR would naturally fix together - even if it touches two nearby functions/fields, as long as they share the same root sloppiness (e.g. 'this file is careless about numeric types/bounds': a price read as the wrong numeric type in one method AND a stock counter with no lower-bound check in a neighboring method are the SAME root cause, a type/bounds-discipline problem, fixable in one PR). False only when the issues are truly unrelated in cause AND fix - a cosmetic typo in a message string has NOTHING to do with a slow database query, even though both live in the same file; those need two separate PRs by two different people. When in doubt, ask: would ONE engineer, looking at this file, plausibly fix all of these in the same sitting as one coherent change? If yes, True.";
sem RootCauseGate.title = "A short (<12 word) title naming the shared root cause. Empty string if same_root_cause is False.";
sem RootCauseGate.root_cause_summary = "1-3 sentences: what's actually broken in the target file and why all these reports trace back to it. Empty string if same_root_cause is False.";
sem RootCauseGate.proposed_fix_summary = "One sentence describing a plausible, mechanically simple code-level fix for the shared root cause (e.g. 'Add a None guard and normalize unicode before length checks.'). Empty string if same_root_cause is False.";

def assess_root_cause(
    target_path: str, source_code: str, issue_summaries: list[str]
) -> RootCauseGate by llm(temperature=0.0);
sem assess_root_cause = "Decide whether a group of bug reports that all point at the same source file share one underlying root cause, or are unrelated problems that happen to live in the same file. The reports are DELIBERATELY worded to share little or no vocabulary even when they share a cause (a crash, a truncated emoji, a rejected phone number, and a skipped CSV row can all trace back to the same validation bug) - so judge by reading the actual source code below and checking whether each report's symptom plausibly flows from the SAME function/bug in that code, not by comparing the reports' wording to each other. If the code shows a specific bug (e.g. a missing None check, a byte-vs-character truncation bug), match reports against what THAT bug would actually cause.";
sem assess_root_cause.target_path = "The shared source file all these issues resolve to.";
sem assess_root_cause.source_code = "The actual current source of target_path, if available (empty string if not) - read it to judge whether reports plausibly share one root cause in this code, don't just compare report wording.";
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
    source_code: str = _read_source(target.path);
    gate: RootCauseGate = assess_root_cause(target.path, source_code, summaries);

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
        cluster = repos[0] +>:owns:+> Cluster(cluster_key=target.path);
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
