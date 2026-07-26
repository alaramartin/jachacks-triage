"""Triage client-side data shapes.

Mirrors the frozen `get_queue` / `get_cluster_detail` JSON contract in
CLAUDE.md §6. These are hand-built objs for the mock-data phase (Person 3
Phase A/B). When Person 1 ships the real endpoints, swap `mock_data.cl.jac`
callers for `sv import`-ed calls returning these same shapes (or the real
server-side types, if they differ) - see jac-fullstack-patterns.
"""

obj:pub IssueRef {
    has id: str,
        external_id: str,
        title: str,
        severity: int,
        resolution_method: str;
}

obj:pub ClusterSummary {
    has id: str,
        title: str,
        target_path: str,
        blast_radius: int,
        issue_count: int,
        max_severity: int,
        urgency: float,
        fix_confidence: float;
    has issues: list[IssueRef] = [];
}

obj:pub SingletonIssue {
    has id: str,
        external_id: str,
        title: str,
        target_path: str,
        blast_radius: int,
        severity: int,
        urgency: float,
        resolution_method: str;
}

obj:pub UnresolvedIssue {
    has id: str,
        external_id: str,
        title: str;
}

obj:pub QueueResponse {
    has repo: str,
        file_count: int;
    has clusters: list[ClusterSummary] = [],
        singletons: list[SingletonIssue] = [],
        unresolved: list[UnresolvedIssue] = [];
}

obj:pub ClusterIssueDetail {
    has id: str,
        external_id: str,
        title: str,
        body: str,
        severity: int,
        resolution_method: str;
}

obj:pub GraphNode {
    has id: str,
        label: str,
        role: str;
    has hops: int = 0;
}

obj:pub GraphEdge {
    has from_file: str,
        to_file: str;
}

obj:pub ClusterGraph {
    has nodes: list[GraphNode] = [],
        edges: list[GraphEdge] = [];
}

obj:pub ClusterDetail {
    has id: str,
        title: str,
        root_cause_summary: str,
        target_path: str,
        blast_radius: int,
        urgency: float,
        fix_confidence: float,
        proposed_fix_summary: str;
    has issues: list[ClusterIssueDetail] = [];
    has graph: ClusterGraph = ClusterGraph();
    has existing_pr: str | None = None;
}
