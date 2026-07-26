"""Agent 1 (Triage): resolve a raw issue onto a code node and assess it.

Explicit signals (traceback / bare path / backticked symbol) are tried first.
Only when none match do we fall back to an LLM guess, and only accept that
guess above the confidence threshold (CLAUDE.md SS5). The walker that owns
graph writes (ingest_issue, Phase B) calls resolve_issue() and decides
whether to create a `resolves_to` edge or park the issue as Unresolved.
"""
import re;

obj Resolution {
    has path: str | None = None;
    has confidence: float = 0.0;
    has method: str = "none";
}

def explicit_resolve(body: str, file_paths: list[str]) -> str | None {
    traceback_match = re.search(r'File "([^"]+\.py)", line \d+', body);
    if traceback_match {
        candidate = traceback_match.group(1);
        for p in file_paths {
            if p == candidate or candidate.endswith(p) or p.endswith(candidate) {
                return p;
            }
        }
    }

    for p in file_paths {
        if p in body {
            return p;
        }
    }

    symbol_matches = re.findall(r'[`@]([A-Za-z_][A-Za-z0-9_./]*)', body);
    for sym in symbol_matches {
        cleaned = sym.strip("`@");
        for p in file_paths {
            base = p.split("/")[-1].replace(".py", "");
            if cleaned == base or cleaned == p {
                return p;
            }
        }
    }

    return None;
}

def assess_severity(title: str, body: str) -> int by llm();
sem assess_severity = "Rate how severe this bug report is on a scale of 1 (cosmetic/trivial) to 10 (critical: crashes, data loss, or breaks core functionality for many users). Typos and feature requests are low severity; crash reports and broad-impact bugs are high severity.";
sem assess_severity.title = "The issue title as reported by a user.";
sem assess_severity.body = "The issue body, which may include a stack trace.";

def estimate_diff_size(title: str, body: str) -> int by llm();
sem estimate_diff_size = "Estimate how many lines of code a fix for this issue would plausibly require, based on how localized or sprawling the described problem sounds. Return a single integer (e.g. ~3 for a one-line typo, ~40 for a moderate logic fix, 150+ for a large refactor).";
sem estimate_diff_size.title = "The issue title.";
sem estimate_diff_size.body = "The issue body/description.";

obj LLMResolution {
    has path: str | None = None;
    has confidence: float = 0.0;
}
sem LLMResolution.path = "The single repo-relative file path, taken verbatim from the provided list, that most plausibly contains the root cause. None if nothing in the list seems related.";
sem LLMResolution.confidence = "Confidence in this file assignment, 0.0 (pure guess) to 1.0 (certain), based on how well the report matches that file's apparent responsibility.";

def llm_resolve(title: str, body: str, file_paths: list[str]) -> LLMResolution by llm();
sem llm_resolve = "Given a bug report and the list of file paths in a codebase, decide which single file the report most likely points to and how confident you are.";
sem llm_resolve.title = "The issue title.";
sem llm_resolve.body = "The issue body/description.";
sem llm_resolve.file_paths = "All known repo-relative file paths this issue could resolve to.";

def resolve_issue(title: str, body: str, file_paths: list[str]) -> Resolution {
    explicit_path = explicit_resolve(body, file_paths);
    if explicit_path {
        return Resolution(path=explicit_path, confidence=0.95, method="explicit");
    }

    fallback = llm_resolve(title, body, file_paths);
    if fallback.path and fallback.path in file_paths and fallback.confidence >= 0.55 {
        return Resolution(path=fallback.path, confidence=fallback.confidence, method="llm");
    }

    conf = 0.0;
    if fallback.path {
        conf = fallback.confidence;
    }
    return Resolution(path=None, confidence=conf, method="none");
}
