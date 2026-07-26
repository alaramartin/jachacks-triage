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

- [ ] **Phase A:** node schema → AST parser → `reindex_repo` → `reset_demo` + `debug_blast` → blast-radius agent
- [ ] **🛑 C1** (~12:45): confirm Person 2's seed repo is in (`find` == 18 files)
- [ ] **🛑 C2** (2:15): first merge; **blast radius of validation.py MUST == 14**
- [ ] **Phase B:** clustering agent → ranking agent → `get_queue`
- [ ] **🛑 C3** (3:30): real-data integration; full ranked queue correct
- [ ] **Phase C:** `get_cluster_detail` (with graph payload) → performance → _(reach)_ weighted ranking
- [ ] **🛑 C4** (5:30): feature freeze; verify ≥40% Jac
- [ ] **🛑 C5** (5:50): confirm Person 2 submitted the partial

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

- [ ] **🚨 TASK ZERO** (by 12:45): push `seed/repo/` skeleton — 18 files, correct imports. **P1 is blocked on this.**. Make sure to .gitignore the seed/ folder so that it does not dilute the Jac percentage in this repo, and tell the human to create a separate git repo for the seed/demo repo./usage
- [ ] **Phase A:** flesh out seed repo + bugs → `issues.json` → start triage agent
- [ ] **🛑 C1** (~12:45): confirm skeleton is up + Person 1's schema is back
- [ ] **🛑 C2** (2:15): first merge; ingestion resolves SEED-01, parks SEED-19
- [ ] **Phase B:** finish triage (LLM fallback + threshold) → `ingest_issue` → `seed.jac` → GitHub OAuth setup
- [ ] **🛑 C3** (3:30): real-data integration; 3 unresolved
- [ ] **Phase C:** real `generate_pr` + `pr_agent` → _(reach)_ add `reactions` to seed issues
- [ ] **🛑 C4** (5:30): feature freeze; real PR opens
- [ ] **🛑 C5** (5:50): **YOU submit the partial** (mandatory)
- [ ] **🛑 C6** (6:45–7:15): final submission

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

1. Push the seed repo to GitHub as a **real repo you own** (real GitHub UI, fully controlled).
2. Replace the stub with real `create_pull_request`, and build **`agents/pr_agent.jac`:** given a
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
3. **`walker:pub generate_pr`** (CLAUDE.md §6) → PR number + URL; on failure
   `{"ok": false, "error": "..."}` — never let the UI spin forever.
4. **(REACH — only if Person 1 is building weighted ranking)** add `reactions` and
   `comment_velocity` integers to each issue in `issues.json` (e.g. SEED-11 the loud one gets ~40
   reactions, SEED-01 gets ~3; comment velocity can stay low/flat across the board — it exists to
   be real and mentionable in the pitch, not to visibly move the demo ranking). Skip entirely if
   we're behind.

**Self-test:** `generate_pr` on cluster A's id → real PR on GitHub.

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
- [ ] **🛑 C1** (~12:45): confirm API shapes unchanged — not yet confirmed with team (no chat check-in done)
- [ ] **🛑 C2** (2:15): merge LAST; confirm build is clean — **not merged to `main` yet**, still on `p3/client`
- [x] **Phase B:** cluster detail page → graph visualization → wire Generate PR button (all on mock data)
- [ ] **🛑 C3** (3:30): swap mocks → live data; full click-through works — **blocked on Person 1's `get_queue`/`get_cluster_detail` and Person 2's seeded pipeline landing on `main`**
- [ ] **Phase C:** live cluster detail (blocked) → polish (started) → rehearse ≥3× → record video → _(reach)_ weights panel
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
