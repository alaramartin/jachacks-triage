# CLAUDE.md — Triage

> Read this file **fully** before writing any code. It is the shared contract between three
> people working in parallel on a one-day build. If you deviate from the schema or the API
> shapes in this file, integration at 5:30 PM will fail and we will not have a demo.

Also, make sure to read PLAN.md at the beginning of every session.

## 1. What we are building

**Triage** — a new lens on the GitHub issue queue for repo maintainers.

Triage builds a live dependency graph of a repository, resolves every open issue onto the
code node it actually points at, then:

1. **Ranks by structural blast radius** — an issue's priority comes from how many files
   transitively depend on the code it touches, not from how dramatically it's worded.
2. **Clusters silently-duplicate issues** — five issues worded completely differently
   ("crashes on upload", "images look corrupted", "photo missing after edit") that all
   resolve to the same function are surfaced as **one** fixable cluster.
3. **Hands the maintainer a one-click PR** — Triage never opens a PR on its own. The human
   stays in control of the only consequential action.

**Hackathon:** JacHacks SF. Tracks we are submitting to: **Agentic AI** and **Best JacHammer
(Best Use of Jac)**. Hard deadline for submissions: **7:15 PM**. Partial submission
checkpoint: **5:50 PM** (mandatory to be considered for judging).

---

## 2. Non-negotiables

These are decided. Do not re-litigate them mid-build.

| Rule                                                                                 | Why                                                                                                                                                       |
| ------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Everything is Jac** — backend _and_ frontend.                                      | 40% Jac is a hard eligibility requirement, and Best JacHammer is a target prize.                                                                          |
| **No automatic PR generation.** PRs are created only when a human clicks the button. | This is our differentiator. Judges have seen auto-fix bots. "The agents do the analysis, the maintainer keeps the trigger" is a _stronger_ agentic pitch. |
| **The four agents hand off through graph state, not by calling each other.**         | This is the Best JacHammer sentence: _"our agents don't call each other, they react to shared graph state."_ See §5.                                      |
| **One graph, two node families.** Not two separate graphs.                           | Clustering falls out of the shared code substrate for free. See §4.                                                                                       |
| **The cluster is the unit of action.**                                               | Issues are clustered precisely because one PR fixes all of them.                                                                                          |
| **Blast radius is transitive reachability**, not just direct in-degree.              | More impressive, still simple, and gives dramatic numbers on our seed repo.                                                                               |
| **Ranking is visibly ~80% structural.** No upvote/comment-velocity signals.          | Any term a plain LLM could estimate dilutes the "only a graph can do this" claim.                                                                         |

