"""The ranked queue - the most important screen (CLAUDE.md §8, beat 2).

MOCK DATA: renders `mock_queue` from mock_data.cl.jac, which mirrors
mocks/queue.json exactly. No client-side sort - the order here IS the order
the (future) get_queue response returns, clusters/singletons already ranked
by urgency descending.
"""

import from "@jac/runtime" { useNavigate }
import from ..mock_data { mock_queue }
import from ..components.ClusterRow { ClusterRow }
import from ..components.SingletonRow { SingletonRow }
import from ..components.UnresolvedList { UnresolvedList }

def:pub QueueScreen -> JsxElement {
    has expanded_id: str | None = None,
        pr_result: dict | None = None;

    nav = useNavigate();

    def toggle_cluster(cluster_id: str) {
        expanded_id = None if expanded_id == cluster_id else cluster_id;
    }

    def handle_generate_pr(cluster_id: str) {
        # MOCK: shapes the response exactly like the real walker/generate_pr
        # contract (CLAUDE.md §6 - {ok, pr_number, pr_url} or {ok: false, error}),
        # so Phase C swaps this for `await generate_pr(cluster_id)` and keeps the
        # same `if pr_result["ok"] { ... } else { ... }` branch below unchanged.
        # None of the seed bugs hit the sensitive-path denylist, so the real demo
        # always takes the success branch - the error branch exists for the
        # "what stops this from patching your database credentials" answer.
        pr_result = {
            "ok": True,
            "pr_number": 7,
            "pr_url": "https://github.com/triage-demo/shipyard/pull/7"
        };
    }

    def handle_open_detail(cluster_id: str) {
        nav("/cluster/" + cluster_id);
    }

    def dismiss_banner(_e: MouseEvent) {
        pr_result = None;
    }

    clusters = mock_queue["clusters"] as list[dict];
    singletons = mock_queue["singletons"] as list[dict];
    unresolved = mock_queue["unresolved"] as list[dict];

    return
        <div className="min-h-screen px-6 py-8 max-w-4xl mx-auto">
            <div className="flex items-baseline justify-between mb-1">
                <h1 className="text-2xl font-bold text-zinc-100">
                    {mock_queue["repo"]}
                </h1>
                <span className="text-xs text-zinc-500">
                    {str(mock_queue["file_count"])} files
                </span>
            </div>
            <p className="text-sm text-zinc-500 mb-6">
                Ranked by structural blast radius, not by how the issue is worded.
            </p>
            {if pr_result is not None and pr_result["ok"] {
                <div
                    key="pr-success"
                    className="mb-4 rounded-lg border border-emerald-500/40 bg-emerald-500/10 px-4 py-3 flex items-center justify-between"
                >
                    <span className="text-sm text-zinc-200">
                        PR #
                        {str(pr_result["pr_number"])}{" "}
                        opened -{" "}
                        <a
                            href={pr_result["pr_url"]}
                            target="_blank"
                            className="underline text-emerald-300"
                        >
                            review on GitHub
                        </a>
                    </span>
                    <button
                        onClick={dismiss_banner}
                        className="text-xs text-zinc-400 hover:text-zinc-100"
                    >
                        dismiss
                    </button>
                </div>
            }}
            {if pr_result is not None and not pr_result["ok"] {
                <div
                    key="pr-error"
                    className="mb-4 rounded-lg border border-red-500/40 bg-red-500/10 px-4 py-3 flex items-center justify-between"
                >
                    <span className="text-sm text-red-200">
                        Couldn't open PR: {pr_result["error"]}
                    </span>
                    <button
                        onClick={dismiss_banner}
                        className="text-xs text-zinc-400 hover:text-zinc-100"
                    >
                        dismiss
                    </button>
                </div>
            }}
            <div className="flex flex-col gap-3">
                {for cluster in clusters {
                    <ClusterRow
                        key={cluster["id"]}
                        cluster={cluster}
                        expanded={expanded_id == cluster["id"]}
                        onToggle={lambda { toggle_cluster(cluster["id"] as str); }}
                        onGeneratePr={handle_generate_pr}
                        onOpenDetail={handle_open_detail}
                    />
                }}
                {for issue in singletons {
                    <SingletonRow key={issue["id"]} issue={issue}/>
                }}
            </div>
            <div className="mt-6">
                <UnresolvedList issues={unresolved}/>
            </div>
        </div>;
}
