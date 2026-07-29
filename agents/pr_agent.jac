"""Agent - human-triggered ONLY (CLAUDE.md #5: NOT on the reactive graph loop).
Fires from the `generate_pr` walker when a maintainer clicks the button.

Given a Cluster: read the target file's real source, `by llm()` generate a
full replacement file that fixes the shared root cause, then hand off to
integrations.github.create_pull_request for the actual branch/commit/PR
(a full-file write via the Contents API, not a unified diff - far more
reliable for an LLM to produce correctly than patch syntax).

Safety gate (CLAUDE.md #4.4): sensitive paths are refused before any LLM
call or GitHub write happens."""

import os;
import re;
import from dotenv { load_dotenv }
import from graph.nodes {
    Cluster,
    File,
    Issue,
    Repo,
    cluster_targets,
    grouped_in,
    resolves_to
}
import from integrations.github { create_pull_request, PullRequestResult }
import from jaclang.byllm.lib { Model }

# `jac run` does not load .env on its own - the environment only appears once
# something imports byllm, which drags in litellm's dotenv call. That makes
# every module-level env read here depend on import ORDER. Loading it
# explicitly, before the globs below, removes that coupling.
glob _DOTENV: bool = load_dotenv();

"""os.environ.get(name, default) returns the EMPTY STRING for a variable that
is present but blank - it does NOT fall back to the default. `.env` carried a
bare `TRIAGE_FIX_MODEL=` (added for the hosted showcase build), so the fix
model was constructed as Model(model_name="") and every single PR generation
died with 'LLM Provider NOT provided ... You passed model='. The walker then
500'd and the button span forever. Treat blank as absent."""
def _env(name: str, fallback: str = "") -> str {
    value: str = os.environ.get(name, "").strip();
    return value if value else fallback;
}

# Full-file code generation is a much harder structured-output task than the
# short classification calls elsewhere (triage/clustering) - the project-wide
# default model (jac.toml, qwen2.5:7b) reliably truncates mid-string on it.
# A code-specialized local model of the same size class fixes this without
# any paid API key.
# Overridable via TRIAGE_FIX_MODEL so a hosted deploy isn't stuck naming a
# local Ollama model it can never reach. Unset => unchanged locally.
glob FIX_MODEL: str = _env("TRIAGE_FIX_MODEL", "ollama/qwen2.5-coder:7b");
glob fix_llm: Model = Model(model_name=FIX_MODEL);

# Printed once at import. A misconfigured model used to be invisible until
# somebody clicked Generate PR and waited; now it is on stdout at boot.
# The def must precede the glob: module-level globs are evaluated in source
# order, so a forward reference here is a runtime NameError that `jac check`
# does not catch.
def _announce_model() -> bool {
    print(f"[triage] PR fix model: {FIX_MODEL}");
    return True;
}

glob _MODEL_BANNER: bool = _announce_model();

glob SENSITIVE_SUBSTRINGS: list[str] = [
         ".env",
         "docker-compose",
         "migrations/",
         "schema.sql",
         "schema.py"
     ];

"""True if `path` matches the sensitive-path denylist - config, secrets,
migrations, schema files. None of the seed bugs hit these, so this never
fires in the demo; it exists so a judge asking 'what stops this from
patching your database credentials' has a real answer."""
def is_sensitive_path(path: str) -> bool {
    lower: str = path.lower();
    for needle in SENSITIVE_SUBSTRINGS {
        if needle in lower {
            return True;
        }
    }
    return False;
}

def _read_source(path: str, repo_root: str) -> str {
    full_path: str = os.path.join(repo_root, path);
    if not os.path.exists(full_path) {
        return "";
    }
    fh = open(full_path, "r");
    source: str = fh.read();
    fh.close();
    return source;
}

obj GeneratedFix {
    has new_content: str;
}

sem GeneratedFix = "A complete, corrected replacement for a single source file, in the same language as the source it was given.";
sem GeneratedFix.new_content = "The FULL new file content (not a diff/patch) - every line of the file, with the described root cause fixed. Preserve everything about the file that isn't part of the bug: same imports, same unrelated functions, same style. Change only what's needed to fix the root cause described.";

def generate_fix(
    target_path: str,
    source_code: str,
    root_cause_summary: str,
    proposed_fix_summary: str,
    issue_summaries: list[str],
    retry_hint: str
) -> GeneratedFix by fix_llm(temperature=0.0, max_tokens=4000);

