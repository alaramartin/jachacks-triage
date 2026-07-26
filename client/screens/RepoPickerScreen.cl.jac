"""Repo picker - lists the user's repos. Only one (real target: the seed repo).

MOCK DATA: the repo name comes from mock_data.cl.jac, not a live GitHub API
call. Person 2's github.jac list_repos() replaces this in Phase B/C.
"""

import from "@jac/runtime" { useNavigate }
import from ..mock_data { mock_queue }

def:pub RepoPickerScreen() -> JsxElement {
    nav = useNavigate();

    def handle_select(_e: MouseEvent) {
        nav("/queue");
    }

    return <div className="min-h-screen flex flex-col items-center justify-center px-4">
        <div className="w-full max-w-md">
            <h2 className="text-xl font-semibold text-zinc-100 mb-1">Choose a repository</h2>
            <p className="text-sm text-zinc-500 mb-6">(mock listing - real GitHub repos land in Phase B)</p>
            <button
                onClick={handle_select}
                className="w-full flex items-center justify-between rounded-xl border border-[var(--color-border)] bg-[var(--color-surface)] px-5 py-4 hover:bg-[var(--color-surface-raised)] transition-colors text-left"
            >
                <div>
                    <div className="font-semibold text-zinc-100">{mock_queue["repo"]}</div>
                    <div className="text-xs text-zinc-500 mt-0.5">{str(mock_queue["file_count"])} files indexed</div>
                </div>
                <span className="text-zinc-500">→</span>
            </button>
        </div>
    </div>;
}
