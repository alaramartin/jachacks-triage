"""Ranking-priority controls - the 'settings / priorities for how to rank' corner
of the queue sketch.

LIVE: the sliders write to the real `set_weights` walker (the parent screen owns
the RPC) and `get_queue` re-ranks against them on the next fetch. The values
shown are the repo's STORED weights, echoed back by get_queue alongside the
queue they produced - not client-side defaults, so a saved preference survives
a reload.

Defaults are the locked blast-dominant weights from CLAUDE.md 4.4, and the two
social-signal weights default to ZERO. That matters for the project's central
claim: out of the box the ranking is still ~80% structural and no upvote or
comment-velocity signal touches it. Turning them up is an explicit, visible
choice by the person looking at the queue.
"""

# One row per weight: the key set_weights expects, a label, the ceiling of its
# slider, and one line explaining what moving it actually does. The copy is the
# point - a slider called "reactions" with no explanation invites someone to
# drag it and quietly undo the thing that makes this ranking worth looking at.
glob WEIGHT_ROWS: list[dict] = [
         {
             "key": "w_blast",
             "label": "blast radius",
             "max": 10.0,
             "hint": "How many files transitively depend on the code an issue points at. The structural signal only the graph can give you."
         },
         {
             "key": "w_sev",
             "label": "severity",
             "max": 10.0,
             "hint": "How bad the report sounds, judged from its text. A crash outranks a typo."
         },
         {
             "key": "w_diff",
             "label": "diff size penalty",
             "max": 10.0,
             "hint": "Pushes sprawling fixes DOWN the queue. Raise it to favour quick wins."
         },
         {
             "key": "w_reactions",
             "label": "reactions",
             "max": 10.0,
             "hint": "Social signal: how many people reacted on GitHub. Off by default - popularity is not blast radius."
         },
         {
             "key": "w_comment_velocity",
             "label": "comment velocity",
             "max": 10.0,
             "hint": "Social signal: comments per day since the issue was opened. Off by default - a loud thread is not a structural risk."
         }
     ];

def:pub SettingsPanel(
    w_blast: float,
    w_sev: float,
    w_diff: float,
    w_reactions: float,
    w_comment_velocity: float,
    open: bool,
    onToggle: Callable[[], None],
    onChange: Callable[[str, float], None],
    onReset: Callable[[], None]
) -> JsxElement {
    def handle_toggle(_e: MouseEvent) {
        onToggle();
    }

    def handle_reset(_e: MouseEvent) {
        onReset();
    }

    def value_for(key: str) -> float {
        if key == "w_blast" {
            return w_blast;
        }
        if key == "w_sev" {
            return w_sev;
        }
        if key == "w_diff" {
            return w_diff;
        }
        if key == "w_reactions" {
            return w_reactions;
        }
        return w_comment_velocity;
    }

    # True when the two social weights are untouched - lets the panel state the
    # "purely structural" claim only while it is actually true.
    structural_only = w_reactions == 0.0 and w_comment_velocity == 0.0;

    def slider(row: dict) -> JsxElement {
        key = row["key"] as str;
        value = value_for(key);

        def handle_input(e: any) {
            onChange(key, float(e.target.value));
        }
        return
            <label key={key} className="block">
                <div
                    className="flex items-baseline justify-between text-[11px] uppercase tracking-[0.1em] text-[var(--color-text-muted)]"
                >
                    <span>{row["label"]}</span>
                    <span className="font-mono text-[var(--color-orange)]">
                        {f"{value:.1f}"}
                    </span>
                </div>
                <input
                    type="range"
                    min="0"
                    max={f"{row['max'] as float:.1f}"}
                    step="0.5"
                    value={f"{value:.1f}"}
                    onChange={handle_input}
                    className="mt-1.5 w-full"
                />
                <p className="mt-1 text-[11px] leading-snug text-[var(--color-text-muted)]">
                    {row["hint"]}
                </p>
            </label>;
    }

    return
        <div className="relative">
            <button
                onClick={handle_toggle}
                aria-expanded={open}
                className="flex items-center gap-2 rounded-lg border border-[var(--color-border)] px-3 py-2 text-xs text-[var(--color-text-muted)] transition-colors hover:border-[var(--color-border-strong)] hover:text-[var(--color-text)]"
            >
                <svg
                    width="14"
                    height="14"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="2"
                    aria-hidden="true"
                >
                    <line x1="4" y1="7" x2="20" y2="7"/>
                    <circle cx="9" cy="7" r="2.5" fill="var(--color-bg)"/>
                    <line x1="4" y1="17" x2="20" y2="17"/>
                    <circle cx="16" cy="17" r="2.5" fill="var(--color-bg)"/>
                </svg>
                Ranking priorities
            </button>
            {if open {
                <div
                    key="panel"
                    className="absolute right-0 z-10 mt-2 w-80 max-h-[70vh] overflow-y-auto rounded-xl border border-[var(--color-border)] bg-[var(--color-surface)] p-4"
                >
                    <p className="mb-4 text-xs leading-relaxed text-[var(--color-text-muted)]">
                        {"Ranking is blast-radius-dominant by default - structural, not textual."
                            if structural_only
                            else "Social signals are on. The order below is no longer purely structural."}
                    </p>
                    <div className="flex flex-col gap-4">
                        {[slider(row) for row in WEIGHT_ROWS]}
                    </div>
                    <button
                        onClick={handle_reset}
                        disabled={structural_only
                        and w_blast == 6.0
                        and w_sev == 3.0
                        and w_diff == 1.0}
                        className="mt-4 w-full rounded-lg border border-[var(--color-border)] px-3 py-2 text-xs text-[var(--color-text-muted)] transition-colors hover:border-[var(--color-orange)] hover:text-[var(--color-text)] disabled:opacity-40 disabled:hover:border-[var(--color-border)]"
                    >
                        Reset to structural defaults
                    </button>
                </div>
            }}
        </div>;
}
