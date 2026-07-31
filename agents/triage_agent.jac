"""Agent 1 (Triage): resolve a raw issue onto a code node and assess it.

Explicit signals (traceback / bare path / backticked symbol) are tried first.
Only when none match do we fall back to an LLM guess, and only accept that
guess above the confidence threshold (CLAUDE.md SS5). The walker that owns
graph writes (ingest_issue, Phase B) calls resolve_issue() and decides
whether to create a `resolves_to` edge or park the issue as Unresolved.
"""
import re;
import os;

obj Resolution {
    has path: str | None = None;
    has confidence: float = 0.0;
    has method: str = "none";
}

# Every issue in a batch resolves against the SAME repo checkout, so reading
# the same files off disk once per issue is pure waste - on a 1000-file repo
# that was ~1000 reads per issue just to build the summary map. Keyed by
# absolute path; a repo is re-cloned into a fresh directory, so staleness is
# only a concern if someone edits the checkout under a running server.
glob _SOURCE_CACHE: dict[str, str] = {};

def _read_cached(full_path: str) -> str {
    if full_path in _SOURCE_CACHE {
        return _SOURCE_CACHE[full_path];
    }
    if not os.path.exists(full_path) {
        _SOURCE_CACHE[full_path] = "";
        return "";
    }
    fh = open(full_path, "r", encoding="utf-8", errors="replace");
    source: str = fh.read();
    fh.close();
    _SOURCE_CACHE[full_path] = source;
    return source;
}

"""Static lookup: does file `p` (read from repo_root/p) define a top-level or
method-level `def {symbol}(`? Best-effort - a missing/unreadable file just
means no match, never an error. This is real source inspection (like
ast_parser.jac's import scan), not a per-repo guess table."""
def _defines_symbol(symbol: str, p: str, repo_root: str) -> bool {
    return f"def {symbol}(" in _read_cached(os.path.join(repo_root, p));
}

# symbol -> the repo-relative files that define it, built once per checkout.
# This is the signal that makes resolution work on a repo nobody hardcoded:
# a report saying "send_file blows up on BytesIO" names a real symbol, and
# knowing which file DEFINES that symbol beats every filename heuristic.
glob _DEF_INDEX: dict[str, dict[str, list[str]]] = {};

# What a top-level declaration looks like, per language. `(?m)` is inline
# rather than a `flags=` argument - Jac's typeshed has no 3-arg re.findall
# overload.
glob _PY_DECL: list[str] = [
         r"(?m)^[ \t]*(?:async[ \t]+)?(?:def|class)[ \t]+([A-Za-z_][A-Za-z0-9_]*)"
     ];
glob _JS_DECL: list[str] = [
         r"(?m)^[ \t]*(?:export[ \t]+)?(?:default[ \t]+)?(?:async[ \t]+)?function[ \t*]+([A-Za-z_$][A-Za-z0-9_$]*)",
         r"(?m)^[ \t]*(?:export[ \t]+)?(?:default[ \t]+)?(?:abstract[ \t]+)?class[ \t]+([A-Za-z_$][A-Za-z0-9_$]*)",
         # `const Foo = () => {}` is how most of a modern TS codebase declares
         # its components and helpers - without this the index misses them all.
         r"(?m)^[ \t]*(?:export[ \t]+)?(?:const|let|var)[ \t]+([A-Za-z_$][A-Za-z0-9_$]*)",
         r"(?m)^[ \t]*(?:export[ \t]+)?(?:interface|type|enum)[ \t]+([A-Za-z_$][A-Za-z0-9_$]*)"
     ];
glob _JS_SUFFIXES: list[str] = [
         ".ts",
         ".tsx",
         ".mts",
         ".cts",
         ".js",
         ".jsx",
         ".mjs",
         ".cjs"
     ];

"""A file's bare name with its source extension removed - `core/validation.py`
-> `validation`, `app/ui/fonts.ts` -> `fonts`. What a report means when it
mentions a module by name."""
def _stem(path: str) -> str {
    name: str = path.split("/")[-1];
    for ext in [".py"] + _JS_SUFFIXES {
        if name.lower().endswith(ext) {
            return name[:-len(ext)];
        }
    }
    return name;
}