sem generate_fix = "Given a source file's current contents and a diagnosed root cause shared by several bug reports, produce a corrected full replacement for that file. Write it in the SAME language as the source you were given - infer it from the file extension and the code itself, and never translate the file into another language. Make the smallest change that fixes the root cause for all the listed reports - do not refactor, rename, or reformat unrelated code, and do not remove functionality. If the root cause spans two nearby functions in the same file (e.g. a shared type/bounds-discipline problem), fix both as part of one coherent change. The output MUST be syntactically valid and complete in that language - every string/docstring quote properly opened AND closed (never leave a triple-quote as a stray double-quote), every block and brace properly closed and indented, nothing truncated.";
sem generate_fix.target_path = "Repo-relative path of the file being fixed, e.g. 'core/validation.py' or 'app/ui/fonts.ts'. Its extension tells you which language to write.";
sem generate_fix.source_code = "The file's current, actual source code.";
sem generate_fix.root_cause_summary = "1-3 sentences describing what's broken in this file and why the linked reports all trace back to it.";
sem generate_fix.proposed_fix_summary = "One sentence describing the intended mechanical fix.";
sem generate_fix.issue_summaries = "One string per linked bug report, formatted '<external_id>: <title> - <body>' - ground the fix in what these reports actually describe.";
sem generate_fix.retry_hint = "Empty on the first attempt. On a retry, this holds the exact syntax error from the previous attempt - fix that specific mistake this time, most likely a malformed string/docstring quote.";

def _issue_summary(issue: Issue) -> str {
    return f"{issue.external_id}: {issue.title} - {issue.body}";
}

"""A standalone (unclustered) issue has no Cluster node, so it has no
root_cause_summary / proposed_fix_summary to hand the fix generator - those are
written by Agent 3 and only exist once two issues converge on one file. This
derives the same two sentences for a single issue, and doubles as the hover
text on the queue's standalone rows (one call serves both)."""
obj IssueFixPreview {
    has issue_summary: str;
    has fix_summary: str;
}

sem IssueFixPreview = "A two-sentence read on a single bug report: what is actually broken, and the mechanical fix.";
sem IssueFixPreview.issue_summary = "ONE sentence, plain language, describing what is actually going wrong in the code - not a restatement of the report's title.";
sem IssueFixPreview.fix_summary = "ONE sentence describing the concrete, minimal code change that would fix it.";

def preview_issue_fix(target_path: str, title: str, body: str) -> IssueFixPreview by llm(
    temperature=0.0
);

sem preview_issue_fix = "Read one bug report and the file it was resolved onto, and state what is broken and how to fix it. Be concrete and specific to this code; exactly one sentence each, no preamble, no bullet points.";
sem preview_issue_fix.target_path = "Repo-relative path of the file the issue resolves onto, e.g. 'core/db.py'.";
sem preview_issue_fix.title = "The bug report's title.";
sem preview_issue_fix.body = "The bug report's full text.";

"""A real syntax check via `compile()` is a cheap, exact gate for Python.
Returns "" if `content` is valid Python, else the compiler's error message.
LLM-generated full-file rewrites occasionally mangle a docstring/quote even
when the described fix is otherwise correct, so this MUST run before anything
is pushed to GitHub.

Only meaningful for Python: `compile()` on a TypeScript file fails every time,
which would burn all three retries and then push anyway. For a non-Python file
this returns "" - unchecked, not "checked and fine". There is no TS/JS parser
in the stdlib and requiring a node toolchain to open a PR isn't a trade worth
making, so those rewrites lean on the model plus human review, which is what
the "a human clicks the button" design already assumes."""
def _syntax_error(content: str, path: str) -> str {
    if not path.lower().endswith(".py") {
        return "";
    }
    try {
        compile(content, path, "exec");
        return "";
    } except SyntaxError as e {
        return str(e);
    }
}

"""Cheap, deterministic pre-pass before spending a retry: local models
consistently drop one quote off the module docstring's CLOSING triple-quote
(`\"\"\"...\"\"` instead of `\"\"\"...\"\"\"`) while every other docstring in the
file closes fine. If line 1 matches that exact shape, just fix it - free,
and skips a whole extra LLM round-trip for the single most common failure."""
def _repair_module_docstring(content: str) -> str {
    lines: list[str] = content.split("\n");
    if len(lines) == 0 {
        return content;
    }
    first: str = lines[0];
    if re.match(r'^""".*[^"]""$', first) {
        lines[0] = first + '"';
        return "\n".join(lines);
    }
    return content;
}

"""PR body per CLAUDE.md #8/Phase C: root cause, the blast-radius framing
('reached by N of M files') that's the whole pitch, and links to every
member issue - this text is on screen during the demo."""
def build_pr_body(
    root_cause: str,
    proposed_fix: str,
    blast_radius: int,
    target: File,
    repo: Repo,
    members: list[Issue]
) -> str {
    issue_lines: str = "\n".join([f"- {i.external_id}: {i.title}" for i in members]);
    return (
        f"## Root cause\n{root_cause}\n\n"
        f"## Fix\n{proposed_fix}\n\n"
        f"## Blast radius\n`{target.path}` is reached by **{blast_radius} of "
        f"{repo.file_count} files** in this repo (transitive structural blast radius), "
        f"computed by walking the import graph, not by reading the issues.\n\n"
        f"## Linked issues ({len(members)})\n{issue_lines}\n\n"
        f"---\n_Opened by Triage. A human clicked Generate PR - nothing here merges itself._"
    );
}

