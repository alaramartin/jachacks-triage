"""A big, loud number + label - urgency and blast radius must catch the eye first."""

def:pub StatPill(value: str, label: str, emphasis: bool = False) -> JsxElement {
    value_cls = "text-3xl font-bold text-[var(--color-accent)]" if emphasis else "text-2xl font-semibold text-zinc-100";
    return <div className="flex flex-col items-center px-4">
        <span className={value_cls}>{value}</span>
        <span className="text-[11px] uppercase tracking-wider text-zinc-500 mt-0.5">{label}</span>
    </div>;
}
