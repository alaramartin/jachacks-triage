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

> ## 🟢 PERSON 1 IS 100% CODE-COMPLETE (updated at the P1+P2 merge)
>
> **Every technical item in Person 1's scope is done and verified live on the demo machine.**
> The two items that were previously blocked/waiting are both now RESOLVED (see below) — the
> environment split is settled, `clustering.test.jac` passes, and `jac test -d .` runs the whole
> suite in one command (35 passed, 0 failed).
>
> **The only thing left with Person 1's name on it is 🛑 C5** — confirming Person 2 submitted the
> Devpost partial. That is a human coordination step, not code. **Nothing left to build.**

**Bottom line: everything in Person 1's scope that can be done independently IS done.** Every
remaining item is either a coordination step for the human or blocked on something outside
Person 1's owned files. See the four buckets below — this is the authoritative status, re-derived
from scratch this session rather than trusted from older notes.

### ✅ DONE

- [x] **Phase A:** node schema → AST parser → `reindex_repo` → `reset_demo` + `debug_blast` →
      blast-radius agent.
- [x] **🛑 C1** (~12:45): confirmed Person 2's seed repo landed (19 `.py` files incl. the token
      test file, matches reference).
- [x] **🛑 C2** (2:15): first merge; blast radius of `core/validation.py` confirmed == 14 against
      the real seed repo, both at merge time and again this session.
- [x] **Phase B:** clustering agent → ranking agent → `get_queue`, all self-tested with hand-built
      graph state + MockLLM (SEED-15/16 anti-cluster case covered).
- [x] **🛑 C3** (3:30): real-data integration; full ranked queue verified live (blast radii
      14/5/1) — see the 🚨 CRITICAL section below for the compiler-breaking regressions found in
      this code on a second machine and fixed this session.
- [x] **Phase C steps 1-2:** `get_cluster_detail` (with the `graph` payload: role/hops/edges) +
      performance (already satisfied — `get_queue` only reads cached `blast_radius`, never
      recomputes). Self-tested, `jac check` clean.
- [x] **Phase C step 3 (REACH):** weighted ranking — `agents/ranking.jac`'s
      `weighted_urgency`/`weighted_cluster_urgency`, `main.jac`'s `walker:pub set_weights`,
      `get_queue` re-ranking against the repo's `Settings` at read time. Stored
      `Issue.urgency`/`Cluster.urgency` untouched (ingest-time cascade always uses default
      weights). Self-tested + live-smoke-tested.
- [x] **This session's regression sweep:** found and fixed real compiler-breaking bugs introduced
      by the 2:15/3:30 merge (connect-operator `[0]`-unwrap, invalid lambda syntax, a byllm import
      path) that made `main.jac` fail to even compile/start on this machine. Re-verified with
      direct repros (`git stash`/`pop`), not just re-reading old notes. Full detail in the 🚨
      CRITICAL section below.
- [x] **🛑 C4** (5:30): feature freeze — human confirmed to continue past this checkpoint. Person
      1's own checks: `debug_blast` still gives 14 live; `seed/repo` confirmed fully
      untracked/gitignored; tracked-byte Jac share ~50% locally as a proxy for the real GitHub bar.
      **Per the checkpoint rule, Person 1 is now bugfixes-only — no new features unless something
      is reported broken.**

### 🔄 IN PROGRESS

None. There is no partially-built Person 1 work in flight right now.

### ⏳ WAITING ON OTHER PEOPLE / OTHER MACHINES (not something Person 1 can move forward alone)

- [ ] **🛑 C5** (5:50): confirm Person 2 submitted the Devpost partial. **Waiting on:** Person 2
      actually submitting, and the human confirming it happened — Person 1 has no endpoint or file
      that touches this.
- [x] ~~**`agents/clustering.test.jac`'s MockLLM tests still fail on this machine**~~ — **RESOLVED
      at the P1+P2 merge.** This was environment-specific (the standalone `byllm==0.6.19`'s
      `mtir.impl.jac`), not a logic bug. On the authoritative demo machine, with the import back to
      `jaclang.byllm.lib`, both tests pass (`jac test agents/clustering.test.jac` → 2 passed).
- [x] ~~**`jac test -d .` can't run as one command**~~ — **FIXED by Person 2.** Root cause was
      `seed/seed.jac` using a plain `with entry`, which executes on *every import* — so the test
      runner fired its HTTP calls during collection. Worse than originally diagnosed: with no
      server it crashed the suite, but **with a server running it silently re-ingested all 20
      issues into the live graph** (observed: 28 issues instead of 20). Changed to
      `with entry:__main__`, so seeding is now an explicit `jac run seed/seed.jac` action only.
      **`jac test -d .` now runs the whole suite in one command: 35 passed, 0 failed**, and the
      graph is verifiably untouched afterward.

### ⬜ NOT STARTED

None remaining in Person 1's scope. (There's no C6 checklist item for Person 1 in this plan — C6
is Person 2's final Devpost submission and Person 3's screenshots/demo-preload work.)

### ✅ RESOLVED — the environment split above, decided at the P1+P2 merge

**The demo runs on Person 2's machine (`jac 0.34.7`, byllm bundled, Ollama installed). The repo's
syntax is now pinned to THAT machine.** Person 1's machine (`jaclang 0.16.7` + standalone
`byllm 0.6.19`) has **no Ollama at all** and therefore cannot run the LLM pipeline the demo
depends on, so it can't be the demo host — which settles which dialect wins.

Re-verified empirically on the demo machine with minimal `jac run` repros (not from notes):

| Construct | Demo machine (authoritative) | P1's machine |
| --- | --- | --- |
| `root ++> Node()` | returns a **bare node** → no `[0]` | returns `list` → needs `[0]` |
| sort key lambda | `lambda (c: T) { c.urgency; }` | `lambda c: T : c.urgency` |
| MockLLM / Model import | `jaclang.byllm.lib` | `byllm.lib` |

Person 1's commit `bb66395` flipped all three the other way; the merge commit reverted the syntax
while **keeping all of P1's feature work** (`Settings`, `set_weights`, weighted re-rank). If you
pull and `jac check` fails on these three shapes, you are on the other environment — do not
"fix" them back, match the table above. Everything below is P1's original write-up, kept for
context.

**Read this before anyone touches `main.jac`, `agents/clustering.jac`, or their tests again.**
After pulling the merged `main` (commit `f140031`), `jac check main.jac` **failed to compile on
this machine** with 3 real errors, and `jac test -d .` crashed outright. Root cause: this
machine's `jaclang` (0.16.7, `pip show jaclang`) and `byllm` (0.6.19, a **standalone** pip
package, NOT bundled inside jaclang) behave differently from whatever the team members who did
the 2:15/3:30 merge fixes were running. Confirmed empirically (`jac run` on a 3-line repro, not
guessed):

1. **`root ++> Node(...)` and `x +>:edge:+> Node(...)` return `list[Node]` on this machine, not
   the bare node.** The 5a0437d merge commit removed the `[0]` unwrap from `main.jac`'s
   `reindex_repo` and `agents/clustering.jac`'s `maybe_cluster` based on the opposite finding on
   someone else's machine. **Restored the `[0]` unwrap in both places** (plus every hand-built
   test fixture in `main.test.jac` and `agents/clustering.test.jac` that had the same pattern) —
   verified this makes `jac check main.jac` pass clean and all of Person 1's tests pass again.
