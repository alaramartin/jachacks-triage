"""One standalone issue row on the ranked queue.

Same visual language as a cluster row, deliberately quieter (no orange, no
graph, no View detail) so the eye lands on clusters first - but it still gets a
Generate PR button, because a lone issue shouldn't be a dead end.

Hovering that button fetches walker/get_issue_fix_preview: two sentences, "the
issue" and "the fix". That's the same by llm() call generate_pr_for_issue builds
its PR from, so the hover text is what the PR would actually be based on. It is
fetched once per row and cached in local state.

Parked issues (`parked`: the ones Agent 1 wouldn't guess a file for) render in
this same list with " - " in place of every number and no PR button - there is
no code node to patch.
"""

sv import from ...main { get_issue_fix_preview }
import from .ResolutionBadge { ResolutionBadge }
import from .IssueChip { IssueChip }
import from .Spinner { Spinner }

glob DASH: str = "-";

def:pub SingletonRow(
    issue: dict,
    repo: str = "",
    onGeneratePr: Callable[[str], None] | None = None,
    generating: bool = False,
    drafted: bool = False
) -> JsxElement {
    has preview: dict | None = None,
        preview_loading: bool = False,
        hovering: bool = False;

    parked = issue["parked"] == True;
    issue_id = issue["id"] as str;

    async def load_preview {
        if preview is not None or preview_loading {
            return;
        }
        preview_loading = True;
        result = root spawn get_issue_fix_preview(issue_id=issue_id);
        if result.reports and len(result.reports) > 0 {
            preview = result.reports[0] as dict;
        }
        preview_loading = False;
    }

    async def handle_enter(_e: MouseEvent) {
        hovering = True;
        await load_preview();
    }

    def handle_leave(_e: MouseEvent) {
        hovering = False;
    }

    # Keyboard users get the same card - separate handlers because the JSX
    # checker types onFocus/onBlur as FocusEvent, not MouseEvent.
    async def handle_focus(_e: FocusEvent) {
        hovering = True;
        await load_preview();
    }

    def handle_blur(_e: FocusEvent) {
        hovering = False;
    }

    def handle_generate(e: MouseEvent) {
        e.stopPropagation();
        if onGeneratePr is not None {
            onGeneratePr(issue_id);
        }
    }

    return
        <div
            className={"rounded-xl border border-[var(--color-border)] bg-[var(--color-surface)] flex flex-wrap items-center gap-x-5 gap-y-2 px-5 py-3.5"
                + (" opacity-55" if drafted else "")}
        >
            <IssueChip
                external_id={issue["external_id"] as str}
                title={issue["title"] as str}
                repo={repo}
            />
            <div className="flex-1 min-w-0">
                <div className="text-[15px] text-[var(--color-text)] truncate">
                    {issue["title"]}
                </div>
                <div className="mt-1 flex items-center gap-2">
                    <span className="font-mono text-xs text-[var(--color-text-muted)] truncate">
                        {DASH if parked else issue["target_path"]}
                    </span>
                    <ResolutionBadge
                        method={"none" if parked else issue["resolution_method"]}
                    />
                </div>
            </div>
            <div
                className="flex items-center gap-5 shrink-0 text-xs text-[var(--color-text-muted)]"
            >
                <span>
                    <span className="text-base font-semibold text-[var(--color-text)]">
                        {DASH if parked else str(issue["blast_radius"])}
                    </span>
                    {" file downstream"
                        if (not parked and issue["blast_radius"] == 1)
                        else " files downstream"}
                </span>
                <span>
                    <span className="text-base font-semibold text-[var(--color-text)]">
                        {DASH if parked else f"{(issue['urgency'] as float):.2f}"}
                    </span>
                    {" urgency"}
                </span>
                <span className="w-12 text-right">
                    sev {DASH if parked else str(issue["severity"])}
                </span>
            </div>
            {if parked {
                <span
                    key="parked-note"
                    className="shrink-0 text-xs italic text-[#5b616e]"
                >
                    below confidence threshold - not placed
                </span>
            }}
            {if drafted {
                <a
                    key="pr-link"
                    href={issue["pr_url"]}
                    target="_blank"
                    rel="noreferrer"
                    className="shrink-0 rounded-lg border border-[var(--color-green)]/40 px-3.5 py-2 text-[12px] font-medium text-[var(--color-green)] transition-colors hover:bg-[var(--color-green-soft)]"
                >
                    PR #{str(issue["pr_number"])} →
                </a>
            }}
            {if not parked and not drafted {
                <div key="pr" className="relative shrink-0">
                    <button
                        onClick={handle_generate}
                        onMouseEnter={handle_enter}
                        onMouseLeave={handle_leave}
                        onFocus={handle_focus}
                        onBlur={handle_blur}
                        disabled={generating}
                        className="flex items-center gap-2 rounded-lg border border-[var(--color-green)]/50 px-3.5 py-2 text-[12px] font-semibold uppercase tracking-wide text-[var(--color-green)] transition-colors hover:bg-[var(--color-green-soft)] disabled:cursor-wait"
                    >
                        {if generating {
                            <Spinner key="sp" tone="light"/>
                        }}
                        {"Generating" if generating else "Generate PR"}
                    </button>
                    {if hovering and not generating {
                        <div
                            key="card"
                            role="tooltip"
                            className="absolute right-0 bottom-full z-20 mb-2 w-80 rounded-lg border border-[var(--color-border-strong)] bg-[var(--color-surface-raised)] p-3 text-left"
                        >
                            {if preview is not None and preview["ok"] {
                                <div key="body">
                                    <div
                                        className="text-[10px] font-semibold uppercase tracking-[0.12em] text-[var(--color-text-muted)]"
                                    >
                                        The issue
                                    </div>
                                    <p className="mt-1 text-xs leading-relaxed text-[var(--color-text)]">
                                        {preview["issue_summary"]}
                                    </p>
                                    <div
                                        className="mt-2.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-[var(--color-green)]"
                                    >
                                        The fix
                                    </div>
                                    <p className="mt-1 text-xs leading-relaxed text-[var(--color-text)]">
                                        {preview["fix_summary"]}
                                    </p>
                                </div>
                            }}
                            {if preview is None or not preview["ok"] {
                                <p
                                    key="pending"
                                    className="text-xs text-[var(--color-text-muted)]"
                                >
                                    {"Reading the issue..."
                                        if preview is None
                                        else "Couldn't summarize this one."}
                                </p>
                            }}
                        </div>
                    }}
                </div>
            }}
        </div>;
}
