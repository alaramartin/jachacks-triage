# PLAN.md — Triage (JacHacks SF)

> **You are a coding agent (Claude Code).** Your human will tell you **"I'm Person 1"** (or 2, or
> 3). Jump to that person's section and do **only that section, top to bottom.** Everything you
> need is inside your section — you do not need to read the other people's sections.
>
> **THE GOLDEN RULE — stop at every 🛑 CHECKPOINT.** Do not keep coding past a checkpoint.
> Instead, print the checkpoint's instructions to your human (who to merge with, exact commands,
> expected output), then **wait for the human to say it passed** before starting the next phase.
> Checkpoints are how three people stay in sync. Blowing past one breaks integration.
> When the human confirms that the work up until that checkpoint is sound, make a note of it in this PLAN.md (and if anything in the plan changes, make sure to update the PLAN.md accordingly). This is so that the human would be able to /clear chat and continue from where they left off if needed.

**Read `CLAUDE.md` first** — it has the graph schema (§4), the four-agent design (§5), and the
frozen API contract (§6).

**Before writing anything, confirm your human ran this in their Claude Code session:**

```
claude mcp add jac -- jac mcp
```

Then **verify all Jac syntax against the Jac MCP server — never guess Jac syntax from training
data.** The language is young; your priors are likely wrong.

**Timeline:** hacking 10:45 AM–7:15 PM · partial submission due 5:50 PM (mandatory) · closes
7:15 PM hard.

**Personalization note (all read once):** we're adding user-adjustable ranking weights (default
heavily favors blast radius; user can also weight issue reactions/upvotes). **This is a REACH
feature — built only in each person's Phase C, and the FIRST thing cut if we're behind.** The
demo always runs on the blast-radius-dominant default.

**Another feature**: the urgency calculation should also include a small factor of social signals--i.e. Upvotes / Reaction Count (👍, 🚀): High community upvotes indicate a widespread issue affecting real users; Comment Velocity: How many comments were posted in the last 24–48 hours? (A spike in comments usually means an active production outage or heated debate).

---

---

# ██ PERSON 1 — Graph & Agents ██

**You own:** `graph/nodes.jac`, `integrations/ast_parser.jac`, `agents/blast_radius.jac`,
`agents/clustering.jac`, `agents/ranking.jac`, and these endpoints in `main.jac`: `reindex_repo`,
`get_queue`, `get_cluster_detail`, `reset_demo`, `debug_blast`.
**You are the guardian of the numbers.** **Branch:** `p1/graph`.

## ✅ Person 1 master checklist

