"""Ranking-priority controls - the 'settings / priorities for how to rank' corner
of the queue sketch.

LIVE: the sliders write to the real `set_weights` walker (the parent screen owns
the RPC) and `get_queue` re-ranks against them on the next fetch. Defaults are
the locked blast-dominant weights from CLAUDE.md 4.4.
"""

def:pub SettingsPanel(
    w_blast: float,
    w_sev: float,
    w_diff: float,
    open: bool,
    onToggle: Callable[[], None],
    onChange: Callable[[str, float], None]
) -> JsxElement {
    def handle_toggle(_e: MouseEvent) {
        onToggle();
    }

    def slider(key: str, label: str, value: float, max_value: float) -> JsxElement {
        def handle_input(e: any) {
            onChange(key, float(e.target.value));
        }
        return
            <label key={key} className="block">
                <div
                    className="flex items-baseline justify-between text-[11px] uppercase tracking-[0.1em] text-[var(--color-text-muted)]"
                >
                    <span>{label}</span>
                    <span className="font-mono text-[var(--color-orange)]">
                        {f"{value:.1f}"}
                    </span>
                </div>
                <input
                    type="range"
                    min="0"
                    max={f"{max_value:.1f}"}
                    step="0.5"
                    value={f"{value:.1f}"}
                    onChange={handle_input}
                    className="mt-1.5 w-full"
                />
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
                    className="absolute right-0 z-10 mt-2 w-72 rounded-xl border border-[var(--color-border)] bg-[var(--color-surface)] p-4"
                >
                    <p className="mb-4 text-xs leading-relaxed text-[var(--color-text-muted)]">
                        Defaults are blast-radius-dominant - the structural signal only the graph can give you.
                    </p>
                    <div className="flex flex-col gap-4">
                        {slider("w_blast", "blast radius", w_blast, 10.0)}
                        {slider("w_sev", "severity", w_sev, 10.0)}
                        {slider("w_diff", "diff size penalty", w_diff, 10.0)}
                    </div>
                </div>
            }}
        </div>;
}