def _decl_patterns(path: str) -> list[str] {
    lowered: str = path.lower();
    for ext in _JS_SUFFIXES {
        if lowered.endswith(ext) {
            return _JS_DECL;
        }
    }
    return _PY_DECL;
}

def _definition_index(repo_root: str, file_paths: list[str]) -> dict[str, list[str]] {
    if repo_root in _DEF_INDEX {
        return _DEF_INDEX[repo_root];
    }
    index: dict[str, list[str]] = {};
    for p in file_paths {
        source: str = _read_cached(os.path.join(repo_root, p));
        if not source {
            continue;
        }
        for pattern in _decl_patterns(p) {
            for name in re.findall(pattern, source) {
                if name not in index {
                    index[name] = [];
                }
                if p not in index[name] {
                    index[name].append(p);
                }
            }
        }
    }
    _DEF_INDEX[repo_root] = index;
    return index;
}

"""Identifier-shaped things a bug report mentions: backticked/@-prefixed
symbols, snake_case and CamelCase names, and anything written as a call.
These are what get matched against the definition index."""
def _mentioned_symbols(text: str) -> list[str] {
    found: list[str] = [];
    seen: set[str] = set();
    patterns: list[str] = [
        r'[`@]([A-Za-z_][A-Za-z0-9_.]*)',
        r'\b([A-Za-z_][A-Za-z0-9_]*)\s*\(',
        r'\b([a-z][a-z0-9]*(?:_[a-z0-9]+)+)\b',
        r'\b([A-Z][a-z0-9]+(?:[A-Z][a-z0-9]+)+)\b'
    ];
    for pattern in patterns {
        for raw in re.findall(pattern, text) {
            name: str = raw.strip("`@").split(".")[-1];
            if len(name) > 2 and name not in seen {
                seen.add(name);
                found.append(name);
            }
        }
    }
    return found;
}

"""First non-empty docstring line of file `p`, or "" if unreadable. Gives the
LLM fallback actual file responsibility instead of just a bare path - the
difference between guessing from a filename and reasoning about what a file
does (needed to recognize that unrelated-sounding symptoms share one cause)."""
def _file_summary(p: str, repo_root: str) -> str {
    source: str = _read_cached(os.path.join(repo_root, p));
    for line in source.splitlines() {
        stripped = line.strip().strip('"""').strip();
        if stripped {
            return stripped;
        }
    }
    return "";
}

def build_file_summaries(file_paths: list[str], repo_root: str | None) -> dict[str, str] {
    summaries: dict[str, str] = {};
    if not repo_root {
        return summaries;
    }
    for p in file_paths {
        summaries[p] = _file_summary(p, repo_root);
    }
    return summaries;
}

# ============================== Candidate shortlisting ==============================
# The LLM fallback used to be handed EVERY file path in the repo plus a summary
# for each. That is fine for the 18-file seed repo and impossible for a real
# open-source one: `jaseci-labs/jac` has 1000+ Python files, and that prompt
# blows straight past a local 7B model's context window - the call errors or
# comes back as noise. That is the concrete reason "index any repo" was pulled.
#
# So: a cheap, deterministic, LLM-free pre-filter picks the plausible files
# first, and only those reach the model. Nothing here decides an answer - it
# only decides what the model is allowed to see - so the resolution itself is
# still the model's call on a small, honest candidate set.
# 30, not 40, and not 20. Measured on the 11 issues already resolved across
# flask (83 files) and jac (95 files): at 40 the correct file ranked as low as
# 27th, so 20 and 25 both DROPPED one issue's real target off the list, while 30
# keeps every one of them. A smaller list is meaningfully cheaper - the resolve
# call is prefill-dominated - but not at the price of changing an answer.
glob CANDIDATE_CAP: int = 30;

# Words that appear in half a repo's paths and every bug report - matching on
# them ranks nothing above anything else.
glob _STOPWORDS: set[str] = {
         "the",
         "and",
         "for",
         "with",
         "that",
         "this",
         "when",
         "from",
         "have",
         "has",
         "not",
         "but",
         "you",
         "are",
         "was",
         "were",
         "there",
         "here",
         "src",
         "lib",
         "app",
         "test",
         "tests",
         "init",
         "main",
         "issue",
         "bug",
         "error",
         "python",
         "code",
         "file",
         "line"
     };

