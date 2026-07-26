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

def:pub QueueScreen() -> JsxElement {
    has expanded_id: str | None = None,
        pr_banner: str | None = None;

    nav = useNavigate();

    def toggle_cluster(cluster_id: str) {
        expanded_id = None if expanded_id == cluster_id else cluster_id;
    }

    def handle_generate_pr(cluster_id: str) {
        # MOCK: no generate_pr endpoint yet (Person 2, Phase C). Show a stand-in
        # result banner so the click has visible feedback during rehearsal.
        pr_banner = "Mock PR opened for " + cluster_id + " - wire to walker/generate_pr in Phase C.";
    }

    def handle_open_detail(cluster_id: str) {
        nav("/cluster/" + cluster_id);
    }

    def dismiss_banner(_e: MouseEvent) {
        pr_banner = None;
    }

    return <div className="min-h-screen px-6 py-8 max-w-4xl mx-auto">
        <div className="flex items-baseline justify-between mb-1">
            <h1 className="text-2xl font-bold text-zinc-100">{mock_queue.repo}</h1>
            <span className="text-xs text-zinc-500">{str(mock_queue.file_count)} files</span>
        </div>
        <p className="text-sm text-zinc-500 mb-6">Ranked by structural blast radius, not by how the issue is worded.</p>

        {if pr_banner is not None {
            <div className="mb-4 rounded-lg border border-[var(--color-accent)]/40 bg-[var(--color-accent-soft)] px-4 py-3 flex items-center justify-between">
                <span className="text-sm text-zinc-200">{pr_banner}</span>
                <button onClick={dismiss_banner} className="text-xs text-zinc-400 hover:text-zinc-100">dismiss</button>
            </div>
        }}

        <div className="flex flex-col gap-3">
            {for cluster in mock_queue.clusters {
                <ClusterRow
                    key={cluster.id}
                    cluster={cluster}
                    expanded={expanded_id == cluster.id}
                    onToggle={lambda -> None { toggle_cluster(cluster.id); }}
                    onGeneratePr={handle_generate_pr}
                    onOpenDetail={handle_open_detail}
                />
            }}
            {for issue in mock_queue.singletons {
                <SingletonRow key={issue.id} issue={issue} />
            }}
        </div>

        <div className="mt-6">
            <UnresolvedList issues={mock_queue.unresolved} />
        </div>
    </div>;
}
