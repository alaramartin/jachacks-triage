"""One issue pill - the stacked `issue #34385 (link)` chips from the queue sketch.

Links are best-effort and honest: seed issues carry `SEED-nn` external IDs which
are NOT GitHub issue numbers, so those render as plain (unlinked) chips. Only a
numeric external_id - i.e. a genuinely ingested GitHub issue - becomes an <a>.
"""

def _is_numeric(s: str) -> bool {
    if len(s) == 0 {
        return False;
    }
    for ch in s {
        if ch < "0" or ch > "9" {
            return False;
        }
    }
    return True;
}

def:pub IssueChip(external_id: str, title: str, repo: str = "") -> JsxElement {
    label = ("#" + external_id) if _is_numeric(external_id) else external_id;
    cls = "inline-flex items-center rounded-full border border-[var(--color-border-strong)] bg-[var(--color-surface-raised)] px-3 py-1 font-mono text-[11px] text-[var(--color-text-muted)] transition-colors";

    if _is_numeric(external_id) and repo != "" {
        return
            <a
                href={"https://github.com/" + repo + "/issues/" + external_id}
                target="_blank"
                rel="noreferrer"
                title={title}
                onClick={lambda (e: MouseEvent) -> None { e.stopPropagation(); }}
                className={cls + " hover:border-[var(--color-orange)] hover:text-[var(--color-orange)]"}
            >
                issue {label}
            </a>;
    }
    return <span title={title} className={cls}>{label}</span>;
}