def _tokens(text: str) -> set[str] {
    return {
        t
        for t in re.findall(r"[a-z0-9]+", text.lower())
        if len(t) > 2 and t not in _STOPWORDS
    };
}

"""How well one candidate path matches the issue text. Token overlap on the
path itself, plus a large bonus when the body literally names the file (or its
module), which is as close to a certainty as a lexical signal gets."""
def _path_score(path: str, issue_tokens: set[str], body_lower: str) -> float {
    score: float = float(len(_tokens(path.replace("/", " ")) & issue_tokens));
    if path.lower() in body_lower {
        score += 20.0;
    }
    stem: str = _stem(path).lower();
    if len(stem) > 3 and stem in issue_tokens {
        score += 5.0;
    }
    return score;
}

"""The files an LLM should actually be asked to choose between, ranked most
plausible first. Returns everything (unchanged) for a repo small enough that
the whole list fits - the seed repo's behavior is bit-for-bit what it was.

Two passes so a big repo never costs a full-repo disk read: rank on the path
string alone, keep a generous margin, then read docstring summaries for only
that shortlist and re-rank with them."""
def shortlist_candidates(
    title: str,
    body: str,
    file_paths: list[str],
    repo_root: str | None,
    cap: int = 0
) -> tuple[list[str], dict[str, str]] {
    limit: int = cap if cap > 0 else CANDIDATE_CAP;
    if len(file_paths) <= limit {
        return (file_paths, build_file_summaries(file_paths, repo_root));
    }

    issue_tokens: set[str] = _tokens(f"{title} {body}");
    body_lower: str = f"{title} {body}".lower();

    # Files that DEFINE a symbol the report names. The strongest lexical signal
    # available without an LLM, and the one that makes a real repo tractable.
    defines_score: dict[str, float] = {};
    if repo_root {
        index: dict[str, list[str]] = _definition_index(repo_root, file_paths);
        for symbol in _mentioned_symbols(f"{title} {body}") {
            for p in index.get(symbol, []) {
                defines_score[p] = defines_score.get(p, 0.0) + 8.0;
            }
        }
    }

    by_path: list[tuple[float, str]] = [
        (_path_score(p, issue_tokens, body_lower) + defines_score.get(p, 0.0), p)
        for p in file_paths
    ];
    by_path.sort(key=lambda (row: tuple[float, str]) { return (-row[0], row[1]); });
    # 3x margin: the path string alone is a weak signal, so keep enough
    # candidates alive for the summary pass to actually change the ranking.
    prefilter: list[str] = [row[1] for row in by_path[:limit * 3]];

    summaries: dict[str, str] = build_file_summaries(prefilter, repo_root);
    rescored: list[tuple[float, str]] = [];
    for p in prefilter {
        score: float = _path_score(p, issue_tokens, body_lower) + defines_score.get(p, 0.0);
        score += float(len(_tokens(summaries.get(p, "")) & issue_tokens)) * 1.5;
        rescored.append((score, p));
    }
    rescored.sort(key=lambda (row: tuple[float, str]) { return (-row[0], row[1]); });

    chosen: list[str] = [row[1] for row in rescored[:limit]];
    return (
        chosen,
        {
            p: summaries.get(p, "")
            for p in chosen
        }
    );
}

