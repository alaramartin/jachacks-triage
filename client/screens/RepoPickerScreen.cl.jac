"""Repo picker - "your projects" grid.

LIVE DATA: the card's repo name and file count come from walker/get_queue against
the real indexed graph. We deliberately do NOT fabricate a list of other repos -
GitHub OAuth is WIP (see PLAN.md "WEBSITE UI"), so the only repo we can speak for
is the one we hold a PAT for. The second tile is an explicitly disabled
placeholder that says so rather than inventing repo names.
"""

import from "@jac/runtime" { useNavigate }
sv import from ...main { get_queue }

glob DEMO_REPO: str = "alaramartin/triage-demo";

def:pub RepoPickerScreen -> JsxElement {
    has repo_name: str = DEMO_REPO,
        file_count: int = 0,
        loading: bool = True;

    nav = useNavigate();

    async can with entry {
        result = root spawn get_queue(full_name=DEMO_REPO);
        if result.reports and len(result.reports) > 0 {
            resp = result.reports[0];
            repo_name = resp.repo;
            file_count = resp.file_count;
        }
        loading = False;
    }

    def handle_select(_e: MouseEvent) {
        nav("/queue");
    }

    owner = repo_name.split("/")[0] if "/" in repo_name else "";
    short_name = repo_name.split("/")[-1];

    return
        <div className="min-h-screen px-6 sm:px-12 py-12 max-w-5xl mx-auto">
            <div className="flex items-baseline gap-3">
                <h1 className="text-xl font-semibold tracking-tight text-[var(--color-text)]">
                    Your projects
                </h1>
                <span className="text-xs text-[var(--color-text-muted)]">
                    repositories Triage has indexed
                </span>
            </div>
            <div className="mt-8 grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
                <button
                    onClick={handle_select}
                    disabled={loading}
                    className="group text-left rounded-xl border border-[var(--color-border)] bg-[var(--color-surface)] p-5 transition-colors hover:border-[var(--color-orange)] hover:bg-[var(--color-surface-raised)] disabled:opacity-40"
                >
                    <div className="flex items-start justify-between gap-3">
                        <div className="min-w-0">
                            <div className="text-xs font-mono text-[var(--color-text-muted)] truncate">
                                {owner}
                            </div>
                            <div className="mt-0.5 text-base font-semibold text-[var(--color-text)] truncate">
                                {short_name}
                            </div>
                        </div>
                        <span
                            className="shrink-0 text-[var(--color-text-muted)] transition-colors group-hover:text-[var(--color-orange)]"
                        >
                            →
                        </span>
                    </div>
                    <div className="mt-6 flex items-center gap-2 text-xs text-[var(--color-text-muted)]">
                        <span
                            className="inline-block h-1.5 w-1.5 rounded-full bg-[var(--color-green)]"
                        />
                        {"indexing..." if loading else str(file_count) + " files indexed"}
                    </div>
                </button>
                <div
                    className="rounded-xl border border-dashed border-[var(--color-border)] p-5 opacity-60"
                >
                    <div className="text-base font-medium text-[var(--color-text-muted)]">
                        Connect more repositories
                    </div>
                    <div className="mt-6 text-xs text-[#5b616e]">
                        GitHub OAuth is a work in progress. Only repositories with a configured token appear here.
                    </div>
                </div>
            </div>
        </div>;
}
