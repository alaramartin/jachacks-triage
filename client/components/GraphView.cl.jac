"""Static SVG blast-radius visualization - the target node lighting up ~14 of 18 files.

Static-but-legible beats animated-but-messy (CLAUDE.md §8 beat 3). Layout is a
plain concentric-ring placement by `hops` - no graph-drawing library needed.
"""

import from ..types { ClusterGraph, GraphNode }

obj NodePos {
    has x: float,
        y: float;
}

def ring_positions(nodes: list[GraphNode], radius: float, cx: float, cy: float, positions: dict[str, NodePos]) -> None {
    count = len(nodes);
    if count == 0 { return; }
    for (i, n) in enumerate(nodes) {
        angle = 2.0 * Math.PI * (i * 1.0) / (count * 1.0);
        positions[n.id] = NodePos(x=cx + radius * Math.cos(angle), y=cy + radius * Math.sin(angle));
    }
}

def node_radius(n: GraphNode) -> float {
    if n.role == "target" { return 18.0; }
    if n.hops == 1 { return 11.0; }
    if n.hops == 2 { return 8.5; }
    return 6.5;
}

def node_fill(n: GraphNode) -> str {
    if n.role == "target" { return "#ff5d5d"; }
    if n.role == "neutral" { return "#3f4657"; }
    if n.hops == 1 { return "#4ade80"; }
    if n.hops == 2 { return "#22c55e"; }
    return "#15803d";
}

def:pub GraphView(graph: ClusterGraph) -> JsxElement {
    width: float = 640.0;
    height: float = 460.0;
    cx: float = width / 2.0;
    cy: float = height / 2.0 - 20.0;

    target_nodes = [n for n in graph.nodes if n.role == "target"];
    hop1 = [n for n in graph.nodes if n.role == "dependent" and n.hops == 1];
    hop2 = [n for n in graph.nodes if n.role == "dependent" and n.hops == 2];
    hop3 = [n for n in graph.nodes if n.role == "dependent" and n.hops == 3];
    neutral = [n for n in graph.nodes if n.role == "neutral"];

    positions: dict[str, NodePos] = {};
    if len(target_nodes) > 0 {
        positions[target_nodes[0].id] = NodePos(x=cx, y=cy);
    }
    ring_positions(hop1, 110.0, cx, cy, positions);
    ring_positions(hop2, 190.0, cx, cy, positions);
    ring_positions(hop3, 262.0, cx, cy, positions);
    for (i, n) in enumerate(neutral) {
        positions[n.id] = NodePos(x=36.0 + (i * 1.0) * 84.0, y=height - 22.0);
    }

    return <svg width="100%" viewBox={"0 0 " + str(width) + " " + str(height)} className="max-w-full">
        {for edge in graph.edges {
            if edge.from_file in positions and edge.to_file in positions {
                from_pos = positions[edge.from_file];
                to_pos = positions[edge.to_file];
                <line
                    key={edge.from_file + "->" + edge.to_file}
                    x1={from_pos.x} y1={from_pos.y} x2={to_pos.x} y2={to_pos.y}
                    stroke="#2a3143" strokeWidth={1.2}
                />
            }
        }}
        {for n in graph.nodes {
            if n.id in positions {
                pos = positions[n.id];
                r = node_radius(n);
                <g key={n.id}>
                    <circle cx={pos.x} cy={pos.y} r={r} fill={node_fill(n)} stroke="#0b0e14" strokeWidth={2} opacity={0.45 if n.role == "neutral" else 1.0} />
                    <text x={pos.x} y={pos.y + r + 12.0} textAnchor="middle" fontSize="9" fill="#8b93a7">{n.label}</text>
                </g>
            }
        }}
    </svg>;
}