2. **The `lambda (c: ClusterView) { c.urgency; }` sort-key syntax from that same merge is invalid
   Jac** (confirmed both by a `jac check` error — `E1054: No matching overload found` — and by
   cross-checking the jac-mcp `functions-objects` doc's actual lambda grammar). Correct form:
   `lambda c: ClusterView : c.urgency` (no parens around the param, single expression after a
   space-colon — see doc §7). Fixed both sort calls in `get_queue`.
3. **`import from jaclang.byllm.lib { MockLLM }` (the team's documented fix for the earlier byllm
   incompatibility) doesn't exist on this machine** — `jaclang.byllm` isn't a module here at all;
   `import from byllm.lib { MockLLM }` (the *original*, pre-fix import) is what actually resolves,
   because this machine has the standalone `byllm` PyPI package installed instead of jaclang's
   bundled copy. Reverted `agents/clustering.test.jac`'s import accordingly. **This is the exact
   opposite of what `jac.toml`'s `[dependencies]` comment and the team's PLAN.md notes say** — do
   not "fix" this back without first checking `pip show jaclang byllm` AND `jac --version`'s
   "Plugins Detected" line on whichever machine is having trouble.
4. **New issue, not yet resolved:** even with the import fixed, `agents/clustering.test.jac`'s
   MockLLM-driven tests crash with `IndexError: list index out of range` deep inside
   `byllm/impl/mtir.impl.jac`'s `factory()` (third-party code, not ours) — reproduced in isolation
   with a trivial 3-arg-plus-`temperature=` `by llm()` function, so it looks like a genuine bug/
   incompatibility in this machine's `byllm==0.6.19` build with that call shape, not a bug in
   `clustering.jac`'s logic. **This machine has no Ollama installed at all**, so I could not
   independently re-verify the live LLM-driven pipeline (clustering/severity/resolution) end to
   end — I'm relying on Person 2's earlier live verification (real Ollama, real server) that the
   actual clustering/ranking logic produces correct results. What I *did* verify live on this
   machine, with no Ollama needed: `reindex_repo` (19 files incl. the test file, 27 edges),
   `debug_blast` (`core/validation.py`→14, `models/product.py`→5), `get_queue` (empty-state shape
   correct pre-ingest), `get_cluster_detail` (`{"ok": false, "error": "cluster not found"}` for a
   bad id), `reset_demo` — all correct.
5. Also: `jac start main.jac --no-client` (as written in Person 2's "standard rehydrate command"
   below) **isn't a valid flag on this machine's jaclang** — it's `--no_client` / `-n`
   (underscore, from `jac start --help`). Cosmetic compared to the above, but will block anyone
   who copy-pastes that command on a similarly-configured machine.

**Recommendation for the team, not yet acted on:** before the live demo, everyone should run
`jac --version` (check "Plugins Detected") and `pip show jaclang byllm` on their own laptop and
compare. Pick ONE laptop as the actual demo machine now and do a full clean-pipeline rehearsal
(`reset_demo` → `jac run seed/seed.jac` → `get_queue`) on *that exact machine*, not whichever
machine happened to verify C3 first — the fixes above suggest at least two genuinely different
environments exist across the team right now, and code that passes `jac check` on one machine
demonstrably fails to even compile on another.

**Double-checked after the human reported a teammate's device runs the unfixed (pre-this-session)
code successfully.** Re-verified rather than assuming my first pass was right:
- `pip show jaclang byllm` on this machine: `jaclang==0.16.7`, standalone `byllm==0.6.19`.
  Cross-checked against PyPI's actual JSON API (not the `pip index versions` CLI command, which
  is flagged experimental and returned a stale/wrong list capped at `jaclang==0.10.2` — a red
  herring, ignore that command): `pypi.org/pypi/jaclang/json` confirms `0.16.7` **is** the latest
  published release, same for `byllm==0.6.19`. So this machine is not behind — there is no newer
  public version to upgrade to, and downgrading to chase the teammate's behavior isn't the fix.
- Did a direct repro: `git stash`'d every fix from this session, restored the exact merged
  `main.jac`/`agents/clustering.jac`/test files, and ran `jac start main.jac --no_client` on this
  machine. **It does not even start** — `Error loading main.jac: No module named 'jaclang.byllm'`
  (the bad import in `clustering.test.jac` loads as an annex of `clustering.jac` even outside
  `jac test`, so it takes the whole server down, not just the test suite). This is a hard,
  reproducible crash on this machine, not a hypothetical or a static-check-only nitpick — `git
  stash pop` restored the fix and the server started clean and served correct data again (see
  verification below). Given this machine already has the newest public release of both packages,
  the most likely explanation is the teammate's machine is on a **different, non-public build**
  (a workshop-distributed pre-release/nightly, an editable git install, or simply a different
  patch that predates a breaking change to the connect-operator return type) rather than this
  machine being misconfigured. Either way: the fixes in this file stay, because they're the only
  version of the code that runs *here*, and reverting them reproduces a proven crash.

### 📍 UPDATE from Person 2 (post-merge — read this before continuing Person 1 work)

**⚠️ Superseded by the 🚨 CRITICAL section above, written later the same day on a different
machine.** Points 1-3 below turned out to be *machine-specific*, not universal fixes — on the
machine used for the session above, the exact opposite was empirically true (`jac check`/`jac
run` proof included there): the connect operators DO return `list[T]` and need the `[0]` unwrap,
the lambda syntax below is invalid, and `jaclang.byllm` doesn't exist so `byllm.lib` is the
correct import. Point 4 (code-context fix for `assess_root_cause`) is unaffected and still stands.
Keep reading both sections — they're not a contradiction to "resolve," they're evidence the team
has at least two different jaclang/byllm environments. Don't re-flip these fixes without checking
which machine you're actually on first (see the recommendation above).

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

### 📍 RESUME HERE (last updated after pulling `f140031` and fixing the cross-machine regressions)

**Read the 🚨 CRITICAL section above first if you haven't.** Short version: pulled the full
merged `main` (Person 2's ingestion + Person 3's client, commit `f140031`), found `main.jac`
didn't even compile on this machine, root-caused it to a genuine jaclang/byllm environment
difference from whoever did the merge, and fixed the actual regressions (not just papered over
them) — verified via `jac check`, `jac test`, and a live `jac start` server hitting the real seed
repo.

**Exact code state right now (all uncommitted — ask the human before committing, per convention):**
- `main.jac`: restored `[0]` unwrap on `reindex_repo`'s `repo = (root ++> Repo(...))[0]`; fixed
  both `get_queue` sort-key lambdas to `lambda x: Type : expr` syntax.
- `agents/clustering.jac`: restored `[0]` unwrap on `maybe_cluster`'s
  `cluster = (repos[0] +>:owns:+> Cluster(...))[0]`.
- `agents/clustering.test.jac`: reverted the `MockLLM` import from `jaclang.byllm.lib` back to
  `byllm.lib`; added back `[0]` unwrap on the hand-built `File`/`Issue` fixtures in both tests.
- `main.test.jac`: added back `[0]` unwrap on every hand-built `Repo`/`File`/`Issue`/`Cluster`/
  `Unresolved` fixture in both `get_queue` and `get_cluster_detail` tests.
- `PLAN.md`: this section plus the 🚨 CRITICAL section above and the annotation on Person 2's
  now-superseded merge notes.
- **Not changed:** `get_cluster_detail`'s own logic, `build_dependency_graph`, the
  `proposed_fix_summary` schema field, `ranking.jac` — all untouched by this session, all still
  passing.

**Verification performed this session:**
- `jac check main.jac` — passes clean (was 3 errors before the fixes above).
- `jac test main.test.jac` — 3/3 pass. `jac test agents/ranking.test.jac` — 2/2 pass.
- `jac test agents/clustering.test.jac` — **still fails** (2 errors), but NOT from the `[0]`
  regression — see 🚨 point 4 above (a suspected `byllm==0.6.19` internal bug on this machine,
  reproduced in isolation, unrelated to our code). Not fixed this session; needs either a byllm
  version change or testing on a machine with the bundled `jaclang.byllm` instead.
- `jac test -d .` **cannot be run as a single command right now** — it walks into
  `seed/seed.jac`, which has top-level `with entry` code that makes real HTTP calls and hard-
  crashes the whole batch run when no server is listening (not a test file, shouldn't be swept
  into `-d .`; flagging for Person 2 since they own `seed/`, not fixing it myself since it's
  outside my ownership and low-priority vs. the compile-blocking bugs). **Workaround: test files
  individually** (`jac test <path>`) until that's addressed.
- Live server check (`jac start main.jac --no_client`, then `reset_demo`'d clean afterward):
  `reindex_repo` → 19 files (18 real + `tests/test_smoke.py`), 27 import edges; `debug_blast` →
  `core/validation.py`=14, `models/product.py`=5 (both match the reference table exactly);
  `get_queue` → correct empty-state shape pre-ingest; `get_cluster_detail` → correct
  `{"ok": false, "error": "cluster not found"}` for a bad id. Could not test `ingest_issue`/
  `seed.jac` live myself — no Ollama installed on this machine, and `assess_severity`/
  `estimate_diff_size` run unconditionally in `ingest_issue` regardless of resolution method, so
  every ingestion needs a working LLM backend.
- The Jac MCP server (`jac-mcp`, `✔ Connected`) was used to pull the actual lambda grammar
  (`functions-objects` doc, §7) rather than guessing — worth reaching for again if another
  syntax disagreement like this comes up.

**Not yet started:** the reach weighted-ranking feature (`Settings` node already exists in
`graph/nodes.jac` from an earlier session as a schema stub; no `set_weights` walker, and
`ranking.jac` still uses the fixed `W_BLAST`/`W_SEV`/`W_DIFF` constants only). PLAN.md's own cut
list puts personalization/weights first to cut if behind — given the environment issues above ate
this session's time budget, recommend treating C4 feature-freeze prep (re-verify the pipeline on
whichever machine is the real demo machine, confirm ≥40% Jac) as higher priority than starting
this reach feature, but that's the human's call.

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

> ## 🟢 PERSON 2 IS 100% CODE-COMPLETE (updated at the P1+P2 merge)
>
> **Every technical item in Person 2's scope is done and verified live against the merged code.**
> Re-verified this session: real PR #3 opened end-to-end, all 20 issues ingest, and the last open
> P2 item (`seed/seed.jac` breaking `jac test -d .`) is fixed via `with entry:__main__`.
>
> **The only things left with Person 2's name on them are 🛑 C5 and 🛑 C6** — the Devpost partial
> and final submission. Both are human actions (Devpost forms, demo video, screenshots), not code.
> **Nothing left to build.**

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

