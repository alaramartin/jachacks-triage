"""Login screen - GitHub OAuth is Person 2's Phase B build (integrations/github.jac).

Until that's wired, "Continue with GitHub" just advances to the repo picker.
This is explicitly the first thing PLAN.md says to cut if OAuth fights us -
it adds nothing to the graph story, so we never gate the demo on it.
"""

import from "@jac/runtime" { useNavigate }

def:pub LoginScreen -> JsxElement {
    nav = useNavigate();

    def handle_continue(_e: MouseEvent) {
        nav("/repos");
    }

    return
        <div
            className="min-h-screen flex flex-col items-center justify-center gap-8 px-4"
        >
            <div className="text-center">
                <h1 className="text-4xl font-bold text-zinc-100 tracking-tight">
                    Triage
                </h1>
                <p className="text-zinc-500 mt-2 max-w-sm">
                    A structural lens on your issue queue - ranked by blast radius, not by how loud the issue is worded.
                </p>
            </div>
            <button
                onClick={handle_continue}
                className="flex items-center gap-2 rounded-lg bg-zinc-100 text-zinc-900 font-semibold px-5 py-3 hover:bg-white transition-colors"
            >
                Continue with GitHub
            </button>
            <p className="text-xs text-zinc-600">
                (Mock login - Phase B wires real GitHub OAuth.)
            </p>
        </div>;
}
