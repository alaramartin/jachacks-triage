"""Landing page - a scroll-driven slideshow built for the demo video.

The first viewport is the original landing (wordmark, one-liner, real GitHub
login). Everything below it is a snap-scrolled deck: the Jac stat, the problem,
the solution, the pipeline diagram, and the demo video. As you leave the hero,
the wordmark and the login button are the only two things that survive - they
travel to the top-left / top-right and shrink into a header.

LIVE AUTH is unchanged: walker/github_status decides what the button does, and
GitHub sends the browser back here with ?code=..., which walker/github_login
trades for a token server-side. The token never reaches this file.

ONE BEHAVIOR CHANGE vs. the old screen: an already-authenticated visitor is no
longer bounced straight to /repos. That redirect made the deck unreachable for
anyone logged in (i.e. us, while recording). The button becomes
"Continue as <login>" instead, which is the same one click.
"""

import from "@jac/runtime" { useNavigate, useLocation }
sv import from ...main { github_status, github_login, github_use_env_token }

# Percentage of the repo that is Jac, as measured off GitHub's language bar.
# This is a static fact about the codebase, not queue data - it does NOT come
# from a walker. Update it by hand if the language bar moves.
glob JAC_PERCENT: str = "98.8%";

# Pulls one query-string value out of a "?a=1&b=2" search string. OAuth codes
# are alphanumeric, so the only decoding worth doing is `+` back to a space
# for GitHub's human-readable error_description.
def _query_param(search: str, key: str) -> str {
    raw = search[1:] if search.startswith("?") else search;
    for part in raw.split("&") {
        if part.startswith(key + "=") {
            return part[len(key) + 1:].replace("+", " ");
        }
    }
    return "";
}

def _clamp(v: float, lo: float, hi: float) -> float {
    if v < lo {
        return lo;
    }
    if v > hi {
        return hi;
    }
    return v;
}

def _lerp(a: float, b: float, t: float) -> float {
    return a + (b - a) * t;
}

# One axis of the hero->header morph, as a CSS calc(). Mixing a viewport unit,
# a pixel offset and a SELF-relative percentage in one expression is what lets
# the wordmark center itself at rest (`50vw - 50%`) without anyone measuring
# how wide it is, then travel to a fixed pixel inset (`0vw + 32px + 0%`).
def _axis(unit: str, vp: float, px: float, pct: float) -> str {
    return "calc(" + str(vp) + unit + " + " + str(px) + "px + " + str(pct) + "%)";
}

# Deck sections drift and fade around their resting position. `index` is the
# section's slide number, so `t` is 0 exactly when that slide is snapped.
def _parallax(scroll: float, vh: float, index: int) -> dict {
    t = (scroll - (index * 1.0) * vh) / vh;
    dist = t if t >= 0.0 else -t;
    return {
        "transform": "translateY(" + str(-t * 80.0) + "px)",
        "opacity": _clamp(1.0 - dist * 1.6, 0.0, 1.0)
    };
}

# Turn a share link into something an <iframe> will actually play. Anything we
# don't recognize is passed through untouched.
def _embed_url(url: str) -> str {
    if "youtube.com/watch?v=" in url {
        return "https://www.youtube.com/embed/"
            + url.split("watch?v=")[1].split("&")[0];
    }
    if "youtu.be/" in url {
        return "https://www.youtube.com/embed/"
            + url.split("youtu.be/")[1].split("?")[0];
    }
    if "drive.google.com" in url and "/view" in url {
        return url.split("/view")[0] + "/preview";
    }
    if "loom.com/share/" in url {
        return url.replace("/share/", "/embed/");
    }
    return url;
}

# py-20 keeps deck content clear of the pinned header; overflow-y-auto is the
# small-screen escape hatch - on desktop nothing overflows, so it never engages
# and never fights the outer snap container.
glob SECTION_CLS: str = "relative z-10 h-screen snap-start flex flex-col justify-center overflow-y-auto px-6 sm:px-12 py-20";
glob DECK_INNER_CLS: str = "w-full max-w-5xl mx-auto";
glob EYEBROW_CLS: str = "text-xs font-mono uppercase tracking-[0.12em] text-[var(--color-green)]";

