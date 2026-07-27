"""Small badge showing how an issue was resolved onto a code node."""

def:pub ResolutionBadge(method: str) -> JsxElement {
    label = "traceback"
        if method == "explicit"
        else ("inferred" if method == "llm" else "unresolved");
    tone = "border-[var(--color-green)]/40 bg-[var(--color-green-soft)] text-[var(--color-green)]"
        if method == "explicit"
        else (
            "border-[var(--color-border-strong)] bg-[var(--color-surface-raised)] text-[var(--color-text-muted)]"
        );
    return
        <span
            className={"inline-flex items-center rounded-full border px-2 py-0.5 text-[10px] font-medium uppercase tracking-[0.08em] " + tone}
        >
            {label}
        </span>;
}