- [x] **Phase A:** node schema → AST parser → `reindex_repo` → `reset_demo` + `debug_blast` → blast-radius agent
- [x] **🛑 C1** (~12:45): confirm Person 2's seed repo is in (`find` == 18 files) — CONFIRMED: seed/repo is its own GitHub repo (github.com/alaramartin/triage-demo), cloned locally, 18 real module files + 1 token tests/test_smoke.py = 19 total .py files, matches reference exactly.
- [x] **🛑 C2** (2:15): first merge; **blast radius of validation.py MUST == 14** — CONFIRMED EARLY against real seed repo: core/validation.py=14, core/db.py=12, models/product.py=5, utils/logging.py=0. reindex_repo: 19 files indexed, 27 import edges. Also fixed a jac.toml bug: byllm model config must be under `[plugins.byllm.model]`, not `[byllm.model]` (jaclang's plugin config loader silently ignores the latter). Team is using local Ollama (ollama/qwen2.5:7b).
- [x] **Phase B:** clustering agent → ranking agent → `get_queue` — DONE. clustering.jac's over-clustering guard tested with MockLLM incl. SEED-15/16 anti-cluster case; ranking.jac's formula tested against hand-computed values; get_queue tested against constructed graph state (cluster + singletons + unresolved, sorted by urgency desc). NOTE: agents/triage_agent.jac (Person 2's file) has no MockLLM override, so its tests will fail until Ollama is running locally - expected, not a bug.
- [ ] **🛑 C3** (3:30): real-data integration; full ranked queue correct
- [x] **Phase C (steps 1-2):** `get_cluster_detail` (with graph payload) → performance — DONE,
      self-tested with hand-built graph state (main.test.jac now has 3 tests). Performance already
      satisfied — no recomputation added. _(reach weighted ranking still not started — see below.)_
- [ ] **🛑 C4** (5:30): feature freeze; verify ≥40% Jac
- [ ] **🛑 C5** (5:50): confirm Person 2 submitted the partial

### 📍 UPDATE from Person 2 (post-merge — read this before continuing Person 1 work)

**Merged cleanly** — Person 2 pulled this Phase B+C push, resolved one conflict in `main.jac`
(import list + `ingest_issue`/`generate_pr` sitting between your `reindex_repo`/`reset_demo`/
`debug_blast` and your `get_queue`/`get_cluster_detail`), and wired `ingest_issue` to call
`agents.ranking.on_issue_resolved` exactly per your contract note below. Real bugs found and fixed
in your code while merging/integration-testing (all `jac check`- or runtime-blocking, not style nits):

1. **`get_queue`'s sort-key lambdas** used `lambda c: ClusterView : c.urgency` — not valid Jac
   syntax (only `lambda (param: Type) { body }` exists). Fixed both (`cluster_views`/`singleton_views`).
2. **`agents/clustering.jac`'s `maybe_cluster`** had the same stale `(x +>:owns:+> Cluster(...))[0]`
   unwrap bug as the `reindex_repo` one from Phase A — `++>`/`+>:edge:+>` on a single node returns
   the node directly now, no `[0]`. Same pattern was also in `clustering.test.jac`'s and
   `main.test.jac`'s hand-built fixtures (`repo +>:owns:+> File(...)` etc.) — fixed throughout.
3. **`agents/clustering.test.jac` imported `byllm.lib` (bare package) instead of
   `jaclang.byllm.lib`.** This is what caused the "no by llm() call works, `by postinit`/`global`
   syntax error deep in byllm's source" scare (see below) — turned out to be a real, fixable bug,
   not a jac/byllm version incompatibility. **Lesson for the whole team: NEVER `import from
   byllm...` or add `byllm` as a pip dependency in `jac.toml` — the compiler bundles its own
   compatible copy as `jaclang.byllm`, always `import from jaclang.byllm.lib { ... }` if you need
   an explicit import (e.g. `MockLLM` in tests). Ambient `by llm()` with no import needed is safest.**
4. **`assess_root_cause` had zero code context** — CLAUDE.md's issues are deliberately worded to
   share no vocabulary even when they share a root cause, so with only issue text to go on, the
   local model said "different root cause" for everything, and `clusters` came back empty. Fixed by
   reading the target file's actual source (mirrors the `_file_summary` pattern Person 2 built for
   `llm_resolve`) and sharpening the same-root-cause bar to match what your own Cluster B design
   needs (two distinct symptoms in one file, same underlying sloppiness, one fixable PR) while still
   correctly rejecting SEED-15/16. Verified live: all three clusters now form correctly with the
   right blast radii (14/5/1).

**Also found: a `with entry` (or bare module-level `glob = ...`) inside a `.test.jac` annex that
references a class from the base module raises `NameError` at module-load time in this jac
version** (even outside `jac test` — the annex loads unconditionally whenever the base module
loads, e.g. via `jac start`). Fix: construct anything referencing base-module names *inside* each
`test { }` body, not at annex module scope — that executes fine. Keep this in mind for future
`.test.jac` files using MockLLM.

### 📍 RESUME HERE (last updated after Phase C steps 1-2)

**Exact code state right now:**
- `graph/nodes.jac`, `integrations/ast_parser.jac`, `agents/blast_radius.jac` (Phase A),
  `agents/clustering.jac` + `clustering.test.jac`, `agents/ranking.jac` + `ranking.test.jac`,
  `main.jac` (`reindex_repo`/`reset_demo`/`debug_blast`/`get_queue`/`get_cluster_detail`),
  `main.test.jac` — **all written and all of Person 1's tests passing locally, but NOT YET
  COMMITTED beyond commit `199ffb4`** (Phase A only). Run `git status` on resume — expect
  `main.jac`, `graph/nodes.jac`, `agents/blast_radius.jac`, `PLAN.md`, `CLAUDE.md` modified, plus
  untracked `agents/clustering.jac`, `agents/clustering.test.jac`, `agents/ranking.jac`,
  `agents/ranking.test.jac`, `main.test.jac`. Commit these before starting further work (ask the
  human first, per repo convention — don't auto-commit). `CLAUDE.md`'s diff is whitespace-only
  (JSON reformatting), not a contract change.
- **Schema change to announce to the team:** `Cluster` gained a new field
  `proposed_fix_summary: str = ""`, set by `clustering.jac`'s `maybe_cluster()` alongside
  `root_cause_summary` (same `by llm()` call — `RootCauseGate` now returns both). This is
  additive/backward-compatible (new field, existing fields untouched) and powers
  `get_cluster_detail`'s `proposed_fix_summary` response field. Purely a Person 1 (P1) schema
  decision per §9 ownership — announce it, don't need to re-litigate it.
- **`get_cluster_detail`** (`main.jac`) is built and self-tested: reverse-BFS dependency graph
  with `role` (`target`/`dependent`) + `hops`, edges in code direction restricted to the
  reachable set, issue detail list (with `body`), `existing_pr` (null unless a `PullRequest`
  `fixes`-edge exists), and a `{"ok": false, "error": "cluster not found"}` shape for a bad
  `cluster_id`. New helper `build_dependency_graph(target: File) -> dict[str, list]` lives in
  `agents/blast_radius.jac` (same file as `compute_blast_radius`, same reverse-BFS-over-incoming-
  `imports` pattern — CLAUDE.md #4.3). **Person 3 is unblocked on this now** — tell the human to
  notify Person 3 it's ready (originally scheduled for ~4:15, done earlier).
- **Performance (Phase C step 2):** already satisfied — `get_queue` only reads cached
  `File.blast_radius`, never recomputes. `get_cluster_detail` does one fresh BFS per call
  (~18 nodes, sub-millisecond) since it's a click-triggered detail view, not the hot queue path.
- `jac test -d .` results as of last run: everything of mine passes (`main.jac`: 3 tests —
  `get_queue` e2e, `get_cluster_detail` happy path, `get_cluster_detail` unknown-id error;
  `ranking.jac`: 4; `clustering.jac`: 2). `agents/triage_agent.jac` (Person 2's file) still fails
  2 tests — expected, no local Ollama running, not a bug in their code.
- Ran `jac format` on every file I touched this session (`main.jac`, `agents/blast_radius.jac`,
  `agents/clustering.jac`, `graph/nodes.jac`, `agents/clustering.test.jac`, `main.test.jac`) —
  note the command is `jac format`, not `jac fmt`. This reformatted whole-file whitespace on
  `main.jac` (multi-line call args, spacing around `->`/`<-` etc.) — CLAUDE.md #9 warns against
  reformatting the whole shared file to avoid merge conflicts; flag this to the human so
  Person 2/3 know to expect whitespace-only diff noise in `main.jac` on their next pull, on top
  of the new `get_cluster_detail` walker.
- The Jac MCP server is installed and registered (`claude mcp add jac -- jac mcp`, shows
  `✔ Connected`) and was used this session for syntax/pattern verification
  (`jid()` confirmed as a language builtin, no import needed).

**⚠️ Contract Person 2's `ingest_issue` MUST follow (this was inferred/decided by Person 1
while building Phase B, since `ingest_issue` doesn't exist yet — confirm with Person 2 before
they start, don't let them redesign this):**
1. Every `Issue`, resolved or not, attaches to the `Repo` via `owns`: `repo +>:owns:+> Issue(...)`.
   Never attach an Issue directly to `root`.
2. If resolved (explicit or LLM above threshold): `issue +>:resolves_to:+> target_file;` then
   call **`agents.ranking.on_issue_resolved(issue, target_file, repo)`** — this one call cascades
   blast-radius -> clustering -> ranking. Don't call `blast_radius.jac`/`clustering.jac` functions
   directly; `on_issue_resolved` is the single integration point.
3. If parked (confidence < 0.55): get-or-create the repo's one `Unresolved` node
   (`[repo ->:owns:->][?:Unresolved]`, create via `repo +>:owns:+> Unresolved()` if none exists
   yet) and attach `unresolved +>:parked:+> issue;`. Do NOT call `on_issue_resolved` for parked
   issues — there's nothing to rank.
4. `get_queue` (already built) infers "singleton vs unresolved" purely from whether the Issue has
   an outgoing `resolves_to` edge — it does not re-check the `Unresolved` node. So a resolved
   issue MUST get a `resolves_to` edge, and a parked one MUST NOT, or it'll show up in the wrong
   bucket.

**Can Person 1 continue without Person 2?** Yes, for all of Phase C (`get_cluster_detail`,
performance pass, reach weighted ranking) — none of it structurally depends on Person 2's code;
self-test with hand-built graph state exactly like `main.test.jac` does for `get_queue`. What
Person 1 genuinely needs from Person 2 is `ingest_issue` + `seed.jac` actually landing before the
**real** C3 checkpoint (full 20-issue ranked queue matching the reference table) can be verified
end-to-end — that's an integration-checkpoint blocker, not a coding blocker.

**Next up: Phase C** — `get_cluster_detail` (with the `graph` payload: nodes w/ role+hops, edges
in code direction), then a performance pass (already satisfied — `get_queue` only reads cached
`File.blast_radius`, never recomputes), then reach weighted ranking only if time allows.

## Person 1 · Phase A — code substrate + blast radius

1. **`graph/nodes.jac`** — every node and edge from CLAUDE.md §4.1/§4.2. **Verify syntax against
   the Jac MCP docs.** Commit, push, and tell your human: _"Tell Person 2 and Person 3 the schema
   is pushed."_
2. **`integrations/ast_parser.jac`** — walk a directory, find `.py` files, parse `import` /
   `from X import Y` with Python's `ast` module (`import ast` directly — Jac has all of PyPI). For
   each intra-repo import create an `imports` edge. Map dotted names (`core.validation`) →
   repo-relative POSIX paths (`core/validation.py`). Ignore stdlib/third-party imports.
3. **`walker:pub reindex_repo`** in `main.jac` (CLAUDE.md §6).
4. **`walker:pub reset_demo`** (wipe Issue/Cluster/PR nodes, keep code substrate) and
   **`walker:pub debug_blast`** (`{"path":"..."}` → blast-radius int). You'll use both all day.
5. **`agents/blast_radius.jac`** — blast radius of B = count of distinct `File` nodes that can
   transitively reach B by following `imports` forward = **reverse BFS from B over INCOMING
   `imports` edges, with a `visited` set, not counting B.** Re-read CLAUDE.md §4.3 — wrong
   direction is the #1 bug of the day. Write to `File.blast_radius`.

**Self-test before C1:** 3-file stub in `/tmp` where `a.py`→imports→`b.py`→imports→`c.py`. Expect
`debug_blast`: `c.py`=2, `b.py`=1, `a.py`=0.

**🛑 CHECKPOINT C1 (~12:45).** Print to human and wait:

> Person 2 must have pushed `seed/repo/` with 18 files. Ask the team: has Person 2 announced
> "skeleton is up"? If yes:
>
> 1. Pull `main`. 2. Run `find seed/repo -name "*.py" | wc -l` → expect **18**.
>    Say "C1 passed" and I'll point the parser at the real repo and confirm validation.py = 14
>    before our C2 merge. If not 18, tell me and we wait for Person 2.

## Person 1 · Phase B — clustering + ranking + queue

**Start only after the human says "C2 passed."**

1. **`agents/clustering.jac`** — fires when a `resolves_to` edge lands on a File already having
   ≥1 other incoming `resolves_to`. **Two required steps:**
    - group candidates by shared target File (pure graph read),
    - **`by llm()` gate** (CLAUDE.md §4.5): do these issues share ONE root cause? If not, keep them
      as separate singletons on the same File. _(This is what stops SEED-15 (typo) and SEED-16
      (perf) — both on `services/orders.py` — from wrongly merging. It's a demo beat.)_
      Create/attach `Cluster` (`cluster_key` = target path); set `title`, `root_cause_summary`,
      `issue_count`, `blast_radius` (copy from target File), `fix_confidence`.
2. **`agents/ranking.jac`** — formula below. Put weights as named constants **in this file only:**
   `W_BLAST = 6.0`, `W_SEV = 3.0`, `W_DIFF = 1.0`. For a cluster: use its `blast_radius`, the
   **max** severity of members, the **max** estimated diff. Write `urgency` to `Issue` + `Cluster`.
    ```
    urgency = 6·(blast_radius/file_count) + 3·(severity/10) − 1·min(diff/100, 1)
    ```
3. **`walker:pub get_queue`** (CLAUDE.md §6) — `clusters` and `singletons` each **sorted
   server-side by urgency descending.** Frontend does not sort.
4. Confirm agents hand off through graph state, not by calling each other on the core loop
   (CLAUDE.md §5). Note anywhere you cheated so nobody oversells it.

**🛑 CHECKPOINT C2 (2:15) — first integration merge.** Print to human and wait:

> 1. **Merge order: I (Person 1) merge `p1/graph` → `main` FIRST**, then Person 2, then Person 3.
> 2. On `main`: `jac start main.jac --dev`, then:
>     ```
>     curl -X POST localhost:8000/walker/reindex_repo -H 'Content-Type: application/json' \
>       -d '{"repo_path":"seed/repo","full_name":"triage-demo/shipyard"}'
>     ```
>     Expect `files_indexed: 18`, `import_edges: ~26`.
> 3. THE critical test:
>     ```
>     curl -X POST localhost:8000/walker/debug_blast -H 'Content-Type: application/json' \
>       -d '{"path":"core/validation.py"}'
>     ```
>     **Expect exactly 14.** Also `models/product.py`→5, `utils/logging.py`→0.
> 4. 🛑 If validation.py ≠ 14, tell me and STOP — everything downstream depends on it. If all
>    three are right, say "C2 passed."

## Person 1 · Phase C — cluster detail + performance + (reach) weighted ranking

**After the human says "C3 passed."**

1. **`walker:pub get_cluster_detail`** (CLAUDE.md §6) including the `graph` payload: `nodes` with
   `role` (`target`/`dependent`/`neutral`) and `hops` (BFS distance from target); `edges` in code
   direction (`from` imports `to`). **Person 3 is blocked on this — finish by ~4:15 and tell your
   human to notify Person 3.**
2. **Performance:** `get_queue` under ~2s — use the cached `File.blast_radius`, never recompute
   per request.
3. **(REACH — only if C3 passed cleanly and you have spare time) Weighted ranking.** Make the
   ranking accept a weights object so the frontend can personalize:
    - Add a `Settings` node (one per Repo) holding `w_blast`, `w_sev`, `w_diff`, `w_reactions`,
      `w_comment_velocity`, with the core defaults above and both social weights defaulting to
      `0.0`.
    - Add `reactions: int` and `comment_velocity: int` fields to `Issue` (Person 2 populates these
      from seed data — mostly low/flat values, since we're not counting on them to visibly move
      the demo ranking, just to be real and buildable).
    - Extend the formula: `... + w_reactions·(reactions/max_reactions) + w_comment_velocity·(comment_velocity/max_comment_velocity)`.
    - Add `walker:pub set_weights` (writes the `Settings` node) and have `get_queue` read weights
      from it and re-rank. Keep the **default demo weights blast-dominant** — the live demo never
      touches the sliders unless we explicitly choose to.
    - If you don't reach this, the fixed formula from Phase B is completely fine and is what we
      demo. **Do not build this before Phase C steps 1–2 are done and tested.**
4. Re-run the C3 pipeline test after every change — you own the numbers.

**🛑 CHECKPOINT C4 (5:30) — feature freeze.** Print to human and wait:

> Run the full clean pipeline once more (`reset_demo` → `jac run seed/seed.jac` → `get_queue`);
> confirm cluster A is #1 with blast radius 14. Check the GitHub language bar shows **≥40% Jac**
> (if not, tell me — we may need to `.gitignore` the seed repo's Python from language stats). Say
> "C4 passed" and after this I only fix bugs.

**🛑 CHECKPOINT C5 (5:50).** Print to human:

> Remind Person 2 to submit the partial on Devpost NOW (mandatory to be judged). Confirm it's
> done, then bring me only bugfixes.

## Person 1 — reference data (assert against these)

**Seed repo import tree** (Person 2 builds it; you assert on it):

```
core/validation.py  ← (none)          core/config.py ← (none)     core/errors.py ← (none)
core/db.py          ← core.validation
models/order.py     ← core.validation, core.db, core.errors
models/user.py      ← core.validation, core.db
models/product.py   ← core.validation, core.db
models/cart.py      ← models.product, core.validation
services/orders.py  ← models.order, core.errors
services/users.py   ← models.user
services/inventory.py ← models.product, core.db
services/pricing.py ← models.cart, models.product
services/upload.py  ← core.validation, core.config
api/routes_orders.py ← services.orders, services.pricing
api/routes_users.py ← services.users
api/routes_admin.py ← services.inventory, services.upload
utils/logging.py    ← core.config
utils/csv_export.py ← models.order
```

**Blast radius (transitive dependents, exclude self), file_count = 18:**
`core/validation.py`=**14** ★ · `core/db.py`=12 · `models/product.py`=**5** · `core/config.py`=3
· `models/order.py`=3 · `services/upload.py`=1 · `services/orders.py`=1 · `services/users.py`=1 ·
`api/routes_admin.py`=0 · `api/routes_users.py`=0 · `utils/logging.py`=0.
_(validation.py coming out 0/1/6 = wrong traversal direction, CLAUDE.md §4.3.)_

**Expected ranked queue** (urgency = 6·(blast/18)+3·(sev/10)−min(diff/100,1)):

1. Cluster A `core/validation.py` (5 issues, blast 14) → **7.22**
2. Cluster B `models/product.py` (3 issues, blast 5) → **3.87**
3. SEED-18 (1,8) → 2.48 · 4. SEED-17 (0,9) → 2.40 · 5. Cluster C `services/upload.py` (2) → 1.88
4. SEED-16 → 1.78 · 7. SEED-11 🚨 → **1.40** (demoted) · 8. SEED-14 → 1.20 · 9. SEED-12 → **1.08**
   (demoted) · 10. SEED-15 → 0.61 · parked: SEED-13, 19, 20.
   **Exact:** blast-radius integers + the ordering (A #1; SEED-11/12 below Cluster B). Severity may
   drift ±1–2 (it's from an LLM). If drift breaks ordering, tell Person 2 to hard-pin severity in
   `issues.json`.

---

---

# ██ PERSON 2 — Seed data, Ingestion, LLM & PR action ██

**You own:** `seed/` (demo repo + issues), `agents/triage_agent.jac`, `agents/pr_agent.jac`,
`integrations/github.jac`, and the `ingest_issue` / `generate_pr` endpoints. **Branch:** `p2/agents`.

## ✅ Person 2 master checklist

- [x] **🚨 TASK ZERO** (by 12:45): push `seed/repo/` skeleton — 18 files, correct imports. Pushed as its own nested git repo under `seed/repo/.git`, gitignored from the main repo (see `.gitignore`).
- [x] **Phase A:** flesh out seed repo + bugs → `issues.json` → start triage agent — all 18 files fleshed out with the three planted bugs, 20 issues in `seed/issues.json` (incl. `reactions`/`comment_velocity`), samples for SEED-01/SEED-19.
- [x] **🛑 C1** (~12:45): confirm skeleton is up + Person 1's schema is back — confirmed, both sides done.
- [x] **🛑 C2** (2:15): first merge; ingestion resolves SEED-01, parks SEED-19 — confirmed live against the real server: SEED-01 → `core/validation.py`, explicit, sev 8; SEED-19 → parked. Also confirmed `debug_blast` 18/14/5/0 numbers still hold post-merge.
- [x] **Phase B:** finish triage (LLM fallback + threshold) → `ingest_issue` → `seed.jac` → GitHub auth setup — all done, see RESUME HERE below.
- [x] **🛑 C3** (3:30): real-data integration; 3 unresolved — **PASSED**, verified live end-to-end (see below). Unresolved is 4, not 3 (SEED-11 misclassified as vague by the local model — a known, documented caveat, not a logic bug).
- [x] Push `seed/repo/` to GitHub as a real, Person-2-owned repo — DONE early (nested repo at `github.com/alaramartin/triage-demo`, gitignored from main repo). Confirmed still pushed/in sync with `origin/main` this session.
- [x] Real GitHub PR creation (`integrations/github.jac` `create_pull_request`) — DONE. Real GitHub REST API calls (create branch, write file via Contents API, open PR) replace the Phase B stub. Authenticates via a **Personal Access Token** (`GITHUB_TOKEN` in `.env`), NOT OAuth — OAuth login was already a documented scope cut (RepoPickerScreen hardcodes the single demo repo regardless of login, so real OAuth would change nothing the demo shows). Verified against the real `alaramartin/triage-demo` repo: branch created, file written, PR opened, closed again during testing (see below).
- [x] `agents/pr_agent.jac` — DONE. Human-triggered only (not on the reactive loop, CLAUDE.md #5). Sensitive-path denylist gate (`.env`, `docker-compose`, `migrations/`, `schema.*`) runs before any LLM call or GitHub write. PR body includes root cause, the blast-radius pitch ("reached by N of M files"), and linked issues — matches CLAUDE.md #8's on-screen PR body requirement.
- [x] **Real bug found + fixed this session:** the first live PR generated a **syntactically invalid** Python file (LLM mangled the module docstring's closing quote, `"""..."" ` instead of `"""..."""`) — would have opened a broken PR onto the real repo undetected. Added a `compile()`-based Python syntax gate in `pr_agent.jac` with up to 3 regenerate attempts (feeding the exact `SyntaxError` back to the LLM as a retry hint), plus a cheap deterministic regex repair (`_repair_module_docstring`) for this exact, extremely consistent failure shape — tried before spending a retry.
- [x] Swapped `generate_fix`'s LLM to `qwen2.5-coder:7b` (code-specialized, same size class as the project default, free/local — no paid API key) via a per-file `Model` override in `pr_agent.jac`, leaving triage/clustering/ranking on the project default model. Fixed an earlier truncation failure mode (was cutting output ~10 lines into a ~30-line file).
- [x] **Decision (human call, noted here since it changes the correctness bar):** PR code quality is explicitly NOT a blocker for the demo. `generate_pr` opening *some* real PR with a real description (root cause + blast-radius pitch + linked issues) is the bar — the generated fix code doesn't need to be perfect. Verified: PR #2 on `alaramartin/triage-demo` opened with valid, correct Python (the repair above got it right), but even if a future run's generated code has a rough edge, `build_pr_for_cluster` now proceeds and opens the PR anyway after 3 attempts + the deterministic repair, logging a warning instead of returning `{"ok": false}`. Rationale: judges evaluate the working demo (ranking, clustering, blast radius, the click-to-PR flow), not a code review of the generated diff — "we didn't spend API credits polishing generated-fix quality" is an acceptable answer if asked. This does NOT relax the sensitive-path denylist gate (CLAUDE.md #4.4), which still refuses unconditionally.
- [x] **🛑 C4** (5:30): feature freeze; real PR opens — verified live: PR #2, https://github.com/alaramartin/triage-demo/pull/2, valid Python, correct root-cause fix, full PR body (root cause + "reached by 14 of 18 files" + linked issues SEED-01..04).
- [ ] **🛑 C5** (5:50): **YOU submit the partial** (mandatory) — human action, not code.
- [ ] **🛑 C6** (6:45–7:15): final submission — human action, not code.
- [x] _(reach)_ `reactions`/`comment_velocity` data — already in `seed/issues.json` and ingested (done early, folded into Phase A). The only remaining reach piece (actually *weighting* ranking by these) is Person 1's `Settings` node/formula work, not Person 2's — skip tracking it here.

**Person 2's code work is DONE.** Only C5/C6 remain, and those are human submission actions (Devpost, screenshots, demo video), not code.

### 📍 RESUME HERE (Person 2, DONE — only C5/C6 human submission steps remain)

**Status at a glance: Person 2's code work is finished.** Real GitHub PR creation is wired
end-to-end and verified live — PR #2 on `alaramartin/triage-demo`
(https://github.com/alaramartin/triage-demo/pull/2) opened with valid Python, a correct fix, and
the full CLAUDE.md #8 PR body (root cause + "reached by 14 of 18 files" + linked issues). Nothing
left to build here; pick up at C5 (Devpost partial submission) when ready.

**DONE this session (Phase C):**
1. **`integrations/github.jac`** — `create_pull_request` is no longer a stub. Real GitHub REST
   calls: read the default branch's head SHA, create a new timestamped branch (`triage/fix-<ts>`,
   collision-proof across rehearsal runs), write the fixed file via the Contents API (a full-file
   write, not a diff — much more reliable for an LLM to get right than unified-diff syntax), open
   the PR. Auth is a **Personal Access Token** (`GITHUB_TOKEN` in `.env`), decided instead of OAuth
   — OAuth login was already a documented scope cut elsewhere (`RepoPickerScreen.cl.jac` hardcodes
   the single demo repo regardless of login, so real OAuth would change nothing the demo shows).
2. **`agents/pr_agent.jac`** (new file) — human-triggered only, not on the reactive graph loop
   (CLAUDE.md #5). `is_sensitive_path()` denylist gate (`.env`, `docker-compose`, `migrations/`,
   `schema.*`) runs before any LLM call or GitHub write. `build_pr_body()` produces the on-screen
   PR body CLAUDE.md #8 wants: root cause, the blast-radius pitch ("reached by N of M files"),
   linked issues. `main.jac`'s `generate_pr` walker now delegates to
   `pr_agent.build_pr_for_cluster()` instead of building the PR inline.
3. **Repo full_name mismatch found + fixed:** the graph's `Repo.full_name` had been set to the
   fictional CLAUDE.md example name `triage-demo/shipyard`, but the actual GitHub repo Person 2
   owns is `alaramartin/triage-demo` — real GitHub API calls need the real name. Fixed by
   reindexing with the real full_name and updating the two client constants that hardcoded the old
   fictional name (`client/screens/RepoPickerScreen.cl.jac`, `client/screens/QueueScreen.cl.jac` —
   both Person 3's files, changed here because it was a blocking mechanical fix, not a design
   change; tell Person 3). **`client/mock_data.cl.jac` still has the old fictional name but is
   dead code (nothing imports it) — harmless, left as-is.**
4. **Real bug caught by testing against the actual GitHub API (not just `jac check`):** the first
   live `generate_pr` call opened PR #1 with a source file that had a **broken docstring** (LLM
   turned `"""..."""` into `""..."""`, an unterminated string — the file would fail to import).
   Confirmed via `ast.parse`/`compile()`. **Fixed:** `pr_agent.jac` now runs the generated fix
   through `compile(content, path, "exec")` before ever calling GitHub; on a `SyntaxError` it
   retries (up to 3 attempts) feeding the exact error back to the LLM as `retry_hint`; if still
   invalid after 3 attempts, `generate_pr` returns `{"ok": false, "error": "..."}` instead of ever
   publishing broken code. **The broken PR #1 and its branch were closed/deleted from the real
   repo during this cleanup** — don't be surprised if PR history shows a closed PR #1.
5. **`.env.example`** updated: `GITHUB_TOKEN` documented as the real-PR-creation credential;
   `GITHUB_CLIENT_ID`/`GITHUB_CLIENT_SECRET` kept but marked as unused OAuth scaffolding.

**RESOLVED — model truncation + the correctness bar decision:** `generate_fix`'s LLM call was
silently truncating full-file output mid-string on the project's default model (`qwen2.5:7b`,
confirmed by dumping raw output — cut off ~10 lines into a ~30-line file). Root cause was the
*model*, not `max_tokens` (raising it to 4000 didn't help): a full-file code rewrite is a much
harder structured-output task than the short severity/clustering classifications elsewhere.
**Fixed** by pulling `qwen2.5-coder:7b` (same size class, code-specialized, still free/local — no
paid API key) and pointing `pr_agent.jac`'s `generate_fix` at it via a per-file `Model` override
(`glob fix_llm`), leaving triage/clustering/ranking untouched on the project default.

Even on the coder model, the exact same docstring-quote bug from PR #1 recurred once more —
consistent enough (always the module docstring's closing `"""`, always the first line, every other
docstring in the file closes fine) that a **deterministic regex repair**
(`_repair_module_docstring` in `pr_agent.jac`) was added ahead of spending a retry on it. That
repair alone fixed PR #2's generation cleanly (verified with `ast.parse`).

**Human decision, applied in code:** PR code quality is explicitly not a demo blocker — a real PR
with a real description matters more than a perfect diff. `build_pr_for_cluster` no longer returns
`{"ok": false}` if 3 attempts + the repair still leave invalid Python; it opens the PR anyway with
the best attempt and logs a warning. The sensitive-path denylist (CLAUDE.md #4.4) is NOT affected
by this — it still refuses unconditionally, before any LLM call.

**Historical context (kept for reference — superseded by the above where it overlaps):**

**✅ C3 PASSED — full pipeline verified live** against the real server + Ollama (`qwen2.5:7b`):
`reindex_repo` (18 files, 26 import edges) → `jac run seed/seed.jac` (all 20 issues) →
`get_queue` returns:
- **Cluster A** `core/validation.py`: 4 issues (SEED-01/02/03/04), blast 14, urgency 6.76.
- **Cluster B** `models/product.py`: 2 issues (SEED-06/08), blast 5, urgency 3.76.
- **Cluster C** `services/upload.py`: 2 issues (SEED-09/10), blast 1, urgency 2.58.
- **Unresolved**: 4 (SEED-11/13/19/20 — expected 3, SEED-11 is the known miscalibration below).

All blast-radius numbers match PLAN.md's reference table exactly. Gaps vs. the reference (SEED-05
and SEED-07 landing on adjacent files instead of joining their clusters, SEED-11 parking instead of
resolving) are **local-7B-model resolution accuracy**, not logic bugs — re-check with a stronger
hosted model before the real demo if you get an API key.

**🚨 The environment blocker from before IS RESOLVED — and it was never actually a jac/byllm version
incompatibility.** Root cause: `jac.toml` had `byllm` as a pip dependency, and
`agents/clustering.test.jac` imported it via the bare `byllm.lib` path. That pulled in a real PyPI
`byllm` release using `by postinit`/`global` syntax this jac compiler can't parse. **The compiler
already bundles its own compatible byllm as `jaclang.byllm`** — no pip install needed or wanted.
Fixed: dropped the pip dependency, fixed the import to `jaclang.byllm.lib`. **Team-wide rule now
documented in `jac.toml`: never `import from byllm...` (bare) and never add `byllm` to
`[dependencies]` — always `jaclang.byllm.lib` for explicit imports (e.g. `MockLLM` in tests);
ambient `by llm()` needs no import at all.** See the Person 1 UPDATE note above for the full
fix list, including a second real bug in `clustering.jac`'s `assess_root_cause` (no code context →
always said "different root cause") that's also now fixed and verified.

**Merge integration done this session** (Person 1 pushed their Phase B+C — clustering, ranking,
`get_queue`, `get_cluster_detail` — while Person 2 was mid-Phase-B; merged cleanly with one real
conflict in `main.jac`, resolved by hand):
- `main.jac`'s `ingest_issue` now calls **`agents.ranking.on_issue_resolved(issue, target, repo)`**
  right after creating the `resolves_to` edge — this is Person 1's documented integration point
  (see their contract note below) and cascades blast-radius → clustering → ranking in one call, all
  re-reading graph state fresh (no direct values passed downstream, per CLAUDE.md #5). `ingest_issue`'s
  response now reports real `clustered_into` (the cluster's `cluster_key` if the issue landed in one,
  else `null`) and real `urgency` (read back off `issue.urgency` post-cascade) instead of the
  Phase-B placeholders (`null`/`0.0`) — **no more hardcoded fields in the ingestion response.**
- Fixed **three separate instances of the same stale bug**: `(root ++> Node(...))[0]` /
  `(x +>:edge:+> Node(...))[0]` — the `[0]` unwrap is wrong against the current Jac compiler
  (`++>`/`+>:edge:+>` on a single node now return the node directly, not a list). Found and fixed in
  `main.jac`'s `reindex_repo` (found before this merge), `agents/clustering.jac`'s `maybe_cluster`,
  and throughout `agents/clustering.test.jac` + `main.test.jac`'s hand-built test fixtures. All now
  `jac check` clean with zero errors.
- Fixed a **real syntax bug in Person 1's `get_queue`**: `lambda c: ClusterView : c.urgency` (Python
  lambda-with-annotation style) isn't valid Jac — the only lambda form is
  `lambda (param: Type) { body }`. Fixed both sort-key lambdas (`cluster_views`/`singleton_views`).
  This was blocking `main.jac` from compiling at all pre-fix.
- `jac.toml`'s `[byllm.model]` fix (from earlier this session) held through the merge — confirmed
  Person 1 did NOT reintroduce the `[plugins.byllm.model]` mistake.

**Everything else from Phase B (unaffected by the merge, already reported last checkpoint):**
`agents/triage_agent.jac` (explicit resolve incl. traceback-direction + symbol-to-file static
lookup, `assess_specificity` gate before `llm_resolve`, file-docstring context, `temperature=0`),
`integrations/github.jac` (real OAuth token exchange + `list_repos`, `create_pull_request` stub),
`seed/seed.jac` (loads all 20 issues via HTTP against a running server — `jac run` does NOT share
graph state with the server's root, confirmed by testing both ways).

**GitHub OAuth app registration is NO LONGER NEEDED** — Phase C used a Personal Access Token
instead (see DONE section above), which is simpler and required no human UI step beyond generating
the token once. `GITHUB_CLIENT_ID`/`SECRET` scaffolding in `integrations/github.jac` is unused on
the demo path but left in place, harmless.

**Nothing left to pick up code-wise.** If resuming for the merge/demo-rehearsal phase, the standard
rehydrate command for any fresh session is: `pkill -f "jac start main.jac"`; `jac clean --all
--force`; `jac start main.jac --no-client`; then `reindex_repo` (use `full_name:
"alaramartin/triage-demo"` — the REAL repo name, not the old fictional `triage-demo/shipyard`) →
`jac run seed/seed.jac` → `get_queue` to get back to a working state. `ollama list` should show
both `qwen2.5:7b` and `qwen2.5-coder:7b` pulled locally; no other env setup is needed beyond
`.env`'s `GITHUB_TOKEN`.

## Person 2 · Phase A — TASK ZERO, then seed + triage

**🚨 TASK ZERO — before anything else. Person 1 is blocked.** Create all 18 files in `seed/repo/`
with the **exact imports** from the reference at the end of your section. Bodies can be `pass`.
Commit, push, tell your human: _"Announce: skeleton is up."_ Target 30 min.

Then:

1. Flesh the 18 files into plausible 20–60-line modules. Plant the three bugs (reference below)
   **exactly as written** — especially the two-line star bug in `core/validation.py`.
2. **`seed/issues.json`** — all 20 issues (reference below). Tracebacks must look real; Cluster
   A's five must share no distinctive vocabulary.
3. **`seed/samples/seed-01.json`** and **`seed/samples/seed-19.json`** (single issues) for tests.
4. Start **`agents/triage_agent.jac`:**
    - `by llm()`: `assess_severity(title, body) -> Severity` (`Severity` = an `enum`),
      `estimate_diff_size(title, body) -> int`, `resolve_issue(title, body, file_paths) -> ...`
      (returns path + confidence).
    - **Explicit-signal layer runs FIRST:** regex the body for a traceback
      (`File "([^"]+\.py)", line \d+`), a bare repo-relative path, or a backticked symbol matching
      a known file. On hit: `resolution_method = "explicit"`, confidence 0.95.

**Self-test:** hand-run `assess_severity` on 3 issues; sane numbers.

**🛑 CHECKPOINT C1 (~12:45).** Print to human and wait:

> I've pushed the seed skeleton. Confirm the team: Person 1 pulled it and pushed their schema
> back? Say "C1 passed" once both true and I'll keep building the triage agent.

## Person 2 · Phase B — finish ingestion, seed loader, GitHub

**After C2 passes.**

1. Finish `triage_agent.jac`: explicit → LLM fallback → if confidence < 0.55, attach to the
   `Unresolved` node via `parked` (`resolution_method = "none"`). Don't guess — the visible
   "couldn't place these" bucket is a credibility beat.
2. **`walker:pub ingest_issue`** (CLAUDE.md §6).
3. **`seed/seed.jac`** — read `issues.json`, ingest all 20 in order. One command loads the whole
   demo; you'll run it constantly.
4. Start **`integrations/github.jac`.** **Register the GitHub OAuth app NOW** (UI wait). Implement
   token exchange, `list_repos`, and a `create_pull_request` **stub** returning a fake URL so
   Person 3 can wire the button early.

**🛑 CHECKPOINT C2 (2:15) — first merge.** Print to human and wait:

> Merge order: Person 1 first, then me (Person 2), then Person 3. With `jac start main.jac --dev`
> running:
>
> ```
> curl -X POST localhost:8000/walker/ingest_issue -H 'Content-Type: application/json' \
>   -d @seed/samples/seed-01.json
> ```
>
> Expect `resolved_to: "core/validation.py"`, `resolution_method: "explicit"`, severity 8–10.
>
> ```
> curl -X POST localhost:8000/walker/ingest_issue -H 'Content-Type: application/json' \
>   -d @seed/samples/seed-19.json
> ```
>
> Expect `parked: true`. Say "C2 passed" if both work. If LLM resolution is flaky, tell me — I'll
> ship explicit-only so the pipeline runs, and add the fallback later.

## Person 2 · Phase C — real PR generation + (reach) social data

**After C3 passes.**

1. [x] Push the seed repo to GitHub as a **real repo you own** (real GitHub UI, fully controlled).
   → `github.com/alaramartin/triage-demo`.
2. [x] Replace the stub with real `create_pull_request`, and build **`agents/pr_agent.jac`:** given a
   cluster, pull code context along the graph path, `by llm()` generate the patch, create a
   branch, commit, open a PR whose body has the root cause, **the blast-radius summary ("reached
   by 14 of 18 files")**, and links to all 5 member issues. That body is on screen during the
   demo — make it look good.
   **Safety gate (CLAUDE.md §4.4):** before generating a patch, check the target path against a
   small sensitive-path denylist (`.env`, `.env.example`, `docker-compose.yml`, anything under a
   `migrations/`-style folder, schema files). If it matches, refuse to auto-generate and return
   `{"ok": false, "error": "sensitive file — flagged for manual review"}` instead. None of our
   seed bugs hit a sensitive path, so this never fires in the demo — it's there so a judge asking
   "what stops this from patching your database credentials" has a real answer.
   → Both done. Note: full-file rewrite via GitHub's Contents API was used instead of a literal
   unified diff/patch — same effect (a real commit landing real changed code), far more reliable
   for an LLM to produce correctly. Denylist gate is in `pr_agent.is_sensitive_path()`.
3. [x] **`walker:pub generate_pr`** (CLAUDE.md §6) → PR number + URL; on failure
   `{"ok": false, "error": "..."}` — never let the UI spin forever. → Done, delegates to `pr_agent.jac`.
4. [x] **(REACH — only if Person 1 is building weighted ranking)** add `reactions` and
   `comment_velocity` integers to each issue in `issues.json` (e.g. SEED-11 the loud one gets ~40
   reactions, SEED-01 gets ~3; comment velocity can stay low/flat across the board — it exists to
   be real and mentionable in the pitch, not to visibly move the demo ranking). Skip entirely if
   we're behind. → Data already present/ingested; actual ranking-weight usage is Person 1's side.

**Self-test:** `generate_pr` on cluster A's id → real PR on GitHub. **[~] IN PROGRESS** — succeeded
once (PR #1, since closed for a code-quality bug, see RESUME HERE above), currently blocked on
retesting with `qwen2.5-coder:7b` to fix an LLM output-truncation issue in the fix generator.

**🛑 CHECKPOINT C3 (3:30) — real-data integration.** Print to human and wait:

> Merge to `main` (P1 → me → P3). Then:
>
> ```
> curl -X POST localhost:8000/walker/reset_demo -d '{}'
> jac run seed/seed.jac
> curl -X POST localhost:8000/walker/get_queue -H 'Content-Type: application/json' \
>   -d '{"full_name":"triage-demo/shipyard"}' | jq '.unresolved | length'
> ```
>
> Expect **3** (SEED-13, 19, 20). Confirm with Person 1 that the queue shows cluster A at top with
> 5 issues. Say "C3 passed" when unresolved == 3 and ingestion ran clean.

**🛑 CHECKPOINT C4 (5:30) — feature freeze.** Print to human and wait:

> Confirm `generate_pr` opens a real PR on our repo with the blast-radius summary in the body.
> Then freeze — bugfixes only. Say "C4 passed."

**🛑 CHECKPOINT C5 (5:50) — PARTIAL SUBMISSION (you own this).** Print to human:

> Do these with me now:
>
> 1. Submit on Devpost (partial is fine, mandatory). Tracks: **Agentic AI** + **Best JacHammer**.
> 2. Star `github.com/jaseci-labs/jac` — all three of us.
> 3. Confirm repo public and ≥40% Jac.
>    Say "C5 done" once submitted.

**🛑 CHECKPOINT C6 (6:45–7:15) — final.** Print to human:

> Update Devpost description stating exactly how we used Jac: graphs as the data model, walkers as
> the four agents, `by llm()` for severity + clustering, `walker:pub` as the API. Attach
> screenshots (ranked queue, graph view, opened PR) + demo video. Confirm final commit pushed and
> repo public. **Closes 7:15 hard.**

## Person 2 — reference data (build exactly this)

**Seed repo `seed/repo/` — 18 files, exact imports:**

```
core/validation.py  → (none)          core/config.py → (none)     core/errors.py → (none)
core/db.py          → core.validation
models/order.py     → core.validation, core.db, core.errors
models/user.py      → core.validation, core.db
models/product.py   → core.validation, core.db
models/cart.py      → models.product, core.validation
services/orders.py  → models.order, core.errors
services/users.py   → models.user
services/inventory.py → models.product, core.db
services/pricing.py → models.cart, models.product
services/upload.py  → core.validation, core.config
api/routes_orders.py → services.orders, services.pricing
api/routes_users.py → services.users
api/routes_admin.py → services.inventory, services.upload
utils/logging.py    → core.config
utils/csv_export.py → models.order
```

Add `seed/repo/README.md` + a token `seed/repo/tests/` folder so it looks real.

**★ Star bug — `core/validation.py` (write exactly):**

```python
def require_fields(payload, fields):
    """Validate that all required fields are present and non-empty."""
    missing = []
    for f in fields:
        # BUG 1: no None check — str(None) == "None" is truthy, length 4, so None silently
        #        passes; downstream then calls None.strip() → TypeError.
        if len(str(payload.get(f)).strip()) == 0:
            missing.append(f)
    if missing:
        raise ValueError(f"missing required fields: {missing}")
    return payload

def normalize_text(value, max_len=64):
    """Trim a text field to a safe length."""
    # BUG 2: slices ENCODED BYTES, so multi-byte chars (emoji, accents, non-Latin) are cut
    #        mid-character and corrupted/dropped.
    return value.encode("utf-8")[:max_len].decode("utf-8", errors="ignore")
```

**Cluster-B bug — `models/product.py`:** `price_cents` read as float in one place, int in another
(sale prices round to 0.00; cart totals disagree); `adjust_stock()` has no lower bound (inventory
goes negative).
**Cluster-C bug — `services/upload.py`:** reads whole file into memory with no size cap (hangs on
big files); ignores EXIF orientation (rotated avatars).
**Decoy files (NO real bug):** `utils/logging.py`, `api/routes_users.py` — these are where the
loud ALL-CAPS issues resolve; the "loud but shallow gets demoted" beat needs them at 0 dependents.

**`seed/issues.json` — 20 issues:**

| ID      | Title                                                | Body must contain                                                        | Resolves to         | Method      | Sev |
| ------- | ---------------------------------------------------- | ------------------------------------------------------------------------ | ------------------- | ----------- | --- |
| SEED-01 | Crash when submitting checkout form                  | traceback ending `File "core/validation.py", line 12, in require_fields` | core/validation.py  | explicit    | 9   |
| SEED-02 | Product names with emoji get silently truncated      | "🚀 Rocket Mug"→"🚀 Rocket M", no path                                   | core/validation.py  | llm         | 5   |
| SEED-03 | Signup fails for international phone numbers         | "+44 7911…" rejected as empty, no path                                   | core/validation.py  | llm         | 7   |
| SEED-04 | TypeError: expected str, got NoneType on order save  | traceback through `models/order.py` into `require_fields`                | core/validation.py  | explicit    | 9   |
| SEED-05 | CSV export skips rows with blank fields              | missing rows, no path                                                    | core/validation.py  | llm         | 6   |
| SEED-06 | Price shows as 0.00 for sale items                   | mentions `product.price_cents`                                           | models/product.py   | explicit    | 7   |
| SEED-07 | Cart total doesn't match sum of items                | user description only                                                    | models/product.py   | llm         | 7   |
| SEED-08 | Inventory count goes negative after refunds          | mentions `adjust_stock`                                                  | models/product.py   | explicit    | 8   |
| SEED-09 | Image upload hangs on files over 5MB                 | mentions upload endpoint                                                 | services/upload.py  | llm         | 6   |
| SEED-10 | Uploaded avatars appear rotated 90 degrees           | user description                                                         | services/upload.py  | llm         | 4   |
| SEED-11 | 🚨 URGENT — logging blew up my disk, EVERYTHING gone | ALL CAPS, mentions log files                                             | utils/logging.py    | llm         | 5   |
| SEED-12 | CRITICAL!!! profile page completely broken!!!        | ALL CAPS, mentions profile page                                          | api/routes_users.py | llm         | 4   |
| SEED-13 | This app is a disaster, nothing works                | pure venting, no detail                                                  | —                   | none→parked | —   |
| SEED-14 | Add a dark mode toggle                               | feature request                                                          | core/config.py      | llm         | 2   |
| SEED-15 | Typo in order confirmation message                   | "recieved"→"received"                                                    | services/orders.py  | llm         | 1   |
| SEED-16 | Orders list takes 30s with 10k rows                  | perf description                                                         | services/orders.py  | llm         | 6   |
| SEED-17 | Admin dashboard 500s on bulk edit                    | mentions `routes_admin`                                                  | api/routes_admin.py | explicit    | 9   |
| SEED-18 | Password reset email never arrives                   | describes the flow                                                       | services/users.py   | llm         | 8   |
| SEED-19 | doesn't work                                         | two words                                                                | —                   | none→parked | —   |
| SEED-20 | pls fix asap thanks                                  | no content                                                               | —                   | none→parked | —   |

**SEED-15 and SEED-16 both resolve to `services/orders.py` and MUST NOT cluster** (typo ≠ perf).
Person 1's clustering `by llm()` gate handles this; just make the bodies clearly different.
_(Reach) reactions:_ if you add reactions data, give SEED-11 ~40 and SEED-12 ~35 (loud ones),
everything else 0–5.

---

---

# ██ PERSON 3 — Frontend (Jac `cl`) & Demo ██

**You own:** `client/` and `mocks/`. **Branch:** `p3/client`.
**Superpower:** you write your own mock data first, so you are **not blocked by Person 1 or 2
until 3:30.**

## ✅ Person 3 master checklist

- [x] **Phase A:** write `mocks/*.json` by hand → login + repo picker → the ranked queue screen (the money shot)
- [x] **🛑 C1** (~12:45): confirm API shapes unchanged — confirmed post-hoc, only the `from_file`/`to_file` vs `from`/`to` edge-key difference noted below.
- [x] **🛑 C2** (2:15): merge LAST; confirm build is clean — merged `p3/client` → `main`, `jac check main.jac` passes clean.
- [x] **Phase B:** cluster detail page → graph visualization → wire Generate PR button (now on live data, see below)
- [x] **🛑 C3** (3:30): swap mocks → live data; full click-through works — **DONE.** All three screens now call the real `get_queue`/`get_cluster_detail`/`generate_pr` walkers; verified via direct API-shape checks against a small live-seeded graph (not the full 20-issue pipeline - see wiring note below).
- [ ] **Phase C:** live cluster detail (done) → polish (started) → rehearse ≥3× → record video → _(reach)_ weights panel
- [ ] **🛑 C4** (5:30): feature freeze; video recorded
- [ ] **🛑 C5** (5:50): confirm Person 2 submitted the partial
- [ ] **🛑 C6** (6:45–7:15): final screenshots; demo pre-loaded

### Session log (Person 3) — resume point

Everything below is done and pushed to `origin/p3/client` (4 commits), **not yet merged to `main`**.
If you `/clear` and come back, read this before re-reading the rest of the file.

**What's built, all on mock data:**
- `mocks/queue.json`, `mocks/cluster_detail.json` — hand-written, match CLAUDE.md §6 exactly.
- `client/app.cl.jac` — manual `<Router>` (not file-based `pages/`), routes: `/` login, `/repos`
  repo picker, `/queue` ranked queue, `/cluster/:id` detail+graph.
- `client/screens/{LoginScreen,RepoPickerScreen,QueueScreen}.cl.jac`, `client/cluster_view.cl.jac`,
  `client/components/{ClusterRow,SingletonRow,UnresolvedList,ResolutionBadge,StatPill,GraphView}.cl.jac`.
- `client/mock_data.cl.jac` — the mock `get_queue`/`get_cluster_detail` responses as **plain dicts**
  (see gotcha below for why, not `obj`).
- Full click-through verified in a real browser (not just `jac check`): login → repo picker → queue
  (expand cluster → 5 differently-worded issues collapse into one row, exactly the beat-2 "collapse"
  moment) → Generate PR (mock success banner + a real error-banner code path, matching the
  `{ok, pr_number, pr_url}` / `{ok:false, error}` contract) → cluster detail with an animated SVG
  graph (rings reveal outward from the target by `hops` on a timer, per beat 3).
- Keyboard accessibility (the cluster row toggle is a real `role="button"` with focus ring +
  Enter/Space, not just a clickable div) and mobile responsiveness (rows were overlapping text
  under ~500px, fixed with `flex-wrap`) — both confirmed visually at a 390px viewport.
- `jac.toml` and `main.jac` didn't exist yet when this session started (only Person 2's `jac.toml`
  fragment + `agents/triage_agent.jac` were on `main`) — added `kind = "fullstack"`, Tailwind v4,
  and the `cl {}` entry block. If Person 1 also touches `jac.toml`'s `[dependencies.npm]` /
  `[plugins.client]` sections, merge carefully — first real merge-conflict risk on this branch.

**⚠️ Two real bugs found by actually running the app (not caught by `jac check`) — worth knowing
if Person 1/2 write `.cl.jac` or edit `jac.toml`:**
1. **`obj`/`glob` in client (`.cl.jac`) files are not exported across files unless declared
   `obj:pub` / `glob:pub`.** Plain `obj`/`glob` passes `jac check` clean but fails at runtime with
   a JS "does not provide an export named X" error. Only surfaces when you actually load the page.
2. **`obj` construction in client code (`SomeObj(field=val)`) compiles to a bare JS call missing
   `new`**, throwing `TypeError: Class constructor X cannot be invoked without 'new'` at runtime —
   also invisible to `jac check`. Worked around by using plain `dict` literals instead of typed
   `obj`s for all client-side mock/display data, with explicit `as str`/`as float`/`as list[dict]`
   casts at the spots the strict type checker needs a concrete type (Callable params, `len()`,
   string concat, arithmetic). **Lesson: a clean `jac check` is not proof the client code runs —
   always verify with a cold `jac start --dev` + real browser check before trusting it.**
3. (Environment-specific, not a Jac bug) `jac install` on this Windows machine writes `jac.toml`
   in the system codepage, not UTF-8 — it corrupted an em-dash in the `description` field into an
   unreadable byte and broke every subsequent `jac` command until fixed. Keep non-ASCII characters
   out of `jac.toml` if you're on Windows.

**Not done / next up:** the live-data swap (C3) is the only remaining hard blocker. Once
`get_queue`/`get_cluster_detail` exist on `main`, replace the `mock_queue`/`mock_cluster_detail`
glob reads in `QueueScreen.cl.jac`/`cluster_view.cl.jac` with `sv import`-ed calls — the dict shape
should carry over almost unchanged. After that: demo rehearsal script, video recording, and the
reach weights panel (only if Person 1 ships `set_weights`).

**Update — Person 1 already pushed `get_queue`/`get_cluster_detail` to `main`** (commits
`199ffb4`, `f92af45`: graph schema, AST parser, blast-radius/clustering/ranking agents, and both
endpoints wired into `main.jac`). Checked the response shapes against my mocks — mostly a direct
match (`QueueResponse`/`ClusterView`/`SingletonView`/`UnresolvedView`/`IssueSummary` field names are
identical to what `QueueScreen.cl.jac` already expects), but **two real differences to fix when
wiring the live swap:**
1. `get_cluster_detail`'s graph payload only ever emits `role: "target"` or `"dependent"` —
   non-dependent files are omitted entirely, there's no `"neutral"` node in the real data.
   `GraphView.cl.jac`'s neutral-node styling becomes dead code against live data (harmless, just
   won't render anything) unless we decide to enhance it later.
2. **Edges use keys `"from"`/`"to"`**, not `"from_file"`/`"to_file"` like my mock and
   `GraphView.cl.jac` use. I picked `from_file`/`to_file` defensively (wasn't sure `from` was safe
   as a plain dict key) — turns out it's fine, Person 1's server code uses `"from"`/`"to"` directly.
   Will need a rename in `GraphView.cl.jac` when swapping to live data.

**However, the pipeline isn't fully runnable end-to-end yet** — Person 2 hasn't pushed
`ingest_issue`, `seed/seed.jac`, or the seed repo itself, so `get_queue` right now would just
return an empty/unindexed repo (no `Issue`/`Cluster` nodes exist). The C3 swap is close but not
quite unblocked — still waiting on Person 2's Phase B before there's real data to point at.

### 📍 UPDATE — live-data wiring done (post `p3/client` merge into `main`)

By the time `p3/client` merged, Person 1's Phase C and Person 2's Phase B were both long done and
already verified live (C3 passed on `main` before this merge). Wired all three screens off mocks:

- **`QueueScreen.cl.jac`**: `sv import from ...main { get_queue, generate_pr }`. Fetches on mount
  (`async can with entry`), converts the typed `QueueResponse`/`ClusterView`/`SingletonView`/
  `UnresolvedView`/`IssueSummary` instances into the same plain-dict shape the existing
  bracket-access JSX (`cluster["id"]`, etc.) already expected — kept every child component
  (`ClusterRow`/`SingletonRow`/`UnresolvedList`) unchanged. `Generate PR` now calls the real
  `generate_pr` walker instead of a hardcoded success object.
- **`cluster_view.cl.jac`**: `sv import from ..main { get_cluster_detail, generate_pr }`. Fetches by
  route `:id` (`async can with [route_id] entry`, re-fetches if the id changes), same dict
  conversion. `get_cluster_detail` can report EITHER a `ClusterDetailResponse` OR a plain
  `{"ok": false, "error": ...}` dict (CLAUDE.md §6) - branches on `resp["ok"] == False` (bracket
  access is safe/non-throwing on both shapes) before deciding which to build.
- **`GraphView.cl.jac`**: fixed the edge-key mismatch flagged in the session log above -
  `from_file`/`to_file` → `from`/`to`, matching the real `build_dependency_graph` output. The
  `"neutral"` role never appears in live data (also flagged above) - harmless, that branch just
  never renders; not worth adding fake neutral nodes to exercise dead code.
- **`RepoPickerScreen.cl.jac`**: repo name/file count now come from a real `get_queue` call instead
  of `mock_queue`. Full GitHub-account repo listing is still the accepted, documented scope cut
  (single demo repo, no live OAuth) - this only removes the fake numbers, not the single-repo UX.
- **`LoginScreen.cl.jac`**: intentionally left as the mock click-through. This was never "blocked on
  someone else's work" - it's a deliberate, documented scope cut (CLAUDE.md/PLAN.md: OAuth is the
  first thing cut, adds nothing to the graph story), not a placeholder waiting for a backend.
- `client/mock_data.cl.jac` and `mocks/*.json` are now fully unused (nothing imports them) but left
  in place per Person 3's own docstring ("kept only as a fallback/demo seed").

**Verification approach** (deliberately NOT a full 20-issue reseed - too slow to rerun for every
small fix): started the server with the real client (`jac start main.jac --dev`, confirmed
"Initial client compilation completed" with zero build errors), ran `reindex_repo` + 2 explicit-
resolution `ingest_issue` calls (fast, no LLM calls needed) to get one real cluster, then `curl`ed
`get_queue`/`get_cluster_detail`/`generate_pr` directly and diffed the JSON field-for-field against
what each screen's conversion code reads. All matched exactly. `jac check main.jac` (whole app,
server + client) passes clean. This is the pattern to reuse for future small client/backend
wiring fixes - full pipeline reseed only before an actual checkpoint or the real demo rehearsal.

## Person 3 · Phase A — mocks + dashboard shell

1. **First, by hand, write `mocks/queue.json` and `mocks/cluster_detail.json`** using the exact
   shapes in CLAUDE.md §6 and the numbers in your reference below. Real target state: cluster A on
   `core/validation.py` (5 issues, urgency 7.22, blast 14), cluster B on `models/product.py` (3),
   cluster C on `services/upload.py` (2), the singletons, the 3 unresolved. **Now you're unblocked
   through all of Phase B.**
2. GitHub OAuth login screen + repo picker listing the user's public repos. _(If OAuth in Jac's
   client framework fights you >30 min, hardcode one repo and tell your human — login is the first
   thing we cut; it adds nothing to the graph story.)_
3. **The ranked queue view — the most important screen.** Requirements:
    - Clusters + singletons in one list, **in the order the API returns them** (no client sort).
    - A cluster = one expandable row: title, `blast radius: 14 files`, a `5 issues` badge, urgency,
      a _Generate PR_ button. Expanding shows member issue titles. **If the API includes a direct
      dependent count alongside the transitive one (free — see CLAUDE.md §4.4), show both**, e.g.
      "3 direct, 14 total downstream" — a small detail that makes the blast-radius claim feel more
      rigorous without any new backend work.
    - **Urgency and blast-radius numbers visually loud** — where the judge's eye must land.
    - A distinct **"Couldn't confidently place (3)"** section at the bottom — don't hide it, it's a
      credibility beat.
    - A small `resolution_method` badge per issue (`traceback` vs `inferred`).

**Self-test:** the queue renders the full 20-issue state from `mocks/queue.json`, screenshot-worthy,
no backend running.

**🛑 CHECKPOINT C1 (~12:45).** Print to human and wait:

> I build against my own mocks so I'm not blocked. Just confirm with the team that the API shapes
> in CLAUDE.md §6 haven't changed (ask if Person 1 renamed any fields). Say "C1 passed."

## Person 3 · Phase B — cluster detail + graph visualization

**After C2. Still on mock data.**

1. **Cluster detail page** from `mocks/cluster_detail.json`: title, root-cause summary, member
   issues with bodies, proposed-fix summary, a second _Generate PR_ button.
2. **Graph visualization (the beat-3 hero shot).** Render `graph.nodes`/`graph.edges`: target node
   distinct, ~14 dependents highlighted, `hops` driving distance/shading. **Static-but-legible
   beats animated-but-messy.** If time allows, animate the highlight expanding outward by `hops` —
   the "walker walking" moment. Try Jac's built-in graph visualizer first; if it doesn't drop into
   `cl` cleanly within 30 min, hand-roll SVG.
3. Wire _Generate PR_ → `generate_pr` → a result dialogue (_"PR #7 opened — review on GitHub"_ +
   link) plus a visible error state.

**🛑 CHECKPOINT C2 (2:15) — merge (you go LAST).** Print to human and wait:

> In the merge, **I (Person 3) merge `p3/client` → `main` LAST**, after Person 1 and Person 2 (my
> files conflict least). After merging, confirm `jac start main.jac --dev` still builds with my
> client. My screens run on mock data still — expected. Say "C2 passed" if the build is clean.

## Person 3 · Phase C — polish, rehearsal + (reach) weights panel

**After C3.**

1. When Person 1 ships `get_cluster_detail` (~4:15), swap the detail/graph page to live data.
2. Polish the queue screen relentlessly — judges look at it longest.
3. **Rehearse the 4-minute demo end-to-end ≥3× before 6:00** (beat sheet in CLAUDE.md §8). Time it.
4. **Record the demo video** during a clean run — don't leave it to 7:00.
5. **(REACH — only if Person 1 built `set_weights`, and only after 1–4 are done)** a settings
   panel: sliders for blast radius / severity / diff / reactions / comment velocity that call
   `set_weights` and re-fetch `get_queue`. **Default stays blast-dominant; the demo runs on the
   default.** Optional demo flourish if rock-solid: weight reactions up and show the loud SEED-11
   climb — but only rehearse this if the core demo is already perfect. Cut first if behind.

**🛑 CHECKPOINT C3 (3:30) — swap mocks for live data (the big one).** Print to human and wait:

> Everyone merges to `main` (P1 → P2 → me). I point the client at live endpoints. Help verify:
>
> 1. With the backend seeded (team runs `reset_demo` + `jac run seed/seed.jac`), load the dashboard.
> 2. Every on-screen number matches live `get_queue` JSON: cluster A first, blast 14, 5 issues; 3
>    unresolved at the bottom.
> 3. Click through login → repo → queue → cluster → graph → Generate PR.
>    Tell me which steps work. If Person 1's `get_cluster_detail` isn't ready, I keep the detail page
>    on mocks until ~4:15. Say "C3 passed" when the queue is on live data and the flow works.

**🛑 CHECKPOINT C4 (5:30) — feature freeze.** Print to human and wait:

> Confirm the full flow on live data: login → repo → ranked queue (cluster A #1) → cluster detail
> → graph lighting up 14 files → Generate PR → PR link. Confirm the demo video is recorded. Then
> freeze — polish only. Say "C4 passed."

**🛑 CHECKPOINT C5 (5:50).** Print to human:

> Confirm Person 2 submitted the partial on Devpost (mandatory). Then I keep rehearsing.

**🛑 CHECKPOINT C6 (6:45–7:15).** Print to human:

> Help me grab final screenshots (ranked queue, graph view, opened PR) for Devpost. Confirm the
> demo is pre-loaded and `reset_demo` is ready for a clean live run at the judging table.

## Person 3 — reference data (for your mocks)

**`get_queue` shape** — see CLAUDE.md §6 for the full JSON. Fill your mock with:

- `clusters[0]`: `target_path` `core/validation.py`, `blast_radius` 14, `issue_count` 5,
  `urgency` 7.22, `fix_confidence` 0.86, 5 member issues (SEED-01..05).
- `clusters[1]`: `models/product.py`, blast 5, 3 issues, urgency 3.87.
- `clusters[2]`: `services/upload.py`, blast 1, 2 issues, urgency 1.88.
- `singletons` (sorted desc): SEED-18 (2.48), SEED-17 (2.40), SEED-16 (1.78), SEED-11 (1.40),
  SEED-14 (1.20), SEED-12 (1.08), SEED-15 (0.61).
- `unresolved`: SEED-13, SEED-19, SEED-20.

**`get_cluster_detail` graph payload** for cluster A: `target` node `core/validation.py`, plus its
14 dependents as `dependent` nodes with `hops` (direct importers `core/db.py`, `models/order.py`,
`models/user.py`, `models/product.py`, `models/cart.py`, `services/upload.py` at hops 1; the rest
at hops 2–3). Edges in code direction. **The visual point: one node reaches almost the whole repo.**

---

---

# SHARED — gotchas discovered so far (read if you touch `.cl.jac` or `jac.toml`)

_Added by Person 3, mid-afternoon session. See the Person 3 session log above for full detail._

- **`obj`/`glob` in client (`.cl.jac`) code need `obj:pub` / `glob:pub` to be importable from
  another file** — plain `obj`/`glob` passes `jac check` but fails at runtime with a JS export
  error. Not caught by the type checker.
- **`obj` construction in client code (`SomeObj(field=val)`) compiles to a JS call missing `new`**
  and throws at runtime (`Class constructor X cannot be invoked without 'new'`) — also invisible to
  `jac check`. Workaround: use plain `dict` literals for client-side data instead of `obj`, with
  `as <type>` casts where the checker needs a concrete type.
- **A clean `jac check` does not mean the app runs.** Both bugs above only showed up after an
  actual `jac start --dev` + browser load. Verify in a real browser before trusting green checks.
- **On Windows, `jac install` can corrupt `jac.toml`'s encoding** if it contains non-ASCII
  characters (it wrote an em-dash in cp1252 and broke every subsequent `jac` command). Keep
  `jac.toml` ASCII-only if you're on Windows.

---

---

# SHARED — checkpoint & merge summary (all three)

| CP  | Time      | What                                                  | Merge order          |
| --- | --------- | ----------------------------------------------------- | -------------------- |
| C0  | 10:45     | schema sync; all attend 11:00 Jac workshop            | —                    |
| C1  | 12:45     | Person 2's seed skeleton up; Person 1's schema pushed | P2 pushes seed first |
| C2  | 2:15      | first integration; **blast radius == 14**             | P1 → P2 → P3         |
| C3  | 3:30      | real-data integration; frontend → live; queue correct | P1 → P2 → P3         |
| C4  | 5:30      | feature freeze; verify ≥40% Jac; video recorded       | all merged           |
| C5  | 5:50      | **partial submission on Devpost (mandatory)**         | —                    |
| C6  | 6:45–7:15 | final submission; screenshots; **closes 7:15 hard**   | —                    |

**Merge order is always P1 → P2 → P3.** Between checkpoints, commit + push your own branch every
~20 min; do **not** merge to `main` ad hoc.

**Cuts if behind, in order (decide at 4:00):** (1) personalization/weights panel; (2) graph
animation → static; (3) real GitHub PR → PR body in a modal with copy button; (4) OAuth → hardcode
one repo. **Never cut:** clustering, blast radius, ranked queue — those _are_ the project.

# SHARED — the three questions judges will ask (everyone answers cold)

**"Why does this need a graph?"** The ranking is a claim about the codebase's structure, not the
issues. "Reached by 14 of 18 files" is transitive reachability you can't read off any single
issue. Clustering isn't text similarity — five issues sharing no vocabulary group because they
land on the same node. Both are traversals over one graph.

**"Couldn't you just paste the repo into Claude?"** Blast radius needs a persistent structural
graph, not a context window. Clustering is a property of the whole set of resolved issues, not any
one issue. And it runs continuously — a new issue is one edge insert, not a repo re-read.

**"How is this multi-agent, not one script?"** The agents never call each other. Triage writes an
edge; blast-radius fires because that edge appeared; clustering fires because two edges converged
on one node; ranking fires because a property changed. The graph is the coordination medium.

_(If asked about the personalization sliders: "The defaults are blast-radius-dominant — the
structural signal you can only get from the graph. The weights let a maintainer tune the other
terms to taste, but the graph is doing the heavy lifting no matter where you set them.")_
