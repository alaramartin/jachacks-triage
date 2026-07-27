"""Landing page - big wordmark, one-liner, real GitHub login.

LIVE AUTH: walker/github_status decides what this screen shows (already logged
in -> straight to /repos; not logged in -> a real github.com/login/oauth link
built server-side from GITHUB_CLIENT_ID). GitHub sends the browser back here
with ?code=..., which walker/github_login trades for a token server-side. The
token itself never reaches this file - the client only ever learns a login
name and avatar.
"""

import from "@jac/runtime" { useNavigate, useLocation }
sv import from ...main { github_status, github_login, github_use_env_token }

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

def:pub LoginScreen -> JsxElement {
    has checking: bool = True,
        signing_in: bool = False,
        auth_url: str = "",
        token_available: bool = False,
        error: str = "";

    nav = useNavigate();
    location = useLocation();

    async can with entry {
        code = _query_param(location.search, "code");
        oauth_error = _query_param(location.search, "error_description");

        if oauth_error {
            error = oauth_error;
            checking = False;
            return;
        }

        if code {
            # Back from GitHub's consent screen.
            signing_in = True;
            login_result = root spawn github_login(code=code);
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

        result = root spawn github_status();
        if result.reports and len(result.reports) > 0 {
            status = result.reports[0];
            if status["authenticated"] {
                nav("/repos");
                return;
            }
            auth_url = status["authorize_url"];
            token_available = status["token_available"];
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

    button_class = "mt-12 inline-flex items-center gap-2.5 rounded-lg bg-[var(--color-green)] px-6 py-3 text-[15px] font-semibold text-[#07130d] transition-colors hover:bg-[#54e79c]";

    return
        <div
            className="min-h-screen flex flex-col items-center justify-center px-6 text-center"
        >
            <h1
                className="text-6xl sm:text-7xl font-bold tracking-[-0.04em] text-[var(--color-text)]"
            >
                Tri
                <span className="text-[var(--color-orange)]">age</span>
            </h1>
            <p
                className="mt-4 max-w-md text-[15px] leading-relaxed text-[var(--color-text-muted)]"
            >
                Your issue queue, ranked by structural blast radius - not by how loudly the issue is worded.
            </p>
            {(checking or signing_in)
            and <div className="mt-12 text-sm text-[var(--color-text-muted)]">
                {"Signing you in..."
                    if signing_in
                    else "Checking your GitHub session..."}
            </div>}
            {not checking
            and not signing_in
            and auth_url
            and <a href={auth_url} className={button_class}>
                {github_mark}Log in with GitHub
            </a>}
            {not checking
            and not signing_in
            and not auth_url
            and token_available
            and <button onClick={handle_use_token} className={button_class}>
                {github_mark}Log in with GitHub
            </button>}
            {not checking
            and not signing_in
            and not auth_url
            and not token_available
            and <button className={button_class} disabled={True}>
                {github_mark}Log in with GitHub
            </button>}
            {error
            and <p
                className="mt-6 max-w-md text-xs leading-relaxed text-[var(--color-orange)]"
            >
                {error}
            </p>}
            {not checking
            and not error
            and <p className="mt-4 text-xs text-[#5b616e]">
                Triage reads your repositories and opens pull requests only when you click.
            </p>}
        </div>;
}
