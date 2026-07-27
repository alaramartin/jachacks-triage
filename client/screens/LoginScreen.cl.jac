"""Landing page - big wordmark, one-liner, one-click GitHub button.

WIP: GitHub OAuth is not wired (Person 2's integrations/github.jac covers the PAT
path only). This button authenticates nothing - it just advances to the repo
picker, which then lists the one repo we actually hold a token for. PLAN.md's
"WEBSITE UI" section records this as the one deliberate placeholder.
"""

import from "@jac/runtime" { useNavigate }

def:pub LoginScreen -> JsxElement {
    nav = useNavigate();

    def handle_continue(_e: MouseEvent) {
        nav("/repos");
    }

    return
        <div
            className="min-h-screen flex flex-col items-center justify-center px-6 text-center"
        >
            <h1
                className="text-6xl sm:text-7xl font-bold tracking-[-0.04em] text-[var(--color-text)]"
            >
                Tri<span className="text-[var(--color-orange)]">age</span>
            </h1>
            <p
                className="mt-4 max-w-md text-[15px] leading-relaxed text-[var(--color-text-muted)]"
            >
                Your issue queue, ranked by structural blast radius - not by how loudly the issue is worded.
            </p>
            <button
                onClick={handle_continue}
                className="mt-12 inline-flex items-center gap-2.5 rounded-lg bg-[var(--color-green)] px-6 py-3 text-[15px] font-semibold text-[#07130d] transition-colors hover:bg-[#54e79c]"
            >
                <svg
                    width="18"
                    height="18"
                    viewBox="0 0 16 16"
                    fill="currentColor"
                    aria-hidden="true"
                >
                    <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27s1.36.09 2 .27c1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8Z"/>
                </svg>
                Log in with GitHub
            </button>
            <p className="mt-4 text-xs text-[#5b616e]">
                GitHub OAuth is a work in progress - this opens the demo repository.
            </p>
        </div>;
}