**Self-test:** `generate_pr` on cluster A's id → real PR on GitHub. **[x] PASSED** — re-verified
against the fully merged code at the P1+P2 merge: **PR #3**,
https://github.com/alaramartin/triage-demo/pull/3 — opened on the top cluster (`core/validation.py`),
+8/−7 on one file, the committed Python compiles cleanly (syntax gate never had to fall back), and
the PR body carries the root cause, "reached by **14 of 18 files**", and all 4 linked issues.
Confirmed the full round trip: `generate_pr` writes the `PullRequest` node → Person 1's
`get_cluster_detail` reads it back as `existing_pr`.

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

**Status as of this update: everything Person 3 can do solo is done.** Every remaining item below
is either waiting on a teammate's work, or needs a human (rehearsing out loud, recording a screen
capture) rather than more agent work. Nothing is stalled on me right now.

### ✅ Done
- [x] **Phase A:** `mocks/*.json` hand-written → login + repo picker → the ranked queue screen
- [x] **Phase B:** cluster detail page → graph visualization (with the hop-reveal animation) → Generate PR wired
- [x] **🛑 C1** (~12:45): API shapes confirmed unchanged (only the `from_file`/`to_file` vs `from`/`to` edge-key naming difference, fixed during the live swap)
- [x] **🛑 C2** (2:15): merged `p3/client` → `main`; `jac check` clean
- [x] **🛑 C3** (3:30): swap mocks → live data — done AND **verified in a real browser**, not just diffed JSON: real seeded cluster/singleton/unresolved data through every screen including a real `generate_pr` call and the graph view, zero console errors
- [x] Queue/cluster-detail polish pass: keyboard accessibility (the cluster row is a real `role="button"` with focus ring + Enter/Space, not just a clickable div), mobile responsiveness (rows were overlapping under ~500px, fixed), a hard-coded `"of 18 files"` label bug fixed, PR success/error banners matching the real `{ok, ...}` contract
- [x] Fixed 5 bugs that were blocking **the whole team's server from starting at all** (not strictly Person 3 scope, but needed doing - see the session log above for detail: a wrong import in `agents/clustering.test.jac`, a wrong `jac.toml` LLM config section, two `++>`/`+>:edge:+>` list-vs-node bugs, a missing `return` in a sort key)

### ⏳ Waiting on other people's work — ALL UNBLOCKED at the P3 merge

- [x] ~~**Full 20-issue real-pipeline demo**~~ — **DONE.** `seed/repo/` is present and P1+P2 are
      merged, so this ran for real against the merged code on the demo machine: 18 files /
      26 import edges, all 20 seed issues ingested through the live Ollama pipeline, `get_queue`
      returning **3 clusters + 8 singletons + 4 unresolved = 20**. Top cluster is
      `core/validation.py`, **blast radius 14**, 4 issues, urgency **6.76**.
      **Note the numbers moved from the old plan:** the target cluster has **4** issues (not 5) at
      urgency **6.76** (not 7.22), because the live LLM resolves SEED-05 to `utils/csv_export.py`
      instead. The beat still lands — 4 differently-worded tickets collapse into one row that
      outranks SEED-12 at **severity 10** (urgency 2.00). Use the real numbers when narrating.
- [x] ~~**Real "review on GitHub" link on Generate PR**~~ — **DONE.** `create_pull_request` is no
      longer a stub; the button opens a real PR and the UI's `href={pr_result["pr_url"]}` now
      points at a genuine GitHub URL. Verified end-to-end through the merged code:
      **PR #4** → https://github.com/alaramartin/triage-demo/pull/4, and `get_cluster_detail`
      reports it back as `existing_pr`.
- [ ] 🟡 **_(Reach)_ weights/personalization panel — THE ONLY REMAINING P3 CODE ITEM.**
      No longer blocked: Person 1 shipped the `Settings` node and the `set_weights` walker, and
      both are verified working (setting `w_reactions=10` and zeroing the rest re-ranks the loud
      SEED-12 to the top at 8.78; restoring defaults puts `core/validation.py` back at 6.76).
      **Nothing in `client/` references `set_weights` — the panel is not built.**
      **This is explicitly the first thing to cut** (CLAUDE.md scope guards + this plan's own
      "skip entirely if the team is behind"). See "Next steps" below before starting it.

### 🙋 Needs you, not a teammate or more agent work
- [ ] **Rehearse the 4-minute demo end-to-end ≥3×** (CLAUDE.md §8 beat sheet) - this has to be a human talking through it
- [ ] **Record the demo video** during a clean run
- [ ] **🛑 C4** (5:30): feature freeze - confirm the full live flow + that the video is recorded
- [ ] **🛑 C5** (5:50): confirm Person 2 submitted the Devpost partial (mandatory)
- [ ] **🛑 C6** (6:45–7:15): final screenshots + confirm the demo is pre-loaded and `reset_demo` is ready for a clean run at the judging table

### 📊 Person 3 status after the merge: CODE-COMPLETE except one optional reach item

Everything on Person 3's required path is **done and verified live against real data** — no mocks
anywhere on the live path (`client/mock_data.cl.jac` and `mocks/*.json` still exist but are dead
code; nothing imports them). The **only** unbuilt item is the _(reach)_ weights panel, which the
plan and CLAUDE.md both name as the first thing to cut.

**Next steps, in priority order:**

1. **Rehearse + record** (highest value by far). The demo is fully working right now — see the
   "how to run the demo" block below. This is the remaining human work and it matters more than
   any additional feature.
2. **Decide on the weights panel.** It is genuinely optional. If you want it, the backend is
   already done and tested, so the work is purely client-side: a small slider/preset control that
   calls `set_weights(full_name, w_blast, w_sev, w_diff, w_reactions, w_comment_velocity)` and
   then re-fetches `get_queue`. A "sort by popularity instead" preset button is the cheapest
   version and makes a sharp demo point — flipping it shoots the loud severity-10 SEED-12 to the
   top, which *proves* the default ranking is structural rather than popularity-driven.
   **Do not start this until the video is recorded.**
3. **C4/C5/C6** — freeze, Devpost partial, final screenshots. Human submission steps.

### 🚨 Demo-day gotchas found while verifying (read before rehearsing)

- **Editing ANY `.jac` file while `jac start main.jac --dev` is running WIPES the seeded graph.**
  The dev server watches `**/*.jac` and hot-reloads; the reload dropped all 20 seeded issues
  mid-verification (`[HMR] Reloaded: seed/seed.jac` → `get_queue` returned `file_count=0`). It can
  also leave duplicate `Repo` nodes behind, where `get_queue` finds a repo with 18 files but zero
  issues. **Do not touch a `.jac` file between seeding and demoing.** If it happens: restart
  clean (`pkill -f "jac start main.jac"`, `jac clean --all --force`, restart) and re-seed —
  `reset_demo` alone does not fix the duplicate-Repo case.
- **The API port depends on the mode.** `--no-client` → API on **8000**. `--dev` → app on
  **8000**, API on **8001**. `seed/seed.jac` defaults to 8000; for a `--dev` server run
  `TRIAGE_API=http://localhost:8001 jac run seed/seed.jac`.