def explicit_resolve(body: str, file_paths: list[str], repo_root: str | None = None) -> str | None {
    traceback_matches = re.findall(r'File "([^"]+\.py)", line \d+', body);
    if not traceback_matches {
        # A V8/Node stack trace is the JS equivalent of a Python traceback and
        # just as strong a signal: `at handler (/app/src/api/route.ts:12:5)`,
        # or the bare `src/api/route.ts:12:5` webpack/vite prints. Same
        # ordering convention - innermost frame last.
        traceback_matches = re.findall(
            r'((?:[\w.\-/\\@]+)\.(?:ts|tsx|js|jsx|mjs|cjs|mts|cts)):\d+(?::\d+)?', body
        );
    }
    if traceback_matches {
        # Python tracebacks list frames oldest-first; the LAST frame is where the
        # exception actually raised, so scan in reverse to find the real culprit
        # (the outermost frame is usually just the route/entry-point file).
        for candidate in reversed(traceback_matches) {
            for p in file_paths {
                if p == candidate or candidate.endswith(p) or p.endswith(candidate) {
                    return p;
                }
            }
        }
    }

    for p in file_paths {
        if p in body {
            return p;
        }
    }

    symbol_matches = re.findall(r'[`@]([A-Za-z_][A-Za-z0-9_.]*)', body);
    for sym in symbol_matches {
        cleaned = sym.strip("`@");
        first_segment = cleaned.split(".")[0];
        for p in file_paths {
            base = _stem(p);
            # Matches a bare filename/module reference (`validation`) or the
            # leading segment of a dotted attribute access (`product.price_cents`
            # -> "product" -> models/product.py).
            if cleaned == base or cleaned == p or first_segment == base {
                return p;
            }
        }
        if repo_root {
            # Bare method/function name with no owning module in the text
            # (`adjust_stock`) - find which file actually defines it. The index
            # is built once per checkout, so this stays O(1) per symbol even on
            # a repo with thousands of files.
            last_segment = cleaned.split(".")[-1];
            definers = _definition_index(repo_root, file_paths).get(last_segment, []);
            for p in file_paths {
                if p in definers {
                    return p;
                }
            }
        }
    }

    return None;
}

def assess_severity(title: str, body: str) -> int by llm(temperature=0.0);
sem assess_severity = "Rate how severe this bug report is on a scale of 1 (cosmetic/trivial) to 10 (critical: crashes, data loss, or breaks core functionality for many users). Typos and feature requests are low severity; crash reports and broad-impact bugs are high severity.";
sem assess_severity.title = "The issue title as reported by a user.";
sem assess_severity.body = "The issue body, which may include a stack trace.";

def estimate_diff_size(title: str, body: str) -> int by llm(temperature=0.0);
sem estimate_diff_size = "Estimate how many lines of code a fix for this issue would plausibly require, based on how localized or sprawling the described problem sounds. Return a single integer (e.g. ~3 for a one-line typo, ~40 for a moderate logic fix, 150+ for a large refactor).";
sem estimate_diff_size.title = "The issue title.";
sem estimate_diff_size.body = "The issue body/description.";

enum ReportSpecificity {
    VAGUE,
    CONCRETE
}
sem ReportSpecificity.VAGUE = "Pure venting or mood with NO named feature, page, file, action, or symptom of any kind - 'doesn't work', 'nothing works', 'every time I try to do anything something breaks', 'pls fix asap'. These give a reader nothing to go looking for.";
sem ReportSpecificity.CONCRETE = "Names at least one specific feature, page, file, action, input, or symptom - such that a different report of the SAME bug would independently mention a similar detail. Emotional delivery (ALL CAPS, exclamation points, 'URGENT', 'CRITICAL') does NOT make a report vague by itself: 'THE LOG FILES FILLED UP MY DISK' names a specific feature (log files) and symptom (disk full) - that's CONCRETE despite the shouting. Judge only on whether a specific thing is named, ignore tone entirely.";

"""A small, more reliable classification gate before attempting file
resolution at all - a single float confidence field is unreliable to
calibrate on a small local model, but VAGUE vs CONCRETE is a much easier
binary judgment and is what actually decides whether we should even guess."""
def assess_specificity(title: str, body: str) -> ReportSpecificity by llm(temperature=0.0);
sem assess_specificity = "Decide whether this bug report names any specific feature, page, file, action, or symptom (CONCRETE) or is pure vague venting with nothing specific named (VAGUE). Ignore emotional tone/shouting entirely - judge only on whether something specific is named.";
sem assess_specificity.title = "The issue title.";
sem assess_specificity.body = "The issue body/description.";

obj LLMResolution {
    has path: str | None = None;
    has confidence: float = 0.0;
}
sem LLMResolution.path = "The single repo-relative file path, taken verbatim from the provided list, that most plausibly contains the root cause. None if nothing in the list seems related.";
sem LLMResolution.confidence = "Confidence in this file assignment, 0.0 (pure guess) to 1.0 (certain), based on how precisely the report's stated facts match one file's responsibility. This is only called for reports already judged CONCRETE, so assume there is a real signal here - focus on HOW WELL it matches, not whether to trust it at all.";