def:pub LoginScreen -> JsxElement {
    has checking: bool = True,
        signing_in: bool = False,
        auth_url: str = "",
        token_available: bool = False,
        authed: bool = False,
        login: str = "",
        demo_video_url: str = "",
        error: str = "",
        scroll: float = 0.0,
        vh: float = 900.0;

    nav = useNavigate();
    location = useLocation();

    async can with entry {
        code = _query_param(location.search, "code");
        oauth_error = _query_param(location.search, "error_description");
        # The OAuth redirect_uri is whatever origin the browser is actually on,
        # NOT a build-time TRIAGE_APP_URL. A hosted deploy can be handed a new
        # subdomain on every redeploy, and pinning the callback to an env var
        # is circular there: fixing the var requires a redeploy, which changes
        # the URL again. Reading it off `window` converges immediately, and it
        # is identical to APP_URL when running on localhost.
        origin = window.location.origin;

        if oauth_error {
            error = oauth_error;
            checking = False;
            return;
        }

        if code {
            # Back from GitHub's consent screen.
            signing_in = True;
            login_result = root spawn github_login(code=code, redirect_uri=origin);
            if login_result.reports and len(login_result.reports) > 0 {
                resp = login_result.reports[0];
                if resp["ok"] {
                    nav("/repos");
                    return;
                }
                error = resp["error"];
            } else {
                error = "Couldn't reach the server to finish signing in.";
            }
            signing_in = False;
            checking = False;
            return;
        }

        result = root spawn github_status(redirect_uri=origin);
        if result.reports and len(result.reports) > 0 {
            status = result.reports[0];
            authed = status["authenticated"];
            login = status["login"];
            auth_url = status["authorize_url"];
            token_available = status["token_available"];
            demo_video_url = status["demo_video_url"];
        } else {
            error = "Couldn't reach the server.";
        }
        checking = False;
    }

    # What the button does when no OAuth app is registered (no
    # GITHUB_CLIENT_ID/SECRET in .env) but a GITHUB_TOKEN is: sign in as that
    # token's GitHub account. Same real account, same real repos - the only
    # thing missing is the consent screen. Keeps the button from ever being a
    # dead control.
    async def handle_use_token(_e: MouseEvent) -> None {
        result = root spawn github_use_env_token();
        if result.reports and len(result.reports) > 0 and result.reports[0]["ok"] {
            nav("/repos");
        } else {
            error = "The configured GITHUB_TOKEN isn't usable.";
        }
    }

    def handle_continue(_e: MouseEvent) -> None {
        nav("/repos");
    }

    # Every position on this page is derived from the scroll container itself,
    # so nothing needs `window` or a resize listener.
    def handle_scroll(e: ScrollEvent) -> None {
        el = e.currentTarget;
        if el.clientHeight > 0.0 {
            vh = el.clientHeight;
        }
        scroll = el.scrollTop;
    }

    # 0.0 while the hero is snapped, 1.0 once the first slide is fully in view.
    p = _clamp(scroll / vh, 0.0, 1.0);
    slide = scroll / vh;
    hero_fade = _clamp(1.0 - p * 2.2, 0.0, 1.0);

    # Wordmark: dead center of the hero -> pinned top-left, a third the size.
    title_transform = "translate("
        + _axis("vw", _lerp(50.0, 0.0, p), _lerp(0.0, 32.0, p), _lerp(-50.0, 0.0, p))
        + ", "
        + _axis("vh", _lerp(32.0, 0.0, p), _lerp(0.0, 24.0, p), _lerp(-50.0, 0.0, p))
        + ") scale("
        + str(_lerp(1.0, 0.34, p))
        + ")";
    # Login button: same motion mirrored to the right edge. It scales about its
    # own right edge so the gap to the viewport edge stays put.
    button_transform = "translate("
        + _axis("vw", _lerp(50.0, 100.0, p), _lerp(0.0, -28.0, p), _lerp(-50.0, -100.0, p))
        + ", "
        + _axis("vh", _lerp(32.0, 0.0, p), _lerp(132.0, 22.0, p), 0.0)
        + ") scale("
        + str(_lerp(1.0, 0.82, p))
        + ")";

    github_mark = <svg
        width="18"
        height="18"
        viewBox="0 0 16 16"
        fill="currentColor"
        aria-hidden="true"
    >
        <path
            d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27s1.36.09 2 .27c1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8Z"
        />
    </svg>;

    button_class = "inline-flex items-center gap-2.5 rounded-lg bg-[var(--color-green)] px-6 py-3 text-[15px] font-semibold text-[#07130d] transition-colors hover:bg-[#54e79c]";

    jac_facts = [
        {
            "title": "Graph Data Model",
            "body": "Nodes (File, Issue, Cluster) connected by typed edges (imports, resolves_to)."
        },
        {
            "title": "Walker-Based Agents",
            "body": "Jac walkers calculate transitive blast radius using object-spatial graph traversals."
        },
        {
            "title": "Decoupled Event Orchestration",
            "body": "The graph organizes the agents; as soon as one agent makes an update, the other can automatically complete its task."
        }
    ];

    problems = [
        "Github repositories have dozens of open issues and PRs.",
        "A one-line code change can silently break multiple downstream modules.",
        "Modern LLMs lack context and, when repos get big, developers can't copy and paste 100,000 lines of code.",
        "Critical production bugs get buried under lower-priority errors, leading to delays."
    ];

    solutions = [
        {
            "title": "Ranked.",
            "body": "A score based on semantic meaning and blast radius determines which issues are most critical."
        },
        {
            "title": "Clustered.",
            "body": "Issues that point to the same code node are clustered, so 20 noisy issues turn into 1 concise read."
        },
        {
            "title": "Drafted.",
            "body": "Click one button and a PR is automatically drafted."
        },
        {
            "title": "Updated.",
            "body": "A live graph that scales like a database (not like the static snapshot of code in traditional LLMs)."
        }
    ];

    steps = [
        {
            "title": "Issues come in",
            "body": "The whole open queue, worded every which way",
            "width": "340px"
        },
        {
            "title": "Each one resolves onto real code",
            "body": "Traceback, file path, or LLM inference",
            "width": "480px"
        },
        {
            "title": "Duplicates merge automatically",
            "body": "5 reports collapse into 1 cluster",
            "width": "424px"
        },
        {
            "title": "Ranked by blast radius, not tone",
            "body": "14 dependent files outrank 5 loud reports",
            "width": "462px"
        }
    ];

    octagon_style = {
        "clipPath": "polygon(30% 0%, 70% 0%, 100% 30%, 100% 70%, 70% 100%, 30% 100%, 0% 70%, 0% 30%)"
    };

    return
        <div className="relative">
            <div
                className="pointer-events-none fixed inset-0 z-0"
                style={{
                    "backgroundImage": "radial-gradient(760px 520px at 50% "
                        + str(30.0 + 18.0 * Math.sin(slide * 1.1))
                        + "%, rgba(255,139,61,0.13), transparent 68%), radial-gradient(620px 460px at "
                        + str(72.0 + 16.0 * Math.cos(slide * 0.9))
                        + "% 78%, rgba(63,214,140,0.09), transparent 70%)"
                }}
            />
            <h1
                className="fixed left-0 top-0 z-50 w-max font-bold tracking-[-0.04em] text-[var(--color-text)]"
                style={{
                    "transform": title_transform,
                    "transformOrigin": "left top",
                    "fontSize": "clamp(3.25rem, 8vw, 4.5rem)",
                    "lineHeight": "1"
                }}
            >
                Tri
                <span className="text-[var(--color-orange)]">age</span>
            </h1>
            <div
                className="fixed left-0 top-0 z-50 w-max"
                style={{
                    "transform": button_transform, "transformOrigin": "right top"
                }}
            >
                {(checking or signing_in)
                and <div className="px-2 py-3 text-sm text-[var(--color-text-muted)]">
                    {"Signing you in..."
                        if signing_in
                        else "Checking your GitHub session..."}
                </div>}
                {not checking
                and not signing_in
                and authed
                and <button onClick={handle_continue} className={button_class}>
                    {github_mark}
                    {"Continue as " + login if login else "Continue"}
                </button>}
                {not checking
                and not signing_in
                and not authed
                and auth_url
                and <a href={auth_url} className={button_class}>
                    {github_mark}Log in with GitHub
                </a>}
                {not checking
                and not signing_in
                and not authed
                and not auth_url
                and token_available
                and <button onClick={handle_use_token} className={button_class}>
                    {github_mark}Log in with GitHub
                </button>}
                {not checking
                and not signing_in
                and not authed
                and not auth_url
                and not token_available
                and <button className={button_class} disabled={True}>
                    {github_mark}Log in with GitHub
                </button>}
            </div>
            <div
                className="h-screen overflow-y-auto overflow-x-hidden snap-y snap-mandatory"
                onScroll={handle_scroll}
            >
                <section className="relative z-10 h-screen snap-start">
                    <p
                        className="absolute left-1/2 w-full max-w-md -translate-x-1/2 px-6 text-center text-[15px] leading-relaxed text-[var(--color-text-muted)]"
                        style={{"top": "calc(32vh + 54px)", "opacity": hero_fade}}
                    >
                        Your issue queue, ranked by structural blast radius - not by how loudly the issue is worded.
                    </p>
                    <div
                        className="absolute left-1/2 w-full max-w-md -translate-x-1/2 px-6 text-center"
                        style={{"top": "calc(32vh + 202px)", "opacity": hero_fade}}
                    >
                        {error
                        and <p
                            className="text-xs leading-relaxed text-[var(--color-orange)]"
                        >
                            {error}
                        </p>}
                        {not checking
                        and not error
                        and <p className="text-xs text-[#5b616e]">
                            Triage reads your repositories and opens pull requests only when you click.
                        </p>}
                    </div>
                    <div
                        className="absolute bottom-10 left-1/2 flex -translate-x-1/2 flex-col items-center gap-2"
                        style={{"opacity": hero_fade}}
                    >
                        <span
                            className="text-[11px] font-mono uppercase tracking-[0.12em] text-[var(--color-text-muted)]"
                        >
                            scroll to see more
                        </span>
                        <svg
                            width="22"
                            height="22"
                            viewBox="0 0 24 24"
                            fill="none"
                            stroke="var(--color-orange)"
                            strokeWidth="2"
                            strokeLinecap="round"
                            strokeLinejoin="round"
                            className="animate-bounce"
                            aria-hidden="true"
                        >
                            <path d="M12 5v14M19 12l-7 7-7-7"/>
                        </svg>
                    </div>
                </section>
                <section className={SECTION_CLS}>
                    <div className={DECK_INNER_CLS} style={_parallax(scroll, vh, 1)}>
                        <div
                            className="font-bold tracking-[-0.04em] text-[var(--color-orange)]"
                            style={{
                                "fontSize": "clamp(4rem, 15vw, 11rem)", "lineHeight": "0.9"
                            }}
                        >
                            {JAC_PERCENT}
                        </div>
                        <div
                            className="mt-3 font-semibold tracking-tight text-[var(--color-text)]"
                            style={{"fontSize": "clamp(1.5rem, 4vw, 2.5rem)"}}
                        >
                            built with jac.
                        </div>
                        <div className="mt-10 grid grid-cols-1 md:grid-cols-3 gap-5">
                            {[
                                <div
                                    key={f["title"]}
                                    className="rounded-xl border border-[var(--color-border)] bg-[var(--color-surface)] p-5"
                                >
                                    <div
                                        className="text-[13px] font-semibold text-[var(--color-green)]"
                                    >
                                        {f["title"]}
                                    </div>
                                    <p
                                        className="mt-2 text-[13px] leading-relaxed text-[var(--color-text-muted)]"
                                    >
                                        {f["body"]}
                                    </p>
                                </div> for f in jac_facts
                            ]}
                        </div>
                    </div>
                </section>
                <section className={SECTION_CLS}>
                    <div className={DECK_INNER_CLS} style={_parallax(scroll, vh, 2)}>
                        <div className={EYEBROW_CLS}>01</div>
                        <h2
                            className="mt-3 font-bold tracking-[-0.03em] text-[var(--color-text)]"
                            style={{"fontSize": "clamp(2.25rem, 7vw, 4.5rem)", "lineHeight": "1"}}
                        >
                            The Problem
                        </h2>
                        <ul className="mt-10 flex flex-col gap-4 max-w-3xl">
                            {[
                                <li key={line} className="flex items-start gap-4">
                                    <span
                                        className="mt-2.5 h-1.5 w-1.5 shrink-0 rounded-full bg-[var(--color-orange)]"
                                    />
                                    <span
                                        className="text-[var(--color-text-muted)]"
                                        style={{
                                            "fontSize": "clamp(0.95rem, 1.6vw, 1.15rem)",
                                            "lineHeight": "1.6"
                                        }}
                                    >
                                        {line}
                                    </span>
                                </li> for line in problems
                            ]}
                        </ul>
                    </div>
                </section>
                <section className={SECTION_CLS}>
                    <div className={DECK_INNER_CLS} style={_parallax(scroll, vh, 3)}>
                        <div className={EYEBROW_CLS}>02 · our solution</div>
                        <h2
                            className="mt-3 font-bold tracking-[-0.03em] text-[var(--color-orange)]"
                            style={{"fontSize": "clamp(2.5rem, 8vw, 5rem)", "lineHeight": "1"}}
                        >
                            TRIAGE
                        </h2>
                        <div className="mt-9 grid grid-cols-1 sm:grid-cols-2 gap-5">
                            {[
                                <div
                                    key={s["title"]}
                                    className="rounded-xl border border-[var(--color-border)] bg-[var(--color-surface)] p-5"
                                >
                                    <div
                                        className="text-lg font-semibold text-[var(--color-text)]"
                                    >
                                        {s["title"]}
                                    </div>
                                    <p
                                        className="mt-2 text-[13px] leading-relaxed text-[var(--color-text-muted)]"
                                    >
                                        {s["body"]}
                                    </p>
                                </div> for s in solutions
                            ]}
                        </div>
                        <p
                            className="mt-8 text-lg font-medium text-[var(--color-green)]"
                        >
                            Stop reading every issue. Start fixing the right ones.
                        </p>
                    </div>
                </section>
                <section className={SECTION_CLS}>
                    <div className={DECK_INNER_CLS} style={_parallax(scroll, vh, 4)}>
                        <div className={EYEBROW_CLS}>03 · how it works</div>
                        <h2
                            className="mt-3 font-bold tracking-[-0.03em] text-[var(--color-text)]"
                            style={{"fontSize": "clamp(1.75rem, 4.5vw, 3rem)", "lineHeight": "1"}}
                        >
                            One graph, four agents, no direct calls.
                        </h2>
                        <div
                            className="mt-9 flex flex-col lg:flex-row lg:items-center gap-10"
                        >
                            <div
                                className="relative w-full min-w-0 lg:w-[528px] shrink-0 pl-8"
                            >
                                <div
                                    className="absolute left-1 top-4 bottom-4 w-px bg-[var(--color-orange)]/40"
                                />
                                <div
                                    className="absolute left-1 top-4 h-2 w-2 -translate-x-1/2 rounded-full bg-[var(--color-orange)]"
                                />
                                <div
                                    className="absolute left-1 bottom-4 h-2 w-2 -translate-x-1/2 rounded-full bg-[var(--color-orange)]"
                                />
                                <div className="flex flex-col gap-3">
                                    {[
                                        <div
                                            key={st["title"]}
                                            className="rounded-2xl border border-[var(--color-border)] bg-[var(--color-surface)] px-5 py-3"
                                            style={{
                                                "width": st["width"], "maxWidth": "100%"
                                            }}
                                        >
                                            <div
                                                className="text-[14px] font-semibold text-[var(--color-text)]"
                                            >
                                                {st["title"]}
                                            </div>
                                            <div
                                                className="mt-0.5 text-[12px] text-[var(--color-text-muted)]"
                                            >
                                                {st["body"]}
                                            </div>
                                        </div> for st in steps
                                    ]}
                                </div>
                            </div>
                            <div
                                className="flex flex-row flex-wrap justify-center lg:flex-col lg:flex-nowrap items-center gap-6 shrink-0"
                            >
                                <div className="relative">
                                    <div
                                        className="hidden lg:block absolute top-1/2 right-full w-24 border-t border-dashed border-[var(--color-green)]/50"
                                    />
                                    <div
                                        className="rounded-full border border-[var(--color-green)]/40 bg-[var(--color-green-soft)] px-8 py-7 text-center w-56"
                                    >
                                        <div
                                            className="text-lg font-semibold text-[var(--color-green)]"
                                        >
                                            Cluster
                                        </div>
                                        <div
                                            className="mt-1 text-[12px] leading-snug text-[var(--color-text-muted)]"
                                        >
                                            Groups duplicate issues into one cluster.
                                        </div>
                                    </div>
                                </div>
                                <div
                                    className="flex h-40 w-40 shrink-0 items-center justify-center bg-[var(--color-orange)] px-6 text-center text-[12px] font-medium leading-4 text-[#1a0d03]"
                                    style={octagon_style}
                                >
                                    Anything else: ranked and flagged, never auto-merged.
                                </div>
                            </div>
                        </div>
                    </div>
                </section>
                <section className={SECTION_CLS}>
                    <div
                        className="w-full max-w-3xl mx-auto"
                        style={_parallax(scroll, vh, 5)}
                    >
                        <h2
                            className="text-center font-bold tracking-[-0.03em] text-[var(--color-text)]"
                            style={{"fontSize": "clamp(1.75rem, 4.5vw, 2.75rem)"}}
                        >
                            Watch our demo video
                        </h2>
                        {demo_video_url
                        and <div
                            className="mt-8 aspect-video w-full overflow-hidden rounded-2xl border border-[var(--color-border)] bg-[var(--color-surface)]"
                        >
                            <iframe
                                src={_embed_url(demo_video_url)}
                                title="Triage demo"
                                className="h-full w-full"
                                allow="accelerometer; autoplay; clipboard-write; encrypted-media; picture-in-picture"
                                allowFullScreen={True}
                            />
                        </div>}
                        {not demo_video_url
                        and <div
                            className="mt-8 flex aspect-video w-full flex-col items-center justify-center gap-2 rounded-2xl border border-dashed border-[var(--color-border-strong)] bg-[var(--color-surface)] px-8 text-center"
                        >
                            <p className="text-sm text-[var(--color-text-muted)]">
                                No demo video is configured on this server yet.
                            </p>
                            <p className="text-xs font-mono text-[#5b616e]">
                                set TRIAGE_DEMO_VIDEO_URL in .env
                            </p>
                        </div>}
                        <p
                            className="mt-6 text-center text-[13px] text-[var(--color-text-muted)]"
                        >
                            Four agents, one graph, and they never call each other. The graph is the coordination medium.
                        </p>
                    </div>
                </section>
            </div>
        </div>;
}