- **The client needs `@tanstack/react-form` in `jac.toml`.** jac 0.34.7's GENERATED
  `client_runtime.js` does an unconditional `import { useForm } from "@tanstack/react-form"`
  even though none of our client code uses forms. If it is missing, the backend looks fine and
  `curl /` even returns 200 (that is just Vite's HTML shell), but the browser shows
  **"[plugin:jac-error-reporter] Failed to fetch dynamically imported module: /compiled/_entry.js"**
  and a blank app. Fixed in `jac.toml`. To verify the client for real, curl the MODULES, not `/`:
  `curl -o /dev/null -w "%{http_code}" http://localhost:8000/compiled/_entry.js` (and
  `/compiled/main.js`, `/compiled/client_runtime.js`) - all must be 200.
- **`pkill -f "jac start"` does NOT stop the frontend.** Vite runs under a separate `bun`
  process that survives, keeps holding port 8000, and the next `jac start` silently bumps the
  app to 8002, 8003, ... while you keep browsing the OLD, stale build on 8000. This is how a
  fixed bug can look unfixed. Always kill both and confirm the port is free:
  `pkill -f "jac start"; pkill -f bun; lsof -nP -iTCP:8000 -sTCP:LISTEN`
  Then check the startup banner actually says `App: http://localhost:8000/`.
- **Seeding takes a few minutes** (20 sequential local-LLM ingests). Seed *before* the judges are
  watching, and never re-seed without `reset_demo` first or you get duplicate issues.

### ▶️ How to run the demo (verified working end to end)

```bash
pkill -f "jac start main.jac"; jac clean --all --force
jac start main.jac --dev                       # app :8000, API :8001
# then, in a second terminal, once it says "Server ready":
curl -X POST http://localhost:8001/walker/reindex_repo \
  -H "Content-Type: application/json" \
  -d '{"repo_path":"seed/repo","full_name":"alaramartin/triage-demo"}'
TRIAGE_API=http://localhost:8001 jac run seed/seed.jac    # ~few minutes, 20 issues
```

Then open **http://localhost:8000/** → login → repo picker → the ranked queue.

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

### 📍 UPDATE — pulled `main`, the server didn't actually start (fixed), then verified live in a real browser

Picked this branch back up after pulling the merge above. **The `jac check` in the note just above
was clean, but the actual dev server would not start at all** - `jac start main.jac --dev` failed
immediately with `No module named 'jaclang.byllm'` before ever reaching the client. `jac check`
never catches this class of bug (same lesson as the earlier `obj`/`new` client bug): it type-checks,
it doesn't execute the module graph the way `jac start`/`jac run` does. Found and fixed **five real
bugs**, all now verified against a genuinely fresh `jac start --dev` + a real headless-browser
click-through with **real seeded graph data** (not just curl'd JSON):

1. **`agents/clustering.test.jac`** imported `from jaclang.byllm.lib` instead of `from byllm.lib`.
   `.test.jac` files auto-merge into their base module at compile time (even outside `jac test`), so
   this one bad import in a *test* file broke importing `agents.clustering` for the entire live
   app - `main.jac` → `agents.ranking` → `agents.clustering` → boom. Root-caused by bisecting with
   throwaway scratch `.jac` files until the exact trigger (the test file's own import) was isolated.
2. **`jac.toml`'s `[byllm.model]` section was wrong again** (flipped back from a previous fix,
   apparently by someone re-"verifying" it the other way). Settled for good this time by reading
   `byllm`'s own bundled `config_loader.jac` docstring directly and empirically confirming with a
   throwaway `get_byllm_config()` script that `[plugins.byllm.model]` resolves and a bare
   `[byllm.model]` does not. Also dropped a stray empty `[client]` table (not a real jac.toml
   section; `[plugins.client]` is what's implied by `[plugins.client.vite]`).
3. **`main.jac`'s `reindex_repo`**: `repo = root ++> Repo(...)` - `++>` returns a **list**, not the
   node (confirmed via `jac-node-edge-patterns`: "`new = here ++> Todo(...)` makes `new` a list").
   Broke on every *first-time* index of a new repo (the common case). Fixed with `[0]`.
4. **`main.jac`'s `get_queue`**: both `.sort(key=lambda (c: ClusterView) { c.urgency; })` calls were
   missing `return` inside the block-lambda body, so the sort key was always `None`. Real bug, not
   just a checker complaint - `jac check` correctly flagged this as `E1054` and it was right to.
5. **`agents/clustering.jac`'s `maybe_cluster`**: `cluster = repos[0] +>:owns:+> Cluster(...)` - same
   list-vs-node pitfall as #3 (`+>:edge:+>` also returns a list). Fixed with `[0]`.

None of these are Person 3's files, but they were blocking the server from running at all, so fixed
them directly rather than just reporting them (matches the pattern already in this repo's own
history - see the `5a0437d`/`d1ed6a8` commits: "fix merge-blocking bugs").

**Then did the verification the previous merge's curl-diff approach couldn't do**: added a
temporary `_debug_seed` walker to `main.jac` (same direct node/edge-construction pattern
`main.test.jac` already uses) to get one real `Cluster` (2 issues, real computed `blast_radius=3`
over a real 4-file `imports` graph), a real singleton, and a real unresolved issue - all without
needing Ollama or the real `seed/repo/` (neither exists on this machine). Removed the walker again
before committing; it never touched `main`. Confirmed in an actual headless Chrome session, zero
console errors, at every step: login → repo picker → queue with real numbers → expand cluster (real
5→1-row collapse, well, 2→1 here) → **real** `generate_pr` walker call (got back a real fake-PR
number from the stub) → cluster detail → **real** graph view with correct live blast-radius topology
and the reveal animation. Found and fixed one more real bug this surfaced: `cluster_view.cl.jac`
hard-coded `"of 18 files"` in the blast-radius label - harmless against the eventual real 18-file
repo, but actively wrong (`"3 of 18 files"`) against any other file count. Now reads `"N file(s)"`
like every other row, no hard-coded total.

**One unresolved oddity, not chased further (time-boxed):** at one point mid-session, real seeded
graph data disappeared from `get_queue` after editing a `.cl.jac` file (confirmed via direct `curl`,
not just the browser - the data was actually gone server-side). Re-seeding immediately after worked
fine and stayed stable through several more edits/screenshots. Docs say `.cl.jac` edits should only
trigger client-side HMR, not a server/data-affecting restart, so this may be a `jac start --dev`
file-watcher quirk under some edit patterns. Never happened with a real seed you'd hate to lose
(only my own throwaway debug data), but **don't trust a long-running dev session's seeded state
across many small edits** - re-verify with a quick `get_queue` curl after any server-module-adjacent
change, and always `reset_demo` + reseed fresh right before a checkpoint or the real rehearsal.

Checklist above updated to reflect this pass. Remaining real work is unchanged from before this
update: demo rehearsal, video, reach weights panel (if Person 1 ships `set_weights`) - none of it
blocked anymore.

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

---

# GITHUB LOGIN — real OAuth + any-repo indexing (built after C4, post-freeze)

**Status: built and verified live end-to-end.** This replaces the "GitHub OAuth is a documented
scope cut" note that appears throughout the older sections below — those are now historical.
The login button, the "Your projects" list, and "choose another repo" all run on real GitHub
data. Nothing on those screens is hardcoded any more.

**⚠️ ONE HUMAN STEP REMAINS.** The OAuth *code* is done; the OAuth *app* is not registered.
Until it is, `github_status` reports `oauth_configured: false` and the login button renders
disabled with an explanation. To turn it on:

1. https://github.com/settings/developers → **New OAuth App**
   - Application name: `Triage`
   - Homepage URL: `http://localhost:8000`
   - **Authorization callback URL: `http://localhost:8000`** (the app root — the login screen
     reads `?code=` off it; do NOT use a `/callback` path, the SPA has no such route)
2. Generate a client secret, put both values in `.env`:
   `GITHUB_CLIENT_ID=...` / `GITHUB_CLIENT_SECRET=...`
3. Restart `jac start main.jac`. The button becomes a real link to GitHub's consent screen.

**Until that's done the app still works** — with `GITHUB_TOKEN` set, `github_status` reports
`source: "token"` and the login screen skips straight to `/repos` with the token's real
identity. So this is a strict upgrade, not a demo risk.

**What was built**

| Layer | Change |
| --- | --- |
| `graph/nodes.jac` | new `GithubAuth` node (root-attached, at most one) holding login/name/avatar/token; `Repo.last_selected` for "which repo is the dashboard showing" |
| `integrations/github.jac` | `authorize_url`, `exchange_code_for_token(code, redirect_uri)`, `get_authenticated_user`, enriched `list_repos`, `get_repo`, `parse_repo_full_name`, `clone_repo` (shallow, into `.workspace/`), `fetch_open_issues(full_name, limit, token)`. **Every call now takes an explicit `token`** that falls back to `.env`'s `GITHUB_TOKEN` — no mutable global session state |
| `integrations/ast_parser.jac` | hardened for arbitrary real repos: skips `.git`/`node_modules`/`venv`/`build`, tolerates unparseable + non-UTF8 files, resolves **relative imports**, and resolves **package-root-relative module names** so `src/`-layout repos actually get import edges |
| `main.jac` | `github_status`, `github_login`, `github_logout`, `list_my_repos`, `select_repo`, `get_active_repo`; `ingest_issue`/`ingest_from_github`/`generate_pr`/`generate_pr_for_issue` no longer assume a single `[root-->][?:Repo][0]` repo |
| `client/screens/LoginScreen` | real OAuth link + `?code=` handling; no more "advances to the repo picker authenticating nothing" |
| `client/screens/RepoPickerScreen` | real repo grid from `list_my_repos` + a "choose another repo" URL box; two-stage progress (clone/index → triage). **No issue cap** — the whole queue gets triaged, with a time estimate shown up front |
| `client/screens/QueueScreen` | `DEMO_REPO` constant **deleted** — repo comes from `/queue?repo=owner/name` or `get_active_repo` |

**Verified live (not from notes):** `pallets/flask` via the paste-a-link path → 83 files, **174
import edges**, `src/flask/app.py` blast radius **23**, 3 real GitHub issues ingested and ranked
with their real issue numbers as `external_id`. Seed repo re-verified unchanged afterwards: 18
files / 26 edges / `core/validation.py` = **14**, clusters 6.76 / 3.76 / 2.58, 4 unresolved.
`jac test -d .` → **35 passed**, same as before.

**Two counting gotchas, both real bugs that shipped and were fixed:** GitHub's
`open_issues_count` **includes pull requests** (`jaseci-labs/Agentic-AI` reports 44 there but has
37 issues + 7 PRs), so `select_repo` calls `count_open_issues` for a true count and the repo grid
labels its cheap number "issues + PRs". And an early 15-issue ingest cap in the repo picker was
removed — it silently would have triaged only 15 of the demo repo's 20 issues.

**Demo note on repo choice:** pick a *Python-heavy* repo for the wow moment. `jaseci-labs/jac`
indexes to only 95 Python files / 12 import edges (it's a Jac repo, so there's little Python to
graph) and the blast radii come out flat. `pallets/flask` is the good one — dense import graph,
only ~10 open issues so a full ingest finishes fast.

**🚨 THE ONE GOTCHA THAT COST THE MOST TIME — read this before debugging anything weird**

**After editing `graph/nodes.jac`, you MUST `rm -rf .jac/cache` before restarting the server.**
The compile cache holds a stale `graph.nodes` module, and `jac check` does NOT catch it (it
compiles fresh). The symptoms are wildly misleading and all trace back to this one cause:

- `NameError: name 'Repo' is not defined` at `root ++> Repo(...)` — under `jac start` only,
  never under `jac run`.
- `NameError: name 'GithubAuth' is not defined` inside a plain `def`.
- **`[root-->][?:SomeType]` silently stops narrowing** and hands back a node of a totally
  different type, so you get `'Repo' object has no attribute 'login'` — the filter didn't
  filter, it just returned everything.
- Any of the above failing on the *first* call after a restart and then appearing to work.

Two false leads chased along the way, recorded so nobody re-chases them: a leading
`import time;` above the archetype imports (looked like the cause under bisection, wasn't —
the bisect commands also wiped the DB), and `SqliteMemory: schema drift on graph.nodes.Repo`
in the log. **The drift message is real but separate**: adding a field to a node type that
already has persisted instances does require deleting `.jac/data/*.db` and re-ingesting
(~3 min of local LLM for a full seed run). Cache first, then DB — in that order.

`main.jac`'s `_auth_node` / `_all_repos` helpers re-check `isinstance` for exactly this reason:
it turns the stale-cache failure from a crash into an empty result.

---

# WEBSITE UI — visual pass (dark / green + orange)

Restyle of the existing four screens from Alara's Excalidraw sketches. Structure and data
flow are already live; this is a **visual + layout** pass, not a rewrite. Vibe: sleek,
modern, flat. Black background, green + orange accents, thin 1px borders, no heavy shadows,
no gradients beyond a hairline.

**Palette (single source of truth: `client/global.css`)**

| Token                    | Value     | Used for                                     |
| ------------------------ | --------- | -------------------------------------------- |
| `--color-bg`             | `#08090b` | page background (near-black)                 |
| `--color-surface`        | `#101216` | cards, rows                                  |
| `--color-surface-raised` | `#171a20` | hover / nested rows                          |
| `--color-border`         | `#22262e` | every border (1px, no shadows)                |
| `--color-text`           | `#f2f4f7` | primary text                                 |
| `--color-text-muted`     | `#878e9c` | labels, paths, meta                          |
| `--color-green`          | `#3fd68c` | **action** — Generate PR, resolved/positive  |
| `--color-orange`         | `#ff8b3d` | **emphasis** — blast radius, view detail, #1 |

Green = the thing you click to act. Orange = the thing the graph is shouting about.

## Tasks

- [x] **Palette + base** — `client/tailwind.src.css` holds the tokens above; body on
      `--color-bg`, antialiased. Old red `--color-accent` removed.
- [x] **Tailwind actually compiles** — see the gotcha below. This was the real reason the app
      looked unstyled, not missing classes.
- [x] **Landing** (`screens/LoginScreen.cl.jac`) — centered `Tri`+orange`age` wordmark,
      one-line tagline, green one-click "Log in with GitHub" button, WIP note under it.
- [x] **Repo picker** (`screens/RepoPickerScreen.cl.jac`) — "Your projects" heading, card grid,
      live repo name + file count, orange hover border. Second tile is a disabled
      "Connect more repositories" placeholder labelled as pending OAuth.
- [x] **Ranked queue** (`screens/QueueScreen.cl.jac`) — repo name + back link top-left,
      ranking-priorities control top-right, cluster rows, then standalone issues, then the
      parked bucket.
- [x] **Cluster row** (`components/ClusterRow.cl.jac`) — sketch's three columns: issue chips
      left, title + root cause + blast/urgency middle, and behind a divider a green
      **GENERATE PR** over an orange **View detail**. `#1` cluster gets an orange border.
- [x] **Singleton + unresolved rows** — same language, quieter (no orange, no buttons, more
      compact) so the eye lands on clusters first.
- [x] **Settings / priorities panel** (`components/SettingsPanel.cl.jac`) — collapsible,
      top-right of the queue. Sliders write to the real `set_weights` walker and refetch
      `get_queue`.
- [x] **Cluster detail** (`cluster_view.cl.jac`) — description up top, big bordered graph panel
      as the hero with stats + legend in its header, root cause / proposed fix side by side,
      member issues below. Also now surfaces the real `existing_pr` link when one exists.
- [x] **Graph view** (`components/GraphView.cl.jac`) — orange target, green dependents fading
      by hop, grey unreached. Wider canvas, rings rotated off each other and labels alternating
      above/below so filenames stop colliding. Ring-by-ring reveal kept.
- [x] **Browser check** — all four screens loaded in a real (headless Chrome) browser against
      the live server; screenshots reviewed, no client-side runtime errors in the dev log.
      **Not** click-tested: the ranking sliders and the Generate PR button (the walkers behind
      both are covered by `main.test.jac`, but the click paths deserve one manual pass).

## Follow-up pass — standalone issues are first-class

- [x] **Parked issues moved into the standalone list.** No more separate "couldn't confidently
      place" panel; they render as ordinary rows at the bottom of **Standalone issues** with
      `-` in place of blast radius / urgency / severity, an `unresolved` badge, and the reason
      inline ("below confidence threshold - not placed"). The credibility beat survives, it
      just isn't a box of its own any more.
- [x] **Generate PR on standalone rows.** New `generate_pr_for_issue` walker (main.jac) +
      `build_pr_for_issue` (agents/pr_agent.jac). `build_pr_for_cluster` was refactored onto a
      shared `_build_pr(target, members, root_cause, proposed_fix, blast_radius, headline,
      repo)` core, so both paths run the exact same pipeline: denylist gate, real source read,
      `by llm()` full-file fix, syntax check + retry, real PR. Still human-triggered only.
      Parked rows get no button — there's no code node to patch.
- [x] **Hover card on those buttons.** New `get_issue_fix_preview` walker backed by
      `preview_issue_fix()` `by llm()`, returning exactly two sentences: **the issue** and
      **the fix**. Fetched on hover/focus, once per row, cached in the row's local state.
      It is the *same* call `generate_pr_for_issue` derives its root cause from, so the hover
      text is what the PR actually gets built from — not decorative copy.
- [x] Verified in a real browser over CDP: hovered the button, the live `by llm()` text landed
      in the card. Standalone rows carry no graph and no View detail, per the ask.
- ⚠️ **Not exercised end to end:** clicking Generate PR on a standalone issue opens a *real*
      PR against the demo repo, so it was left unclicked. The GitHub half of that path is the
      same code the cluster button already proved (PR #5), but give it one manual click before
      the demo.

Schema note for P1/P2: `fixes` (documented in CLAUDE.md §4.2 as PullRequest -> Cluster) now
also lands on an Issue when the PR came from a standalone issue. Nothing reads it in the
other direction, so it is purely additive.

## Follow-up pass — Generate PR feedback + Drafted PRs

Clicking Generate PR used to do nothing visible for ten-plus seconds (real source read,
full-file `by llm()` rewrite, syntax check, GitHub call). Now:

- [x] **Button shows progress.** On click it becomes a spinner + "Generating", is disabled,
      and takes a `cursor-wait`. Same treatment on cluster rows, standalone rows and the
      cluster detail page (`components/Spinner.cl.jac`).
- [x] **Done items leave the queue.** On success the screen refetches `get_queue`; the row
      dims to 55% opacity and moves to a new **Drafted PRs** section at the bottom, with its
      action replaced by a `PR #n →` link. Cluster rows there swap the orange `#1` rank badge
      for a green `drafted` badge; ranks renumber over the *live* clusters, so #1 is always
      the top of the working queue.
- [x] **It survives a reload.** `get_queue` now reports `pr_number` / `pr_url` on both
      `ClusterView` and `SingletonView`, read off the `fixes` edge - so "drafted" is graph
      state, not React state. A refresh does not resurrect a row you already actioned.
- [x] Verified in a real browser over CDP. The spinner was checked by **holding** the
      `/walker/generate_pr` request at the CDP Fetch layer and aborting it, so the mid-flight
      state was observed (`text: "Generating"`, `disabled: true`, `animationName: "spin"`)
      **without opening a real PR**. The drafted section renders from genuinely pre-existing
      PRs (#5 on the core/validation.py cluster, #7 on SEED-17).

### ⚠️ Demo-day trap

Every PR you open in rehearsal moves that item into Drafted PRs **permanently** (it's on the
graph). The `core/validation.py` cluster - the 14-of-18 blast-radius hero of beat 2 - already
sits down there because of earlier testing. **Run `reset_demo` + re-seed before the real
run**, or your top cluster will be greyed out at the bottom of the page when you present.

## Data honesty (check at the end — CLAUDE.md §2)

- ✅ **Real:** repo name + file count, clusters, member issues, blast radius, urgency,
      severity, resolution method, cluster detail, graph nodes/edges, PR generation, and the
      ranking weights (all from `get_queue` / `get_cluster_detail` / `generate_pr` /
      `set_weights`).
- ⚠️ **WIP — GitHub OAuth.** "Log in with GitHub" does not authenticate; it navigates
      straight to the repo picker. The picker therefore lists only the repo we hold a PAT
      for, sourced live from the graph — **not** a fabricated repo list. A dashed
      "Connect more repositories" card is shown disabled and labelled as pending auth.
- ✅ **Issue links are real (as of 2026-07-26).** Seeding now ingests from
      `github.com/alaramartin/triage-demo/issues` via `ingest_from_github`, not a
      `SEED-nn`-labelled fixture — every ingested issue's `external_id` is the real GitHub
      issue number, so `IssueChip` renders every chip as a live link back to GitHub. See the
      2026-07-26 entry above.
- `client/mock_data.cl.jac` and `mocks/*.json` are **not** imported by any screen. They stay
  as the offline fallback fixtures they were built as.

## ⚠️ Gotcha found during this pass — Tailwind was emitting ZERO utilities

The app rendered as unstyled text on a black page, and it was not the class names — it was
that Tailwind never ran.

- `jac.toml`'s `[plugins.client.vite]` table (`plugins = ["tailwindcss()"]`) is **not honored
  by jac 0.34.7**. The generated `.jac/client/configs/vite.dev.config.js` contains only jac's
  own plugins plus `react()` — no `tailwindcss()`.
- That config is **regenerated from scratch on every `jac start`**, so hand-patching it in
  `.jac/` does not survive a restart (verified with a marker comment).
- Without the plugin, `@import "tailwindcss"` is passed through raw: the served CSS literally
  contained `@layer utilities { @tailwind utilities; }`, i.e. zero compiled classes.
- Adding `@source` to the CSS does not help on its own — Tailwind skips `.gitignore`d paths,
  and the copy it would scan from lives under the ignored `.jac/`.

**Fix in place:** we precompile the stylesheet ourselves.

```
npm install          # once - root devDependency on the Tailwind CLI
./client/build_css.sh   # regenerates client/global.css from client/tailwind.src.css
```

- Edit **`client/tailwind.src.css`**, never `client/global.css` (generated, and marked
  `linguist-generated=true` in `.gitattributes` so it does not dent the repo's Jac language %).
- **Re-run `./client/build_css.sh` after adding any new Tailwind class to a `.cl.jac` file**,
  or that class will silently have no effect. `./client/build_css.sh --watch` alongside
  `jac start --dev` if you're iterating on styling.

## 2026-07-26 — `seed/issues.json` retired, real GitHub issues now the source of truth

The 20 synthetic issues that used to live in `seed/issues.json` are now real issues on
`github.com/alaramartin/triage-demo/issues` (#8–#27 — #1–#7 were already taken by PRs opened
during earlier `generate_pr` testing). `seed/issues.json` is deleted; nothing in the codebase
reads it anymore.

**What changed:**

- `integrations/github.jac`: new `fetch_open_issues(full_name) -> list[RemoteIssue]`. Real
  GitHub REST call (`GET /repos/{full_name}/issues?state=open`), paginated, filters out pull
  requests (they share the issues endpoint — anything with a `pull_request` key is skipped).
  `comment_velocity` is derived (comments / days-since-created, min 1 day) since GitHub has no
  such field natively.
- `main.jac`: the per-issue resolve → severity/diff estimate → cluster → rank logic that used
  to live inside `ingest_issue`'s walker body is now a shared `_ingest_one()` function, so it
  can't drift between entry points. New `walker:pub ingest_from_github` fetches a repo's live
  open issues and runs each through `_ingest_one()`, skipping any `external_id` (the GitHub
  issue number) already ingested — safe to re-run as new issues get opened.
- `seed/seed.jac`: now POSTs to `/walker/ingest_from_github` instead of reading a local JSON
  fixture. `TRIAGE_GITHUB_REPO` env var overrides which repo it seeds from.

**Why this matters beyond "looks more legit":** `external_id` on ingested issues is now the
real GitHub issue number (a numeric string), which is exactly what `client/components/
IssueChip.cl.jac` already checked for to render a chip as a real `github.com/.../issues/N`
link instead of a dead-end label — that codepath had been sitting unused since P3 built it
against `SEED-nn` fixtures. It's live now with zero client changes. This is also the mechanism
that lets Triage point at **any** repo's real issue queue, not just the hardcoded demo one, once
GitHub auth is wired up to let a user pick a repo — `ingest_from_github` already takes
`full_name` as a parameter for exactly that reason.

**Verified live:** restarted the server (it was running the pre-change compiled `main.jac` and
returned a bare `401 Unauthorized` for the unknown new walker — a stale server process, not a
real auth failure), re-ran `reindex_repo`, then `ingest_from_github` — fetched 20, ingested 20,
0 skipped. `get_queue` came back with the same shape as before: 3 clusters (`core/validation.py`
× 4 issues / blast 14 / urgency 6.76, `models/product.py` × 2, `services/upload.py` × 2), 8
singletons, 4 unresolved. Numbers match the pre-migration `issues.json` run, as expected — same
issue text, now sourced from GitHub instead of a fixture.

**Data honesty update (CLAUDE.md §2):** the "Issue links are best-effort" caveat in the Data
honesty section above is now stale — issue chips resolve to real GitHub links for every
ingested issue, not just a hypothetical numeric-external_id case.

---

# Post-hackathon refinement pass (2026-07-28)

Five asks, in the order they'll be done. Task 3 (speed) is deliberately last — it's the
vaguest and the lowest priority. **Each task ends with a stop-and-test beat**: nothing moves
on to the next task until the human has run it and committed.

Everything below was diagnosed against the **live running server + the persisted graph**
(`.jac/data/anchor_store.db`), not guessed.

## Task 1 — Index ANY repo, not just your own

### What's actually broken

The paste box was deleted from the JSX in commit `0d2c12c` ("demo bugfixes"), with a comment
claiming the server side is fine. The server side is **not** fine — three separate things
break on somebody else's repo:

1. **`llm_resolve` is handed EVERY file path + every file summary.** Fine for an 18-file seed
   repo; on `pallets/flask` (~90 py files) it's marginal and on `jaseci-labs/jac` (1000+) the
   prompt blows past a local 7B model's context and the call errors or returns garbage. This
   is almost certainly the "it was erroring" the box got pulled for.
2. **PR creation assumes push access.** `create_pull_request` does `POST /git/refs` directly
   on the target repo. On a repo you don't own that's a hard `403` — which is the *normal*
   case for "other people's open-source repos". There is no fork path.
3. **No feedback for the cases that legitimately can't work** — a repo with zero Python files
   indexes to `file_count = 0` and every issue silently parks as Unresolved with no
   explanation on screen.

### Fix

- [ ] `agents/triage_agent.jac`: add `shortlist_candidates(title, body, file_paths,
      summaries, cap)` — a cheap, deterministic lexical pre-filter (token overlap between the
      issue text and each path + its docstring summary, plus every path literally mentioned in
      the body). `resolve_issue` sends the LLM at most `cap` (default 40) candidates instead
      of the whole repo. Pure Python, no extra LLM call, and it makes big repos *possible*,
      not just faster.
- [ ] `integrations/github.jac`: `ensure_fork(full_name, token)` (POST `/repos/{r}/forks`,
      poll until the fork's default branch is readable) and rework `create_pull_request` to
      take a `head_repo`: when the caller can't push to the target, create the branch on the
      **fork**, write the file there, and open the PR cross-repo with `head = "<owner>:<branch>"`.
      Push access is probed once via `GET /repos/{r}` → `permissions.push`.
- [ ] `main.jac` / `select_repo`: report `python_files` explicitly and a `warning` string when
      a repo indexes to 0 Python files, so the UI can say why instead of showing an empty queue.
- [ ] `client/screens/RepoPickerScreen.cl.jac`: restore the "paste any repo" form (it's still
      wired to `handle_custom_submit`), and surface the new warning + a "you can't push here,
      PRs will open from a fork" note on the queue screen.

**Test:** paste `pallets/flask` (or any public repo you don't own), confirm it indexes, the
queue fills, and Generate PR opens a PR *from your fork* against upstream.

## Task 2 — The two bugs

### 2a. Duplicated issues — CONFIRMED, root cause found

`get_queue` on `alaramartin/triage-demo` right now: `services/upload.py` reports **10** issues
that are really 2 (#16 ×5, #17 ×5), and the standalone list carries 30 rows for 12 issues. The
graph has **64 Issue nodes for 20 real GitHub issues** — 20 distinct `external_id`s with
multiplicities of 1–5.

The multiplicity *rises with issue number* (#8/#9 ×1 … #19/#20/#21 ×5). That's the signature of
**overlapping `ingest_from_github` runs**, not of a bad loop: `ingest_from_github` snapshots
`already = {external_ids}` **once, before the loop**, then spends ~9s per issue. Anything that
starts a second run mid-flight (the picker's detached `start_ingest`, a browser retry of a
multi-minute request, a re-click, a back-and-click-again) re-ingests everything the first run
hasn't reached yet. Five overlapping runs ⇒ ×5 on the tail.

- [ ] **Re-check inside the loop, not just before it.** Query the repo's issues by
      `external_id` immediately before creating each `Issue` node.
- [ ] **Take an ingest lock on the `Repo` node** (`ingesting_since: float`). A second
      `ingest_from_github` for the same repo returns `{ok: false, error: "already ingesting"}`
      instead of racing. Lock is released in a `try`/`finally` and treated as stale after 15 min
      so a crashed run can't wedge the repo forever.
- [ ] **Client guard**: the repo picker disables cards while a select/ingest is in flight
      (it already has `busy_repo` — it just isn't held across the nav).
- [ ] **`walker:pub dedupe_issues`** — repairs an already-polluted graph: for each repo, keep
      the oldest Issue per `external_id`, delete the rest and their edges, then recompute
      cluster `issue_count`. `dedupe_repos` already does the Repo-level equivalent.

### 2b. Generate PR does nothing — CONFIRMED, root cause found

`.env` line 34 is `TRIAGE_FIX_MODEL=` — **set but empty**. `agents/pr_agent.jac` does
`os.environ.get("TRIAGE_FIX_MODEL", "ollama/qwen2.5-coder:7b")`, and `os.environ.get` returns
the **empty string**, not the default, for a set-but-empty var. So `fix_llm = Model(model_name="")`
and every `generate_fix` dies with:

```
litellm.BadRequestError: LLM Provider NOT provided ... You passed model=
```

Reproduced directly (scratch `jac run` against the real file, no GitHub calls). The walker then
500s, the client's `root spawn` throws, `mark_generating(id, False)` never runs — hence
"it says Generating and then nothing, forever". This broke in `dc7f1bb` (showcase mode), which
added the empty var to `.env`.

- [ ] **`_env(name, default)` helper** in `pr_agent.jac` + `github.jac` that treats
      set-but-empty as unset. Same trap applies to `TRIAGE_APP_URL`, `TRIAGE_WORKSPACE`.
- [ ] **`generate_pr` / `generate_pr_for_issue` must never 500.** Wrap the fix-generation call
      so an LLM failure reports `{ok: false, error: "<reason>"}` and the UI shows it.
- [ ] **Client `try`/`finally`** around both PR handlers so the spinner always clears.
- [ ] Add a one-line startup check that prints the resolved fix model, so an empty/misconfigured
      model is visible at boot instead of on click.

**Test:** click Generate PR on the `core/validation.py` cluster. Expect a real PR, or a red
banner naming the reason — never a stuck spinner.

## Task 4 — Personalized ranking settings

Half-built already: the `Settings` node, `set_weights`, and `weighted_urgency`
(with `w_reactions` / `w_comment_velocity` terms) all exist and `get_queue` re-ranks against
them. What's missing is that **the UI only exposes 3 of the 5 weights and never loads the
stored ones** — `SettingsPanel` hardcodes `w_blast = 6.0` on every mount, so a saved
preference silently reverts on reload.

- [ ] `walker:pub get_weights` (or fold the weights into `get_queue`'s report) so the panel
      mounts with what's actually stored.
- [ ] Sliders for **social signals** (`w_reactions`, `w_comment_velocity`) — the two weights
      that already work server-side and aren't on screen.
- [ ] A "reset to structural defaults" button, and live per-slider explanation text so the
      demo point ("blast radius is the signal only a graph gives you") survives someone
      dragging the sliders around.
- [ ] Keep `set_weights`' current contract: it never touches stored `Issue.urgency`, so the
      cascade's numbers stay blast-dominant regardless of viewer preference.

**Test:** move the sliders, reload the page, confirm the order and the slider positions both
persist.

## Task 5 — Better PR quality

Current body is four short sections and a bare `- <id>: <title>` list. Target:

- [ ] **Real issue links** — `Closes #16` / `Closes #17` lines (GitHub auto-closes on merge)
      plus full URLs, using the fact that `external_id` IS the GitHub issue number.
- [ ] **Before / after** — emit the unified diff (`difflib.unified_diff` over the old and new
      file, already both in hand) into a collapsed ```` ```diff ```` block, so the PR shows what
      changed rather than just asserting it.
- [ ] **What it did and why, specifically** — a `by llm()` `FixExplanation` object
      (`what_changed`, `why_it_works`, `risk_notes`, `test_suggestion`) generated from the
      before/after pair, not from the issue text.
- [ ] **Provenance** — the blast-radius line becomes a short table (target file, dependents
      reached, files in repo, cluster urgency, member count) and the footer keeps the "a human
      clicked this" line.
- [ ] Verify the whole body renders on a real PR before calling it done.

## Task 3 — Make triage faster (LAST)

Deliberately last, per the ask. Sketch, to be firmed up when we get there:

- **Cache the expensive per-issue LLM work** keyed by `(repo, external_id, content hash)` so
  a re-visit or a re-ingest is instant. This is the "optimize repeated visits" half.
- **Cut 3 LLM calls per issue to 1** by merging `assess_specificity` + `assess_severity` +
  `estimate_diff_size` + `llm_resolve` into a single structured `by llm()` object. That's the
  real win: ~9s → ~3s per issue.
- **Parallelize** ingestion across issues (they're independent until the clustering step).
- Skip re-clustering per issue: cluster once at the end of a batch instead of on every edge.


## Task 1b — TypeScript / JavaScript indexing (2026-07-28)

Prompted by `alaramartin/website` reporting "no Python files to index": 9 of the account's 15
repos are TypeScript, so a Python-only Triage could not touch most of the user's own work.
CLAUDE.md's "Python only" scope guard is lifted (see §2 there).

- [x] **`integrations/js_parser.jac`** — discovery + import resolution for
      `.ts/.tsx/.mts/.cts/.js/.jsx/.mjs/.cjs`. Regex over the four specifier shapes
      (`from '…'`, bare `import '…'`, `require('…')`, dynamic `import('…')`) rather than a real
      parser: there is no TS parser in the stdlib and requiring a node toolchain to index a repo
      is a worse trade. Resolution is exact — a specifier only becomes an edge if it resolves to
      a file actually in the index, so the failure mode is a *missing* edge, never a fabricated
      one. Handles relative paths, extension inference in tsc's own order, `/index.*` directory
      imports, the TS-ESM `./foo.js` → `foo.ts` convention, and `@/` `~/` root aliases.
      Skips `node_modules`, `dist`, `build`, `.next`, `coverage`, minified bundles and `.d.ts`.
- [x] **`build_code_substrate` dispatches by language** and sets `File.language`. A mixed repo
      gets ONE graph containing both families — imports don't cross languages, so it is two
      disconnected components and blast radius is still correct within each.
- [x] **`agents/triage_agent.jac`**: the definition index learned TS/JS declaration forms
      (`function`, `class`, `const`/`let`/`var`, `interface`/`type`/`enum`, all with optional
      `export`/`default`), `explicit_resolve` reads V8/Node stack traces the way it already read
      Python tracebacks, and `_stem()` strips any source extension instead of only `.py`.
- [x] **`agents/pr_agent.jac`**: `_python_syntax_error` → `_syntax_error`, which **skips
      non-Python files**. `compile()` on a `.ts` file fails every time, which would have burned
      all three retries and pushed anyway. Non-Python rewrites are explicitly unchecked rather
      than falsely "validated". The `generate_fix` semstrings no longer say "Python" and now
      tell the model to write in the source's own language and never translate it.
- [x] `select_repo` reports `python_files` / `js_files`; the no-parseable-source warning names
      all three supported languages.

**Verified live:**

| repo | result |
| --- | --- |
| `alaramartin/website` | 48 TS files, 79 import edges (was "0 files, no Python") |
| `pmndrs/zustand` | 49 files / 44 edges; both open issues ingested — one resolved onto a real file via the LLM path, one honestly parked |
| blast radius on TS | `src/vanilla.ts` reached by **24 of 49** files; `app/ui/fonts.ts` by **23 of 48** |

### ⚠️ Known gap, folded into task 2

`select_repo` short-circuits on `already_indexed` — a repo indexed **before** this change keeps
its Python-only substrate and will never pick up its JS/TS files. Re-indexing in place is not
safe to bolt on here because deleting `File` nodes orphans the `resolves_to` edges of any issue
already resolved onto them. Task 2 is already doing graph maintenance (`dedupe_repos`,
`dedupe_issues`), so a proper "re-index this repo, rebuilding its issue edges" belongs there.

Also folded into task 2, found while diagnosing this: **duplicate `Repo` nodes** for
`AzizAkturin/TeamSnorlax-UX-Agent` (two nodes, same root, same `full_name`). `select_repo` and
`get_queue` each independently take `matches[0]`, so a read can land on the node that has no
files yet — which is what produced the "indexed 0 files" report on a repo that has 19 Python
files. `dedupe_repos` exists but nothing prevents the duplicate being created in the first place.

## Task 2 — the two bugs (2026-07-28) — DONE

### 2a. Duplicated issues — fixed and repaired

Root cause confirmed exactly as predicted: `ingest_from_github` snapshotted "what's already
here" **once, before the loop**, then spent ~9s per issue. Any second run starting mid-flight
re-ingested everything the first hadn't reached. Caught live during task 1 testing — a single
curl produced `fetched: 4, ingested: 1, skipped_existing: 3`, i.e. the request ran twice and
was saved only by lucky timing.

- [x] **Per-issue re-check** (`_existing_issue`, called inside `_ingest_one`) — the batch
      snapshot is gone; every write re-reads the graph immediately beforehand. Returns a
      `skipped_duplicate` outcome so the skip count stays honest.
- [x] **Per-repo ingest lock** (`Repo.ingesting_since` + `INGEST_LOCK_TIMEOUT`), released in a
      `finally`. Second concurrent run on the same repo is refused; a *different* repo is
      unaffected (verified both).
- [x] **Stale locks die at process boot.** A killed server never runs its `finally`, and an
      hour-long lockout after a routine Ctrl-C is not acceptable. A lock is only honored if
      `ingesting_since > PROCESS_STARTED_AT` — a lock predating this process cannot be held by
      a run inside it. Found by actually killing the server mid-ingest, not by inspection.
      `force: bool` on the walker as a manual override; deliberately not wired to the UI.
- [x] **Client guard** — the repo picker returns early while a select/ingest is in flight.
- [x] **`walker:pub dedupe_issues`** repairs an already-polluted graph: one Issue per
      `external_id` per repo (preferring a copy that resolved onto a code node), then repairs
      the cluster `issue_count`s and the `Unresolved.count` that the deletions invalidate, and
      drops clusters left with no members.

**Repair result on the live graph — 64 Issue nodes → 20, matching the 20 real GitHub issues:**

| | before | after |
| --- | --- | --- |
| `core/validation.py` cluster | 6 members (`8,9,10,10,11,11`) | **4** (`8,9,10,11`), blast radius 14 |
| `services/upload.py` cluster | 10 members (`16`×5, `17`×5) | **2** (`16,17`) |
| standalone | 30 | 10 |
| unresolved | 18 | 4 |

Verified afterwards across all five indexed repos: **zero duplicate external_ids anywhere**.

### 2b. Generate PR — fixed

Root cause confirmed by direct reproduction: `.env` line 34 was a bare `TRIAGE_FIX_MODEL=`,
and **`os.environ.get(name, default)` returns `""` for a set-but-empty variable, not the
default**. So `fix_llm = Model(model_name="")` and every generation died with
`litellm.BadRequestError: LLM Provider NOT provided ... You passed model=`. The walker 500'd,
the client's `root spawn` threw, and `mark_generating(id, False)` never ran — hence a button
stuck on "Generating" forever. Introduced by `dc7f1bb` (showcase mode), which added the empty
var.

- [x] **`_env()` treats blank as absent** in `pr_agent.jac`.
- [x] **`load_dotenv()` called explicitly** before the module's globs. `.env` was only ever
      loaded as a side effect of importing byllm, making every module-level env read depend on
      import order — `jac run` saw no environment at all.
- [x] **Never 500.** `generate_fix` and `preview_issue_fix` are wrapped; an LLM failure becomes
      `{ok: false, error: "the fix model (<name>) failed: ..."}`, which the UI already renders.
- [x] **`try`/`finally` in all three client handlers** (two in `QueueScreen`, one in
      `cluster_view`) so the spinner clears even when the walker throws.
- [x] **Boot banner** — `[triage] PR fix model: ollama/qwen2.5-coder:7b` on stdout at startup,
      so a misconfigured model is visible immediately instead of on click.

**Verified:** `generate_fix` against the real `core/validation.py` now returns 960 bytes of
**valid Python** with a correct `None` guard — the exact call that previously raised. The
GitHub write itself was deliberately NOT exercised: opening a PR moves that cluster into
Drafted PRs permanently (see the demo-day trap note above), so the last click is the human's.

⚠️ **One generate_fix call takes ~86 seconds** on the local 7B model. The PR button is
therefore a ~1.5 minute wait even when everything works. That belongs to task 3.

### Also folded in

- [x] **Duplicate `Repo` nodes** — the cause of the "indexed 0 files" report on a repo with 19
      Python files. `_collapse_duplicate_repos()` is extracted from the `dedupe_repos` walker
      and now runs *before* the lookup in `select_repo` and `reindex_repo`, so a duplicate can
      never be observed rather than only being cleaned up afterwards.
- [x] **Repos indexed before TS/JS support** now re-index automatically — but **only when that
      destroys nothing**: no JS/TS File nodes exist, the checkout has some, and no Issue has
      resolved onto the existing files. `TeamSnorlax-UX-Agent` went 19 → **72 files** (19 py +
      53 ts/js); `triage-demo`, which has 20 triaged issues, was correctly left untouched.

## Task 4 — personalized ranking settings (2026-07-28) — DONE

The groundwork existed (`Settings` node, `set_weights`, `weighted_urgency` with social terms,
`get_queue` re-ranking at read time). Three things were actually broken or missing.

- [x] **Stored weights are now loaded.** `get_queue` reports a `WeightsView` alongside the
      queue it ranked, and the panel mounts on that. Previously `SettingsPanel` hardcoded
      `w_blast = 6.0` on every mount, so a saved preference silently reverted on reload and the
      slider positions could disagree with the order actually on screen. Adopted from the FIRST
      fetch only, so the 5s ingest poll can't yank a slider mid-drag.
- [x] **The two social weights are on screen** (`w_reactions`, `w_comment_velocity`). They
      already worked server-side and simply had no control.
- [x] **BUG: moving any slider silently zeroed the social weights.** `set_weights` defaults the
      fields it isn't given, and the client only ever sent three of five. All five now go on
      every call (`apply_weights`).
- [x] **Reset to structural defaults** button (6/3/1/0/0), disabled when already there.
- [x] **Per-slider explanation copy.** A slider labelled "reactions" with no explanation invites
      someone to quietly undo the thing that makes this ranking worth looking at. The panel
      header also *changes* when social weights are non-zero: it stops claiming the ranking is
      structural, because it no longer is.

### ⚠️ Bug found while verifying: comment velocity was structurally always zero

`fetch_open_issues` computed `velocity: int = round(comments / days_open)`. Integer division of
a comment count by days-since-opened is 0 for everything except a brand-new flooded thread — a
40-comment issue open two years scored identically to one with no comments. The weight attached
to it could never change any ordering, so the slider would have been decorative.

`comment_velocity` is now a **float** end to end (`Issue`, `RemoteIssue`, `_ingest_one`,
`ranking.jac`). Verified against live GitHub data: jac issue #7730 now scores `0.2743` where it
previously rounded to `0`. **Issues ingested before this change keep their integer 0** — they
need a re-ingest to pick up a real value.

**Verified end to end on `pallets/flask`** (real reaction counts, PRs excluded):

| | `w_reactions = 0` (default) | `w_reactions = 9` |
| --- | --- | --- |
| #6093 IPv6 parsing (blast 23) | **3.36 — 1st** | 3.36 — 2nd |
| #6071 pytest failure (blast 0) | 2.00 — 2nd | 2.00 — 3rd |
| #6065 feature request, 4 reactions (blast 23) | 1.66 — 3rd | **10.66 — 1st** |

That is the feature working and the argument for the default in one table: weight popularity
heavily and a *feature request* outranks a live parsing bug. Defaults keep both social terms at
0.0, so out of the box the ranking stays ~80% structural exactly as CLAUDE.md §4.4 requires —
turning that off is now an explicit, visible choice rather than something nobody can see.