def llm_resolve(title: str, body: str, file_paths: list[str], file_summaries: dict[str, str]) -> LLMResolution by llm(temperature=0.0);
sem llm_resolve = "Given a bug report and a codebase's files (with a short description of each file's responsibility), decide which single file most plausibly contains the ROOT CAUSE and how confident you are. Most reports contain no file names at all - match the described symptom/behavior against each file's description, not filename similarity. Different-sounding symptoms (a crash, a truncated emoji, a rejected phone number, a skipped CSV row) can all trace back to the SAME shared low-level utility if their descriptions point that way - read every file's description before deciding. This root-cause matching only applies when the report states a concrete fact (see the confidence field's rule) - pure venting with zero concrete detail gets low confidence no matter how thematically close a file sounds.";
sem llm_resolve.title = "The issue title.";
sem llm_resolve.body = "The issue body/description.";
sem llm_resolve.file_paths = "All known repo-relative file paths this issue could resolve to.";
sem llm_resolve.file_summaries = "Map of file path to a one-line description of that file's responsibility. Empty string if unavailable. This is the primary signal - use it to reason about responsibility, not the path string alone.";

def resolve_issue(title: str, body: str, file_paths: list[str], repo_root: str | None = None) -> Resolution {
    explicit_path = explicit_resolve(body, file_paths, repo_root);
    if explicit_path {
        return Resolution(path=explicit_path, confidence=0.95, method="explicit");
    }

    specificity = assess_specificity(title, body);
    if specificity == ReportSpecificity.VAGUE {
        return Resolution(path=None, confidence=0.0, method="none");
    }

    # Only the plausible candidates reach the model - see shortlist_candidates.
    # On a repo small enough to fit, this IS the full file list.
    (candidates, file_summaries) = shortlist_candidates(title, body, file_paths, repo_root);
    fallback = llm_resolve(title, body, candidates, file_summaries);
    if fallback.path and fallback.path in file_paths and fallback.confidence >= 0.55 {
        return Resolution(path=fallback.path, confidence=fallback.confidence, method="llm");
    }

    conf = 0.0;
    if fallback.path {
        conf = fallback.confidence;
    }
    return Resolution(path=None, confidence=conf, method="none");
}

# Real bug reports are long - environment dumps, reproduction steps, full logs.
# Prefill is ~200 tok/s, so body length is a direct per-call cost: a 3.6KB
# next.js body measured 6.33s of prefill against 0.58s for a 181-byte seed-repo
# body, and it is paid by EVERY LLM call the issue makes. Truncating what the
# model sees is the single biggest lever on a real repo.
#
# The DETERMINISTIC matcher (explicit_resolve) still gets the full body - it is
# pure Python and free, and it is what finds a traceback or a file path buried at
# the end of a long report. Only the LLM's copy is clipped, and the front of a
# report is where the symptom is stated; the tail is environment noise.
glob LLM_BODY_CHARS: int = 1500;

def _llm_body(body: str) -> str {
    if len(body) <= LLM_BODY_CHARS {
        return body;
    }
    return body[:LLM_BODY_CHARS] + "\n...[truncated]";
}

# ============================== Merged assessment ==============================
# Everything above still exists and is what the unit tests exercise. What
# ingestion actually calls is below, and the difference is purely how many
# round trips it takes.
#
# Each by llm() call carries ~1.2s of fixed cost on a local 7B (measured), and
# ingestion used to make three or four of them per issue for facts that are
# entirely independent of each other. Merging them into one structured call
# removes that fixed cost without changing what is being asked - the semstrings
# below are the originals, reworded only where a field name changed.

obj IssueImpact {
    has severity: int;
    has estimated_diff_lines: int;
}

