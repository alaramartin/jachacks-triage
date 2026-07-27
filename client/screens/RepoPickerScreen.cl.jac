"""Repo picker - "your projects", populated from the real GitHub account.

LIVE DATA: walker/list_my_repos returns every repo the logged-in account owns
or collaborates on, straight from the GitHub API - nothing on this screen is
fabricated. Picking one runs walker/select_repo (clone + AST index) then
walker/ingest_from_github (the Agent 1->2->3->4 cascade over its real open
issues), reporting progress between the two because indexing is fast and
triage is not. The whole queue gets triaged - no cap - because collapsing a
hundred-issue queue into a handful of clusters is the entire point.

"Choose another repo" takes any github.com link, so Triage can be pointed at a
repo the user has never touched - the same two walkers, no special path.
"""

import from "@jac/runtime" { useNavigate }
sv import from ...main {
    github_status,
    github_logout,
    list_my_repos,
    select_repo,
    ingest_from_github
}

# Hover text on everything showcase mode disables (see the `showcase` flag,
# reported by walker/github_status off TRIAGE_SHOWCASE on the deploy).
glob SHOWCASE_TOOLTIP: str = "We were too broke to afford an API key - triage runs on a model on our own "
     "laptop, so this is disabled on the hosted build. Watch the demo video.";

