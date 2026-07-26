"""Agent 2 - Blast Radius. Fires (per CLAUDE.md #5) when a new `resolves_to`
edge lands on a File whose blast_radius is still -1 (not yet computed).

CLAUDE.md #4.3 - THE #1 SOURCE OF BUGS:
  File_A -:imports:-> File_B  means "A imports B" => "A depends on B".
  blast_radius(B) = count of distinct File nodes that can transitively reach B
  by following `imports` forward = a REVERSE BFS from B over INCOMING `imports`
  edges, with a visited set, NOT counting B itself.
Wrong direction gives tiny numbers (0/1/2) on core/validation.py; correct is 14."""

import from graph.nodes { File, imports }

def compute_blast_radius(target: File) -> int {
    visited: set[str] = set();
    visited.add(jid(target));
    queue: list[File] = [target];

    while len(queue) > 0 {
        current: File = queue.pop(0);
        for dependent in [current<-:imports:<-] {
            dep_id: str = jid(dependent);
            if dep_id not in visited {
                visited.add(dep_id);
                queue.append(dependent);
            }
        }
    }

    radius: int = len(visited) - 1;  # exclude target itself
    target.blast_radius = radius;
    return radius;
}

"""The graph-state trigger point: call right after a `resolves_to` edge
lands on `target` (CLAUDE.md #5's firing condition). Guarded on
blast_radius == -1 so re-ingestion / re-clustering never recomputes."""
def maybe_compute_blast_radius(target: File) -> int {
    if target.blast_radius == -1 {
        return compute_blast_radius(target);
    }
    return target.blast_radius;
}

"""Powers get_cluster_detail's `graph` payload (CLAUDE.md #6): same reverse
BFS as compute_blast_radius, but keeps hop distance per node and the
in-set `imports` edges instead of collapsing to a count. `id`/`label` use
the File's path (not jid) to match the frozen API example. Edges are kept
in code direction (`from` imports `to`) and only between two nodes that are
both in the reachable set."""
def build_dependency_graph(target: File) -> dict[str, list] {
    hops_by_id: dict[str, int] = {};
    file_by_id: dict[str, File] = {};
    target_id: str = jid(target);
    hops_by_id[target_id] = 0;
    file_by_id[target_id] = target;
    queue: list[File] = [target];

    while len(queue) > 0 {
        current: File = queue.pop(0);
        current_hops: int = hops_by_id[jid(current)];
        for dependent in [current<-:imports:<-] {
            dep_id: str = jid(dependent);
            if dep_id not in hops_by_id {
                hops_by_id[dep_id] = current_hops + 1;
                file_by_id[dep_id] = dependent;
                queue.append(dependent);
            }
        }
    }

    nodes: list[dict[str, object]] = [];
    for (fid, hops) in hops_by_id.items() {
        f: File = file_by_id[fid];
        role: str = "target" if fid == target_id else "dependent";
        nodes.append({"id": f.path, "label": f.path, "role": role, "hops": hops});
    }

    edges: list[dict[str, object]] = [];
    for fid in hops_by_id.keys() {
        f: File = file_by_id[fid];
        for imported in [f->:imports:->] {
            imported_id: str = jid(imported);
            if imported_id in hops_by_id {
                edges.append({"from": f.path, "to": imported.path});
            }
        }
    }

    return {"nodes": nodes, "edges": edges};
}
