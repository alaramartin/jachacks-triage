"""Small badge showing how an issue was resolved onto a code node."""

def:pub ResolutionBadge(method: str) -> JsxElement {
    label = "traceback" if method == "explicit" else ("inferred" if method == "llm" else "unresolved");
    tone = "bg-emerald-500/15 text-emerald-300 border-emerald-500/30" if method == "explicit" else (
        "bg-sky-500/15 text-sky-300 border-sky-500/30" if method == "llm" else
        "bg-zinc-500/15 text-zinc-300 border-zinc-500/30"
    );
    return <span className={"inline-flex items-center rounded-full border px-2 py-0.5 text-[11px] font-medium tracking-wide " + tone}>
        {label}
    </span>;
}
