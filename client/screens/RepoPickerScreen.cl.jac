"""Repo picker - lists the user's repos. Only one (the seed demo repo).

LIVE DATA: repo name/file count come from walker/get_queue against the real
indexed graph. Full GitHub-account repo listing stays an accepted, documented
scope cut (CLAUDE.md/PLAN.md: OAuth login is the first thing cut if it fights
us - it adds nothing to the graph story) - this repo is the only one in scope
for the demo either way.
"""

import from "@jac/runtime" { useNavigate }
sv import from ...main { get_queue }

glob DEMO_REPO: str = "triage-demo/shipyard";

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

    return
        <div className="min-h-screen flex flex-col items-center justify-center px-4">
            <div className="w-full max-w-md">
                <h2 className="text-xl font-semibold text-zinc-100 mb-1">
                    Choose a repository
                </h2>
                <p className="text-sm text-zinc-500 mb-6">
                    (single demo repo - live GitHub account listing is a scope cut)
                </p>
                <button
                    onClick={handle_select}
                    disabled={loading}
                    className="w-full flex items-center justify-between rounded-xl border border-[var(--color-border)] bg-[var(--color-surface)] px-5 py-4 hover:bg-[var(--color-surface-raised)] transition-colors text-left disabled:opacity-50"
                >
                    <div>
                        <div className="font-semibold text-zinc-100">
                            {repo_name}
                        </div>
                        <div className="text-xs text-zinc-500 mt-0.5">
                            {"loading..." if loading else str(file_count) + " files indexed"}
                        </div>
                    </div>
                    <span className="text-zinc-500">→</span>
                </button>
            </div>
        </div>;
}