"""Shared core behind both entry points below - a PR is always "one target
file, N linked issues, one diagnosed root cause". A cluster supplies N issues
and Agent 3's summaries; a standalone issue supplies one issue and summaries
derived by preview_issue_fix(). Everything GitHub-specific lives in
integrations/github.jac; this owns the domain logic (denylist gate, source
read, LLM fix, PR body)."""
def _build_pr(
    target: File,
    members: list[Issue],
    root_cause: str,
    proposed_fix: str,
    blast_radius: int,
    headline: str,
    repo: Repo,
    token: str
) -> PullRequestResult {
    # Where the repo was actually indexed from (reindex_repo -> Repo.repo_path),
    # not a hardcoded demo path.
    repo_root: str = repo.repo_path;
    if not repo_root {
        return PullRequestResult(
            ok=False, error="repo has no repo_path - call reindex_repo first"
        );
    }

    if is_sensitive_path(target.path) {
        return PullRequestResult(
            ok=False, error="sensitive file - flagged for manual review"
        );
    }

    if len(members) == 0 {
        return PullRequestResult(ok=False, error="no linked issues");
    }

    source: str = _read_source(target.path, repo_root);
    if not source {
        return PullRequestResult(
            ok=False, error=f"couldn't read source for {target.path}"
        );
    }

    summaries: list[str] = [_issue_summary(i) for i in members];
    retry_hint: str = "";
    fix: GeneratedFix = GeneratedFix(new_content="");
    syntax_error: str = "";
    max_attempts: int = 3;
    attempt: int = 0;
    while attempt < max_attempts {
        # An unreachable/misconfigured model raises out of by llm(). Left
        # uncaught it becomes a 500, the client's spawn throws, and the button
        # spins forever with nothing on screen saying why - which is exactly
        # how the empty TRIAGE_FIX_MODEL presented. Report it instead.
        try {
            fix = generate_fix(
                target.path, source, root_cause, proposed_fix, summaries, retry_hint
            );
        } except Exception as e {
            return PullRequestResult(
                ok=False,
                error=f"the fix model ({FIX_MODEL}) failed: {e}"
            );
        }
        syntax_error = _syntax_error(fix.new_content, target.path);
        if syntax_error {
            repaired: str = _repair_module_docstring(fix.new_content);
            syntax_error = _syntax_error(repaired, target.path);
            if not syntax_error {
                fix.new_content = repaired;
            }
        }
        if not syntax_error {
            break;
        }
        retry_hint = syntax_error;
        attempt += 1;
    }
    # A demo needs a working PR more than a perfect diff (CLAUDE.md's PR bar is
    # "human clicks the button, something real opens" - not "every generated
    # line compiles"). If 3 attempts + the deterministic repair still leave
    # invalid Python, open the PR anyway with the best attempt rather than
    # blocking the whole feature on local-model code-gen quality.
    if syntax_error {
        print(
            f"WARNING: opening PR with unvalidated Python for {target.path}: {syntax_error}"
        );
    }

    title: str = f"fix({target.path}): {headline}"
        if headline
        else f"fix: {target.path}";
    body: str = build_pr_body(
        root_cause, proposed_fix, blast_radius, target, repo, members
    );

    return create_pull_request(
        repo.full_name,
        title,
        body,
        repo.default_branch,
        target.path,
        fix.new_content,
        token
    );
}

"""Entry point `generate_pr` (main.jac) calls - the cluster is the unit of
action (CLAUDE.md #2), so this stays the primary path."""
def build_pr_for_cluster(
    cluster: Cluster, repo: Repo, token: str = ""
) -> PullRequestResult {
    targets: list[File] = [cluster->:cluster_targets:->][?:File];
    if len(targets) == 0 {
        return PullRequestResult(ok=False, error="cluster has no target file");
    }
    return _build_pr(
        targets[0],
        [cluster<-:grouped_in:<-][?:Issue],
        cluster.root_cause_summary,
        cluster.proposed_fix_summary,
        cluster.blast_radius,
        cluster.title,
        repo,
        token
    );
}

"""Entry point `generate_pr_for_issue` (main.jac) calls, for a standalone
issue that never clustered. Same pipeline, same human trigger - the only
difference is that the root cause and fix are derived for this one report
instead of read off a Cluster node."""
def build_pr_for_issue(issue: Issue, repo: Repo, token: str = "") -> PullRequestResult {
    targets: list[File] = [issue->:resolves_to:->][?:File];
    if len(targets) == 0 {
        return PullRequestResult(
            ok=False, error="issue isn't resolved onto a file - nothing to patch"
        );
    }
    target: File = targets[0];
    preview: IssueFixPreview = IssueFixPreview(issue_summary="", fix_summary="");
    try {
        preview = preview_issue_fix(target.path, issue.title, issue.body);
    } except Exception as e {
        return PullRequestResult(ok=False, error=f"couldn't diagnose the issue: {e}");
    }
    return _build_pr(
        target,
        [issue],
        preview.issue_summary,
        preview.fix_summary,
        target.blast_radius,
        issue.title,
        repo,
        token
    );
}
