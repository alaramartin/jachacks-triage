"""Agent 4 - Ranking. Fires (CLAUDE.md #5) whenever an urgency-relevant
property changes (blast_radius, severity, estimated_diff_lines). Writes
`urgency` onto Issue and Cluster. Formula + weights are LOCKED - CLAUDE.md #4.4.
Weight constants live here ONLY - do not redeclare them elsewhere."""

import from graph.nodes { Issue, File, Repo, Cluster, Settings, resolves_to }
import from agents.blast_radius { maybe_compute_blast_radius }
import from agents.clustering { maybe_cluster }

glob W_BLAST: float = 6.0;
glob W_SEV: float = 3.0;
glob W_DIFF: float = 1.0;

def _urgency(
    blast_radius: int, severity: int, estimated_diff_lines: int, file_count: int
) -> float {
    blast_norm: float = (blast_radius / file_count) if file_count > 0 else 0.0;
    sev_norm: float = severity / 10.0;
    diff_norm: float = min(estimated_diff_lines / 100.0, 1.0);
    urgency: float = (W_BLAST * blast_norm) + (W_SEV * sev_norm) - (W_DIFF * diff_norm);
    scaled: int = int(urgency * 100);
    return scaled / 100.0;
}

def rank_issue(issue: Issue, target: File, repo: Repo) -> float {
    issue.urgency = _urgency(
        target.blast_radius, issue.severity, issue.estimated_diff_lines, repo.file_count
    );
    return issue.urgency;
}

def rank_cluster(cluster: Cluster, members: list[Issue], repo: Repo) -> float {
    # CLAUDE.md #4.4: cluster ranking uses the cluster's own blast_radius, the
    # MAX severity of its members, and the MAX estimated_diff_lines.
    max_sev: int = max([m.severity for m in members]);
    max_diff: int = max([m.estimated_diff_lines for m in members]);
    cluster.urgency = _urgency(
        cluster.blast_radius, max_sev, max_diff, repo.file_count
    );
    return cluster.urgency;
}

"""Orchestrates the Agent 2 -> 3 -> 4 cascade for one newly-`resolves_to`'d
issue. A real event bus doesn't exist in a single-process demo, so this is the
one direct call `ingest_issue` (Person 2) makes right after creating the
`resolves_to` edge - everything downstream still re-reads graph state fresh
(blast radius re-walks `imports`, clustering re-reads ALL current
`resolves_to` edges on the file) rather than being handed values directly."""
def on_issue_resolved(issue: Issue, target: File, repo: Repo) -> None {
    maybe_compute_blast_radius(target);
    cluster: Cluster | None = maybe_cluster(target);

    if cluster is not None {
        members: list[Issue] = [target<-:resolves_to:<-];
        rank_cluster(cluster, members, repo);
        for m in members {
            rank_issue(m, target, repo);
        }
    } else {
        rank_issue(issue, target, repo);
    }
}

"""(REACH, PLAN.md Phase C step 3) Personalized re-rank used ONLY by get_queue's read-time
display - never by the ingest-time cascade above, so the demo's stored Issue/Cluster.urgency
stays blast-dominant-by-default regardless of what a viewer's weights panel is set to.
max_reactions/max_comment_velocity are the repo-wide maxima (0 => that term contributes 0,
same convention as blast_norm when file_count is 0)."""
def weighted_urgency(
    blast_radius: int,
    severity: int,
    estimated_diff_lines: int,
    reactions: int,
    comment_velocity: float,
    file_count: int,
    max_reactions: int,
    max_comment_velocity: float,
    settings: Settings
) -> float {
    blast_norm: float = (blast_radius / file_count) if file_count > 0 else 0.0;
    sev_norm: float = severity / 10.0;
    diff_norm: float = min(estimated_diff_lines / 100.0, 1.0);
    reactions_norm: float = (reactions / max_reactions) if max_reactions > 0 else 0.0;
    velocity_norm: float = (comment_velocity / max_comment_velocity)
        if max_comment_velocity > 0
        else 0.0;
    urgency: float = (
        (settings.w_blast * blast_norm) + (settings.w_sev * sev_norm) - (
            settings.w_diff * diff_norm
        ) + (settings.w_reactions * reactions_norm) + (
            settings.w_comment_velocity * velocity_norm
        )
    );
    scaled: int = int(urgency * 100);
    return scaled / 100.0;
}

"""Cluster counterpart of weighted_urgency - MAX reactions/comment_velocity across members,
matching the existing MAX-severity/MAX-diff convention (CLAUDE.md #4.4)."""
def weighted_cluster_urgency(
    cluster_blast_radius: int,
    members: list[Issue],
    file_count: int,
    max_reactions: int,
    max_comment_velocity: float,
    settings: Settings
) -> float {
    max_sev: int = max([m.severity for m in members]);
    max_diff: int = max([m.estimated_diff_lines for m in members]);
    max_member_reactions: int = max([m.reactions for m in members]);
    max_member_velocity: float = max([m.comment_velocity for m in members]);
    return weighted_urgency(
        cluster_blast_radius,
        max_sev,
        max_diff,
        max_member_reactions,
        max_member_velocity,
        file_count,
        max_reactions,
        max_comment_velocity,
        settings
    );
}
