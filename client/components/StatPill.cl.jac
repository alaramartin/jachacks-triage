"""A big, loud number + label - urgency and blast radius must catch the eye first.

`emphasis` = the structural number (blast radius). Orange, because that is what
the graph is shouting about; green is reserved for things you click.
"""

def:pub StatPill(value: str, label: str, emphasis: bool = False) -> JsxElement {
    value_cls = "text-2xl font-bold tracking-tight text-[var(--color-orange)]"
        if emphasis
        else "text-2xl font-semibold tracking-tight text-[var(--color-text)]";
    return
        <div className="flex flex-col">
            <span className={value_cls}>{value}</span>
            <span
                className="mt-0.5 text-[10px] uppercase tracking-[0.12em] text-[var(--color-text-muted)]"
            >
                {label}
            </span>
        </div>;
}
