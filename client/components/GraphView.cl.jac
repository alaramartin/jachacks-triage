"""SVG blast-radius visualization - the target node lighting up ~14 of 18 files.

Layout is a plain concentric-ring placement by `hops` - no graph-drawing
library needed. Rings reveal outward from the target on a timer (CLAUDE.md §8
beat 3: "the walker traversal lights up 14 of 18 files" - the walker-walking
moment), static once fully revealed so it stays legible, not messy.

Nodes/edges are plain dicts (not `obj`) - Jac's client codegen compiles
`SomeObj(field=val)` construction to a bare JS call missing `new`, which
throws at runtime. See mock_data.cl.jac for the fuller note. Subscripting an
untyped dict yields `any`, so call sites below cast explicitly (`as str`,
`as float`, `as list[dict]`) wherever the strict type checker needs a
concrete type (Callable params, len(), string concat, arithmetic).
"""

import from react { useEffect }

def ring_positions(
    nodes: list[dict], radius: float, cx: float, cy: float, positions: dict[str, dict]
) -> None {
    count = len(nodes);
    if count == 0 {
        return;
    }
    for (i, n) in enumerate(nodes) {
        angle = 2.0 * Math.PI * (i * 1.0) / (count * 1.0);
        positions[n["id"] as str] = {
            "x": cx + radius * Math.cos(angle),
            "y": cy + radius * Math.sin(angle)
        };
    }
}

def node_radius(n: dict) -> float {
    if n["role"] == "target" {
        return 18.0;
    }
    if n["hops"] == 1 {
        return 11.0;
    }
    if n["hops"] == 2 {
        return 8.5;
    }
    return 6.5;
}

def node_fill(n: dict) -> str {
    if n["role"] == "target" {
        return "#ff5d5d";
    }
    if n["role"] == "neutral" {
        return "#3f4657";
    }
    if n["hops"] == 1 {
        return "#4ade80";
    }
    if n["hops"] == 2 {
        return "#22c55e";
    }
    return "#15803d";
}

# Reveal order: target first, then ring-by-ring outward. Neutral files were
# never reached, so they're visible from the start as dim context.
def node_reveal_step(n: dict) -> int {
    if n["role"] == "neutral" {
        return 0;
    }
    if n["role"] == "target" {
        return 1;
    }
    return (n["hops"] as int) + 1;
}

def:pub GraphView(graph: dict) -> JsxElement {
    has revealed: int = 0;

    useEffect(
        lambda {
            step = 0;
            interval = setInterval(
                lambda {
                    step = step + 1;
                    revealed = step;
                    if step >= 4 {
                        clearInterval(interval);
                    }
                },
                350
            );
            return lambda { clearInterval(interval); };
        },
        []
    );

    width: float = 640.0;
    height: float = 460.0;
    cx: float = width / 2.0;
    cy: float = height / 2.0 - 20.0;

    nodes = graph["nodes"] as list[dict];
    edges = graph["edges"] as list[dict];

    target_nodes = [
        n
        for n in nodes
        if n["role"] == "target"
    ];
    hop1 = [
        n
        for n in nodes
        if n["role"] == "dependent" and n["hops"] == 1
    ];
    hop2 = [
        n
        for n in nodes
        if n["role"] == "dependent" and n["hops"] == 2
    ];
    hop3 = [
        n
        for n in nodes
        if n["role"] == "dependent" and n["hops"] == 3
    ];
    neutral = [
        n
        for n in nodes
        if n["role"] == "neutral"
    ];

    positions: dict[str, dict] = {};
    if len(target_nodes) > 0 {
        positions[target_nodes[0]["id"] as str] = {"x": cx, "y": cy};
    }
    ring_positions(hop1, 110.0, cx, cy, positions);
    ring_positions(hop2, 190.0, cx, cy, positions);
    ring_positions(hop3, 262.0, cx, cy, positions);
    for (i, n) in enumerate(neutral) {
        positions[n["id"] as str] = {"x": 36.0 + (i * 1.0) * 84.0, "y": height - 22.0};
    }

    node_by_id: dict[str, dict] = {};
    for n in nodes {
        node_by_id[n["id"] as str] = n;
    }

    return
        <svg
            width="100%"
            viewBox={"0 0 " + str(width) + " " + str(height)}
            className="max-w-full"
        >
            {for edge in edges {
                from_id = edge["from"] as str;
                to_id = edge["to"] as str;
                if from_id in positions and to_id in positions {
                    from_pos = positions[from_id];
                    to_pos = positions[to_id];
                    from_step = node_reveal_step(node_by_id[from_id]);
                    to_step = node_reveal_step(node_by_id[to_id]);
                    edge_step = from_step if from_step > to_step else to_step;
                    <line
                        key={from_id + "->" + to_id}
                        x1={from_pos["x"] as float}
                        y1={from_pos["y"] as float}
                        x2={to_pos["x"] as float}
                        y2={to_pos["y"] as float}
                        stroke="#2a3143"
                        strokeWidth={1.2}
                        opacity={1.0 if revealed >= edge_step else 0.0}
                        style={{"transition": "opacity 300ms ease"}}
                    />
                }
            }}
            {for n in nodes {
                node_id = n["id"] as str;
                if node_id in positions {
                    pos = positions[node_id];
                    px = pos["x"] as float;
                    py = pos["y"] as float;
                    r = node_radius(n);
                    step = node_reveal_step(n);
                    base_opacity = 0.45 if n["role"] == "neutral" else 1.0;
                    <g
                        key={node_id}
                        opacity={base_opacity if revealed >= step else 0.0}
                        style={{"transition": "opacity 350ms ease"}}
                    >
                        <circle
                            cx={px}
                            cy={py}
                            r={r}
                            fill={node_fill(n)}
                            stroke="#0b0e14"
                            strokeWidth={2}
                        />
                        <text
                            x={px}
                            y={py + r + 12.0}
                            textAnchor="middle"
                            fontSize="9"
                            fill="#8b93a7"
                        >
                            {n["label"] as str}
                        </text>
                    </g>
                }
            }}
        </svg>;
}
