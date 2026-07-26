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
        for dependent in [current <-:imports:<-] {
            dep_id: str = jid(dependent);
            if dep_id not in visited {
                visited.add(dep_id);
                queue.append(dependent);
            }
        }
    }

    radius: int = len(visited) - 1;   # exclude target itself
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