sem IssueImpact = "How bad a bug report is and how big its fix looks.";
sem IssueImpact.severity = "How severe this report is, 1 (cosmetic/trivial) to 10 (critical: crashes, data loss, or breaks core functionality for many users). Typos and feature requests are low; crash reports and broad-impact bugs are high.";
sem IssueImpact.estimated_diff_lines = "How many lines of code a fix would plausibly require, based on how localized or sprawling the problem sounds - ~3 for a one-line typo, ~40 for a moderate logic fix, 150+ for a large refactor.";

"""Severity + fix size in one call, for issues already placed by an explicit
signal (traceback, path, symbol) and so needing no LLM resolution at all."""
def assess_impact(title: str, body: str) -> IssueImpact by llm(temperature=0.0);
sem assess_impact = "Read one bug report and judge how severe it is and how large a fix it would need.";
sem assess_impact.title = "The issue title as reported by a user.";
sem assess_impact.body = "The issue body, which may include a stack trace.";

# ⚠️ DO NOT merge the VAGUE gate into the resolution call. It was tried and
# reverted on 2026-07-29, and the failure is instructive: asked for
# specificity AND a file path in one structured response, the model answers
# CONCRETE and supplies a path at 0.8-0.9 confidence for reports that contain
# nothing at all. On the seed repo, "doesn't work" (#26) and "pls fix asap
# thanks" (#27) both got placed on utils/csv_export.py and then CLUSTERED
# TOGETHER, and the parked set collapsed from 4 issues to 2.
#
# Asked on its own, as a binary judgment with nothing else to produce, the same
# model correctly calls those VAGUE. The separate call is not redundant - it is
# the thing that stops the system guessing, which is the property the whole
# project is built on (CLAUDE.md §5: "Do not guess", and the demo beat that
# points at the parked issues). The ~1.2s it costs is the price of that.

obj TriagedIssue {
    has path: str | None = None;
    has confidence: float = 0.0;
    has method: str = "none";
    has severity: int = 0;
    has estimated_diff_lines: int = 0;
}

"""What ingestion calls: resolution AND impact for one issue, in as few LLM
round trips as the case allows.

  explicit signal placed it   1 call  (was 3: severity + diff + nothing else)
  too vague to place          2 calls (was 3)
  model has to place it       3 calls (was 4)

Decision logic is IDENTICAL to resolve_issue + assess_severity +
estimate_diff_size - explicit signals win outright at 0.95, the VAGUE gate parks
without guessing, the path must appear in file_paths, and the 0.55 confidence
threshold is unchanged. The only thing removed is the fixed per-call overhead of
asking for severity and fix size separately, which are independent of each other
and of resolution."""
def triage_issue(
    title: str, body: str, file_paths: list[str], repo_root: str | None = None
) -> TriagedIssue {
    # Full body for the deterministic matcher; clipped for anything that pays
    # prefill on it.
    explicit_path = explicit_resolve(body, file_paths, repo_root);
    brief: str = _llm_body(body);
    if explicit_path {
        impact = assess_impact(title, brief);
        return TriagedIssue(
            path=explicit_path,
            confidence=0.95,
            method="explicit",
            severity=impact.severity,
            estimated_diff_lines=impact.estimated_diff_lines
        );
    }

    # The specificity gate stays its own focused call - see the warning above.
    impact = assess_impact(title, brief);
    if assess_specificity(title, brief) == ReportSpecificity.VAGUE {
        return TriagedIssue(
            path=None,
            confidence=0.0,
            method="none",
            severity=impact.severity,
            estimated_diff_lines=impact.estimated_diff_lines
        );
    }

    # Only the plausible candidates reach the model - see shortlist_candidates.
    # On a repo small enough to fit, this IS the full file list.
    (candidates, file_summaries) = shortlist_candidates(title, body, file_paths, repo_root);
    fallback = llm_resolve(title, brief, candidates, file_summaries);
    if fallback.path and fallback.path in file_paths and fallback.confidence >= 0.55 {
        return TriagedIssue(
            path=fallback.path,
            confidence=fallback.confidence,
            method="llm",
            severity=impact.severity,
            estimated_diff_lines=impact.estimated_diff_lines
        );
    }
    return TriagedIssue(
        path=None,
        confidence=fallback.confidence if fallback.path else 0.0,
        method="none",
        severity=impact.severity,
        estimated_diff_lines=impact.estimated_diff_lines
    );
}