# The "paste any repo link" box is deliberately NOT rendered. The server side
# of it is untouched - select_repo/parse_repo_full_name still accept an
# arbitrary repo, and handle_custom_submit below still works - so putting the
# control back is a JSX-only change.
def:pub RepoPickerScreen -> JsxElement {
    has repos: list = [],
        loading: bool = True,
        error: str = "",
        login: str = "",
        avatar_url: str = "",
        custom_url: str = "",
        busy_repo: str = "",
        progress: str = "",
        showcase: bool = False,
        demo_video_url: str = "";

    nav = useNavigate();

    async can with entry {
        status_result = root spawn github_status();
        if status_result.reports and len(status_result.reports) > 0 {
            status = status_result.reports[0];
            if not status["authenticated"] {
                nav("/");
                return;
            }
            login = status["login"];
            avatar_url = status["avatar_url"];
            # Hosted showcase build (TRIAGE_SHOWCASE=1 on the deploy): the repo
            # list below is real and live, but everything downstream of it needs
            # a local model the pod doesn't have. Grey it out rather than let a
            # judge click into a walker that will only ever return an error.
            showcase = status["showcase"];
            demo_video_url = status["demo_video_url"];
        }

        result = root spawn list_my_repos();
        if result.reports and len(result.reports) > 0 {
            resp = result.reports[0];
            if resp["ok"] {
                repos = resp["repos"];
            } else {
                error = resp["error"];
            }
        } else {
            error = "Couldn't reach the server.";
        }
        loading = False;
    }

    # Both entry points - a card click and a pasted link - run the same two
    # walkers, so an unowned repo behaves exactly like one of your own.
    # Ingestion runs detached (note: NOT awaited) - it is three LLM calls per
    # issue, so awaiting it here is what made a click sit on this screen for
    # minutes with nothing to show. The queue opens immediately instead and
    # fills in as issues land.
    async def start_ingest(full_name: str) -> None {
        root spawn ingest_from_github(full_name=full_name, limit=0);
    }

    async def open_repo(repo_url: str) -> None {
        busy_repo = repo_url;
        error = "";
        progress = "Cloning and indexing the code graph...";

        selected = root spawn select_repo(repo_url=repo_url);
        if not (selected.reports and len(selected.reports) > 0) {
            error = "Couldn't reach the server.";
            busy_repo = "";
            progress = "";
            return;
        }
        picked = selected.reports[0];
        if not picked["ok"] {
            error = picked["error"];
            busy_repo = "";
            progress = "";
            return;
        }

        full_name = picked["full_name"];
        remaining = picked["open_issues"] - picked["issues_in_graph"];
        if remaining > 0 {
            start_ingest(full_name);
            nav(f"/queue?repo={full_name}&ingesting=1");
        } else {
            nav(f"/queue?repo={full_name}");
        }
    }

    async def handle_logout(_e: MouseEvent) -> None {
        root spawn github_logout();
        nav("/");
    }

    async def handle_custom_submit(e: FormEvent) -> None {
        e.preventDefault();
        if custom_url.strip() {
            await open_repo(custom_url.strip());
        }
    }

    return
        <div className="min-h-screen px-6 sm:px-12 py-12 max-w-5xl mx-auto">
            <div className="flex items-baseline justify-between gap-3">
                <div className="flex items-baseline gap-3">
                    <h1
                        className="text-xl font-semibold tracking-tight text-[var(--color-text)]"
                    >
                        Your projects
                    </h1>
                    <span className="text-xs text-[var(--color-text-muted)]">
                        repositories you own or collaborate on
                    </span>
                </div>
                {login
                and <div
                    className="flex items-center gap-2 text-xs text-[var(--color-text-muted)]"
                >
                    {avatar_url
                    and <img
                        src={avatar_url}
                        alt=""
                        width={20}
                        height={20}
                        className="h-5 w-5 shrink-0 rounded-full"
                    />}
                    <span className="font-mono">{login}</span>
                    <button
                        onClick={handle_logout}
                        className="ml-1 underline underline-offset-2 hover:text-[var(--color-orange)]"
                    >
                        log out
                    </button>
                </div>}
            </div>
            {busy_repo
            and <div
                className="mt-6 rounded-lg border border-[var(--color-border)] bg-[var(--color-surface)] px-4 py-3"
            >
                <div className="font-mono text-sm text-[var(--color-green)]">
                    {busy_repo}
                </div>
                <div className="mt-1 text-sm text-[var(--color-text-muted)]">
                    {progress}
                </div>
            </div>}
            {error
            and <p className="mt-6 text-sm text-[var(--color-orange)]">{error}</p>}
            {showcase
            and <div
                className="mt-6 rounded-lg border border-[var(--color-border)] bg-[var(--color-surface)] px-4 py-3 text-sm text-[var(--color-text-muted)]"
            >
                We were too broke to afford an API key, so triage runs on a model on our own laptop - your repos below are real, but opening one is disabled here.{" "}
                <a
                    href={demo_video_url or "#"}
                    target="_blank"
                    rel="noreferrer"
                    className="underline underline-offset-2 text-[var(--color-orange)]"
                >
                    Watch the demo instead
                </a>
                .
            </div>}
            {loading
            and <p className="mt-8 text-sm text-[var(--color-text-muted)]">
                Loading your repositories...
            </p>}
            {not loading
            and len(repos) == 0
            and not error
            and <p className="mt-8 text-sm text-[var(--color-text-muted)]">
                No repositories came back from GitHub for this account. Paste a repo link above to triage any public repo.
            </p>}
            <div className="mt-8 grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
                {[
                    <button
                        key={r["full_name"]}
                        onClick={lambda (_e: MouseEvent) -> None { open_repo(
                            r["full_name"] as str
                        ); }}
                        disabled={bool(busy_repo) or showcase}
                        title={SHOWCASE_TOOLTIP if showcase else ""}
                        className="group text-left rounded-xl border border-[var(--color-border)] bg-[var(--color-surface)] p-5 transition-colors hover:border-[var(--color-orange)] hover:bg-[var(--color-surface-raised)] disabled:opacity-40"
                    >
                        <div className="flex items-start justify-between gap-3">
                            <div className="min-w-0">
                                <div
                                    className="text-xs font-mono text-[var(--color-text-muted)] truncate"
                                >
                                    {r["full_name"].split("/")[0]}
                                </div>
                                <div
                                    className="mt-0.5 text-base font-semibold text-[var(--color-text)] truncate"
                                >
                                    {r["full_name"].split("/")[1]}
                                </div>
                            </div>
                            <span
                                className="shrink-0 text-[var(--color-text-muted)] transition-colors group-hover:text-[var(--color-orange)]"
                            >
                                →
                            </span>
                        </div>
                        <div
                            className="mt-2 h-8 text-xs leading-4 text-[var(--color-text-muted)] overflow-hidden"
                        >
                            {r["description"]}
                        </div>
                        <div
                            className="mt-4 flex items-center gap-3 text-xs text-[var(--color-text-muted)]"
                        >
                            <span className="inline-flex items-center gap-1.5">
                                <span
                                    className={"inline-block h-1.5 w-1.5 rounded-full " + (
                                        "bg-[var(--color-green)]"
                                            if r["indexed"]
                                            else "bg-[#5b616e]"
                                    )}
                                />
                                {str(r["open_issues"]) + " issues + PRs"}
                            </span>
                            {r["language"] and <span>{r["language"]}</span>}
                            {r["private"] and <span>private</span>}
                        </div>
                    </button> for r in repos
                ]}
            </div>
        </div>;
}