Also, at the end, **NOTHING SHOULD BE HARDCODED**, particularly for the website/interface/dashboard. Person 3 may start with a mock data/graph, but by the end, make sure that it takes in REAL data FROM the repository (from the graph/walker agents that are person 1 and 2's jobs). At each checkpoint, and especially at the end of a person's task list, check whether the data being displayed is real or fake/hardcoded and make sure the human knows. If it's hardcoded data, it's incomplete.

### What NOT to build (scope guards)

- ❌ No auto-merge. Ever.
- ❌ No "reject PR + type feedback + regenerate" loop. **Parked as reach.** Only if everything
  else is done and tested by 6:00 PM.
- ❌ No support for multiple languages. Python only.
- ❌ No real-time GitHub webhook server. We simulate ingestion via a `walker:pub` endpoint
  (which is _also_ how the live demo beat works — see §8).
- ❌ No embeddings, no vector DB, no separate similarity index. Clustering comes from the
  graph. If you find yourself reaching for a vector store, you have misunderstood §4.

---

## 3. Project layout

```
triage/
  jac.toml
  main.jac                    # all walker:pub endpoints live here (the API surface)
  graph/
    nodes.jac                 # ALL node + edge definitions. Single source of truth.
  agents/
    triage_agent.jac          # Agent 1 — parse + resolve issue onto code node
    blast_radius.jac          # Agent 2 — transitive reverse-reachability
    clustering.jac            # Agent 3 — group issues sharing a code node
    ranking.jac               # Agent 4 — compute urgency
    pr_agent.jac              # NOT an agent on the loop. Human-triggered only.
  integrations/
    ast_parser.jac            # build File/imports graph from a Python repo
    github.jac                # OAuth + create PR
  client/
    app.jac                   # cl def:pub — login + dashboard + ranked queue
    cluster_view.jac          # cl — cluster detail + graph visualization
  seed/
    repo/                     # the 18-file seed Python repo (see PLAN.md §Seed Repo)
    issues.json               # the 20 seed issues
    seed.jac                  # loads seed/repo + seed/issues.json into the graph
  mocks/
    queue.json                # static mock of get_queue response — for P3 before C3
    cluster_detail.json       # static mock of get_cluster_detail response
```

---

## 4. THE GRAPH — single source of truth

**One graph. Two node families. Connected by `resolves_to` edges.**

- **Code substrate (permanent):** `File` nodes joined by `imports` edges. Exists whether or
  not any issue is open.
- **Issue layer (dynamic):** `Issue`, `Cluster`, `PullRequest` nodes that _attach_ to the code
  substrate.

**There are no issue↔issue edges.** Two issues are "the same problem" because they
`resolves_to` the _same code node_. A walker standing on a `File` node reads its incoming
`resolves_to` edges and **that is the cluster**. This is the whole elegance of doing it in Jac
— blast radius and clustering are two different walks over one structure.

### 4.1 Node definitions

> ⚠️ **Syntax check required.** The _shape_ of this model is locked. The exact Jac syntax for
> typed edges may differ from what's written here. In the first 15 minutes, run
> `claude mcp add jac -- jac mcp` and verify typed-edge and node syntax against the real docs
> (`jac guide`, or the Jac MCP server's docs tool). **Person 1 owns fixing the syntax and
> telling P2/P3 the final form.** Do not each independently guess at syntax.

```jac
node Repo {
    has full_name: str;
    has default_branch: str = "main";
    has file_count: int = 0;
}

node File {
    has path: str;              # e.g. "core/validation.py" — repo-relative, always POSIX slashes
    has language: str = "python";
    has loc: int = 0;
    has blast_radius: int = -1;  # -1 = not yet computed. Written by Agent 2.
}

node Issue {
    has external_id: str;              # "SEED-01" for seed data, GitHub number for real
    has title: str;
    has body: str;
    has created_at: str;               # ISO8601
    # --- written by Agent 1 (Triage) ---
    has severity: int = 0;             # 1-10, from by llm()
    has estimated_diff_lines: int = 0; # from by llm()
    has resolution_confidence: float = 0.0;
    has resolution_method: str = "";   # "explicit" | "llm" | "none"
    has root_cause_guess: str = "";
    # --- written by Agent 4 (Ranking) ---
    has urgency: float = 0.0;
}

node Cluster {
    has cluster_key: str;              # == the target File's path. One cluster per code node.
    has title: str = "";               # by llm() summary of the shared root cause
    has root_cause_summary: str = "";
    has blast_radius: int = 0;         # copied from target File by Agent 3/4
    has issue_count: int = 0;
    has urgency: float = 0.0;
    has fix_confidence: float = 0.0;   # how mechanically simple the fix looks, 0.0-1.0
}

node PullRequest {
    has number: int = 0;
    has url: str = "";
    has status: str = "open";
    has title: str = "";
    has body: str = "";
    has patch: str = "";
}

node Unresolved {                      # exactly ONE of these per Repo. The parking lot.
    has count: int = 0;
}
```

### 4.2 Edge definitions

```jac
edge owns {}              # Repo -> File | Issue | Cluster | Unresolved | PullRequest
edge imports {}           # File -> File.  DIRECTION IS CRITICAL. See 4.3.
edge resolves_to {}       # Issue -> File
edge grouped_in {}        # Issue -> Cluster
edge cluster_targets {}   # Cluster -> File
edge parked {}            # Unresolved -> Issue
edge fixes {}             # PullRequest -> Cluster
```

Anchoring: `root ++> Repo`, then `Repo -:owns:-> everything else`. Never attach a File or
Issue directly to `root` — always go through the Repo node, or the queue walkers won't find it.

### 4.3 ⚠️ Edge direction — the #1 source of bugs today

```
File_A  -:imports:->  File_B        means  "A imports B"  ⇒  "A depends on B"
```

Therefore:

- **Dependencies of A** = walk _forward_ along outgoing `imports` from A.
- **Dependents of B (what we want)** = walk _backward_ along **incoming** `imports` edges to B.
- **`blast_radius(B)` = the number of distinct `File` nodes that can transitively reach B by
  following `imports` forward** — i.e. a reverse BFS from B over incoming `imports` edges,
  with a `visited` set, **not counting B itself**.

If your blast radius numbers come out tiny (0, 1, 2) on `core/validation.py`, you have
traversed the wrong direction. The correct answer for our seed repo is **14**. That number is
your assertion. See PLAN.md for the full expected table.

### 4.4 The ranking formula (locked)

```
blast_norm = blast_radius / repo.file_count          # 0.0 - 1.0
sev_norm   = severity / 10.0                         # 0.0 - 1.0
diff_norm  = min(estimated_diff_lines / 100.0, 1.0)  # 0.0 - 1.0

urgency = (6.0 * blast_norm) + (3.0 * sev_norm) - (1.0 * diff_norm)
```

Constants live in **one** place: `agents/ranking.jac` as `W_BLAST = 6.0`, `W_SEV = 3.0`,
`W_DIFF = 1.0`. For a `Cluster`, use the cluster's `blast_radius`, the **max** `severity` of
its member issues, and the **max** `estimated_diff_lines`.

Say this out loud in the demo: _"the ranking is roughly 80% structural — you cannot get this
by reading the issues."_

### 4.5 The over-clustering guard (do not skip this)

Naive "same code node ⇒ same cluster" over-clusters. A typo in an error message and a
performance problem can both resolve to `services/orders.py` and they are **not** one fix.

**Agent 3 must therefore do two steps:**

1. Group candidates by shared target `File` node (pure graph read).
2. Gate each candidate with `by llm()`: _do these issues describe the same underlying root
   cause?_ If no, leave them as separate singletons attached to the same File.

This is a demo beat, not just correctness — it shows the system isn't naive. Seed issues
SEED-15 and SEED-16 both point at `services/orders.py` and **must not** cluster.

---

## 5. The four agents — triggers and graph handoffs

**The rule: each agent fires on a change in the graph, writes graph state, and the next agent
fires on _that_. No agent on the core loop calls another agent directly.**

| #   | Agent            | Fires when                                                                            | Reads                                                                     | Writes                                                                                                                                                      |
| --- | ---------------- | ------------------------------------------------------------------------------------- | ------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | **Triage**       | a new raw issue arrives (`ingest_issue`)                                              | raw issue text; list of File paths                                        | new `Issue` node; `resolves_to` edge **or** `parked` edge to `Unresolved`; `severity`, `estimated_diff_lines`, `resolution_confidence`, `resolution_method` |
| 2   | **Blast-Radius** | a new `resolves_to` edge appears on a File whose `blast_radius == -1`                 | `imports` edges (reverse BFS)                                             | `File.blast_radius`                                                                                                                                         |
| 3   | **Clustering**   | a `resolves_to` edge lands on a File that already has ≥1 other incoming `resolves_to` | incoming `resolves_to` edges of that File; issue text (for the §4.5 gate) | `Cluster` node, `grouped_in` + `cluster_targets` edges, `Cluster.title`, `root_cause_summary`, `issue_count`, `blast_radius`, `fix_confidence`              |
| 4   | **Ranking**      | any `urgency`-relevant property changed                                               | `blast_radius`, `severity`, `estimated_diff_lines`                        | `urgency` on `Issue` and `Cluster`                                                                                                                          |

**`pr_agent.jac` is NOT on this loop.** It fires only from the `generate_pr` endpoint when a
human clicks the button.

**Agent 1 resolution strategy — hybrid (locked):**

1. **Explicit signals first.** Regex the issue body for a Python traceback (`File "x.py", line
N`), a bare repo-relative path, or a `` `symbol` ``/`@symbol` mention that matches a known
   File. If found → `resolution_method = "explicit"`, `resolution_confidence = 0.95`.
2. **LLM fallback.** Pass the issue text plus the list of all File paths to a `by llm()`
   function that returns `(path, confidence)`. → `resolution_method = "llm"`.
3. **Threshold.** If `confidence < 0.55` → attach to the `Unresolved` node via `parked`,
   `resolution_method = "none"`. **Do not guess.** The visible "we couldn't confidently place
   these 3" bucket makes the whole system more credible to a judge, not less.

---

## 6. API contract — `walker:pub` endpoints

**This is the contract between backend (P1/P2) and frontend (P3). It is frozen at 10:45 AM.**
P3 builds against `mocks/*.json` until checkpoint C3. If a shape must change, it changes in
this file first and gets announced in the group chat.

Jac turns a `walker:pub` into a REST endpoint automatically; request bodies map onto walker
fields and `report` becomes the JSON response.

### `reindex_repo`

Request: `{ "repo_path": "seed/repo", "full_name": "triage-demo/shipyard" }`
Builds the code substrate. Report:

```json
{ "ok": true, "files_indexed": 18, "import_edges": 24 }
```

### `ingest_issue`

Request: `{ "external_id": "SEED-01", "title": "...", "body": "...", "created_at": "..." }`
Runs Agent 1, which cascades into 2 → 3 → 4 via graph state. Report:

```json
{
    "issue_id": "...",
    "resolved_to": "core/validation.py",
    "resolution_method": "explicit",
    "confidence": 0.95,
    "severity": 9,
    "clustered_into": "core/validation.py",
    "urgency": 7.22
}
```

If parked: `{ "issue_id": "...", "resolved_to": null, "resolution_method": "none", "parked": true }`

### `get_queue`

Request: `{ "full_name": "triage-demo/shipyard" }`
Report — **the main dashboard payload**:

```json
{
    "repo": "triage-demo/shipyard",
    "file_count": 18,
    "clusters": [
        {
            "id": "n:Cluster:...",
            "title": "require_fields() crashes on None and non-ASCII input",
            "target_path": "core/validation.py",
            "blast_radius": 14,
            "issue_count": 5,
            "max_severity": 9,
            "urgency": 7.22,
            "fix_confidence": 0.86,
            "issues": [
                {
                    "id": "n:Issue:...",
                    "external_id": "SEED-01",
                    "title": "Crash when submitting checkout form",
                    "severity": 9,
                    "resolution_method": "explicit"
                }
            ]
        }
    ],
    "singletons": [
        {
            "id": "n:Issue:...",
            "external_id": "SEED-17",
            "title": "Admin dashboard 500s on bulk edit",
            "target_path": "api/routes_admin.py",
            "blast_radius": 0,
            "severity": 9,
            "urgency": 2.4,
            "resolution_method": "llm"
        }
    ],
    "unresolved": [
        {
            "id": "n:Issue:...",
            "external_id": "SEED-19",
            "title": "doesn't work"
        }
    ]
}
```

`clusters` and `singletons` are each returned **sorted by `urgency` descending**. The frontend
does not sort; it renders in the order given. (One less place for the two of you to disagree.)

### `get_cluster_detail`

Request: `{ "cluster_id": "n:Cluster:..." }`
Report — powers the graph view:

```json
{
    "id": "n:Cluster:...",
    "title": "...",
    "root_cause_summary": "All five reports trace to require_fields(), which ...",
    "target_path": "core/validation.py",
    "blast_radius": 14,
    "urgency": 7.22,
    "fix_confidence": 0.86,
    "proposed_fix_summary": "Add a None guard and normalize unicode before length checks.",
    "issues": [
        {
            "id": "...",
            "external_id": "SEED-01",
            "title": "...",
            "body": "...",
            "severity": 9,
            "resolution_method": "explicit"
        }
    ],
    "graph": {
        "nodes": [
            {
                "id": "core/validation.py",
                "label": "core/validation.py",
                "role": "target"
            },
            {
                "id": "models/order.py",
                "label": "models/order.py",
                "role": "dependent",
                "hops": 2
            }
        ],
        "edges": [{ "from": "models/order.py", "to": "core/db.py" }]
    },
    "existing_pr": null
}
```

`role` is one of `"target" | "dependent" | "neutral"`. `hops` = BFS distance from target.
`edges` are in **code direction** (`from` imports `to`) — the frontend draws arrows however it
likes but must not assume the reverse.

### `generate_pr`

Request: `{ "cluster_id": "n:Cluster:..." }`
Report:

```json
{
    "ok": true,
    "pr_number": 7,
    "pr_url": "https://github.com/.../pull/7",
    "title": "fix(validation): guard require_fields against None and unicode input",
    "files_changed": ["core/validation.py"]
}
```

On failure: `{ "ok": false, "error": "human readable reason" }` — and the UI must show it
rather than spinning forever.

### `reset_demo`

Request: `{}` — wipes Issue/Cluster/PR nodes, keeps the code substrate. **Build this early.**
You will run the demo 10+ times in rehearsal and you do not want to rebuild the AST each time.

---

## 7. Jac conventions & gotchas

- **`by llm()` is a language feature, not an SDK call.** Declare the function with a
  meaningful name and typed args/return, and the compiler builds the prompt and enforces the
  return schema. Prefer an `enum` or a typed object return over parsing a string.
    ```jac
    enum Severity { TRIVIAL = 1, MINOR = 4, FUNCTIONAL = 7, CRITICAL = 10 }
    def assess_severity(title: str, body: str) -> Severity by llm();
    ```
- **Declare the model once in `jac.toml`**, run `jac install byllm`. Don't scatter model names.
- `walker:pub` = public REST endpoint. `report` = the JSON response body. Swagger appears at
  `/docs` — **use it to test the backend without the frontend existing.**
- Frontend: `cl def:pub app -> JsxElement { ... }` compiles to React. An `await` on a backend
  `def:pub` inside a client handler is a real RPC — the compiler writes the HTTP call and
  shares types. Do not hand-write `fetch()` if a typed RPC will do.
- `jac start --dev` for hot reload. `jac check` before every commit. `jac fmt` on save.
- The graph **persists automatically between runs** — there is no database to set up. This
  also means a bad run leaves junk in the graph. That's what `reset_demo` is for.
- **Wire the Jac MCP server into every Claude Code session before writing anything:**
    ```
    claude mcp add jac -- jac mcp
    ```
    It gives your session Jac validation, formatting, docs, and examples. Three sessions each
    guessing at syntax from training data is the single most likely way we lose the afternoon.

---

## 8. The demo we are building toward (4 minutes)

Every line of code should serve one of these beats. If a feature doesn't appear here, it is
not in scope today.

| Time      | Beat                                | What's on screen                                                                                                                                                                                                                                                                          |
| --------- | ----------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 0:00–0:45 | **The problem**                     | The raw seed repo's issue list — 20 issues, worded all over the place, flat and unsorted. "Which of these is actually breaking things? You can't tell by reading."                                                                                                                        |
| 0:45–2:00 | **The collapse** _(emotional peak)_ | The Triage dashboard: same 20 issues, now ranked — and 5 differently-worded tickets visibly merged into one top cluster, sitting **above** two much scarier-sounding issues. Point at the demoted loud ones explicitly.                                                                   |
| 2:00–3:00 | **The why**                         | Click the cluster → graph view. The walker traversal lights up **14 of 18** files downstream of one core utility. "This is why it's #1 — structural blast radius, computed by walking the graph, not read from the text." Also point at the 3 parked unresolved issues: "we don't guess." |
| 3:00–3:40 | **The controlled action**           | Hit _Generate PR_ → a real PR opens on GitHub with the 5 issues linked and the blast-radius summary in the body. "We never open this on our own. The maintainer keeps the trigger."                                                                                                       |
| 3:40–4:00 | **The Jac close**                   | One sentence on architecture: four agents, one graph, no direct calls between them.                                                                                                                                                                                                       |

**The Jac close, verbatim, memorize it:**

> "Four agents, one graph, and they never call each other. Triage writes an edge; the
> blast-radius agent fires because that edge appeared; clustering fires because two edges
> converged on the same node. The graph _is_ the coordination medium — that's Jac's model, not
> something we bolted on."

**Live ingestion beat (optional, if stable):** during beat 2, POST a brand-new 21st issue via
`ingest_issue` and let the dashboard update live to show it joining the top cluster. Only do
this if it has worked 3 times in rehearsal. Otherwise cut it — a failed live beat costs more
than it wins.

---

## 9. Ownership

| Area                                                                                                                       | Owner                                    | Don't edit if you're not the owner                                                           |
| -------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------- | -------------------------------------------------------------------------------------------- |
| `graph/nodes.jac`, `agents/blast_radius.jac`, `agents/clustering.jac`, `agents/ranking.jac`, `integrations/ast_parser.jac` | **Person 1**                             | Schema changes go through P1, announced in chat                                              |
| `seed/`, `agents/triage_agent.jac`, `agents/pr_agent.jac`, `integrations/github.jac`                                       | **Person 2**                             |                                                                                              |
| `client/`, `mocks/`                                                                                                        | **Person 3**                             |                                                                                              |
| `main.jac`                                                                                                                 | **shared — highest merge-conflict risk** | One endpoint per person per commit. Pull before you touch it. Never reformat the whole file. |

## 10. Git protocol

- Branches: `p1/graph`, `p2/agents`, `p3/client`. Never commit to `main` directly.
- **Do not commit by yourself, but remind your human to commit once a feature/phase/checkpoint is finished.** A repo with one giant 7:00 PM commit looks bad and is a rules risk.
- Tell the human to `main` **only at the numbered checkpoints** in PLAN.md by telling them specific commands. Ad-hoc merges are how a
  one-day project dies.
- Do not commit `.env`, API keys, or the OAuth client secret. Use `.env.example`. Make sure to create a relevant .gitignore.

## 11. Submission checklist (owner: Person 2, start at 5:30 PM)

- [ ] GitHub repo link, public
- [ ] **≥40% Jac in the repo** — verify with GitHub's language bar before submitting
- [ ] Demo video
- [ ] Written description, **explicitly stating how we used Jac** (graphs, walkers, `by llm()`)
- [ ] ⭐ Star `github.com/jaseci-labs/jac` — all three of us
- [ ] Devpost tracks selected: **Agentic AI** + **Best JacHammer**
- [ ] **Partial submission in by 5:50 PM** — you can keep editing after. Missing this means
      not being considered for judging at all.
