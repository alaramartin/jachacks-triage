"""API surface - every walker:pub endpoint lives here (CLAUDE.md #6).
SHARED FILE - highest merge-conflict risk. One endpoint per person per commit.
Pull before you touch it. Never reformat the whole file. See CLAUDE.md #9."""

import from graph.nodes { Repo, File, Issue, Cluster, PullRequest, Unresolved, owns, resolves_to, parked, grouped_in, cluster_targets, fixes }
import from integrations.ast_parser { build_code_substrate, count_import_edges }
import from agents.blast_radius { compute_blast_radius, maybe_compute_blast_radius }
import from agents.triage_agent { resolve_issue, assess_severity, estimate_diff_size }
import from integrations.github { create_pull_request }

# ============================== Person 1 — Graph & Agents ==============================

walker:pub reindex_repo {
    has repo_path: str;
    has full_name: str;

    can build with Root entry {
        existing: list[Repo] = [root -->][?:Repo, full_name == self.full_name];
        repo: Repo;
        if len(existing) > 0 {
            repo = existing[0];
        } else {
            repo = root ++> Repo(full_name=self.full_name);
        }

        already_indexed: list[File] = [repo ->:owns:->][?:File];
        if len(already_indexed) > 0 {
            # Idempotent: reindex_repo is safe to call repeatedly during rehearsal
            # without duplicating File nodes or resetting computed blast radii.
            report {
                "ok": True,
                "files_indexed": repo.file_count,
                "import_edges": count_import_edges(already_indexed)
            };
        } else {
            stats: dict[str, int] = build_code_substrate(self.repo_path, repo);
            report {
                "ok": True,
                "files_indexed": stats["files_indexed"],
                "import_edges": stats["import_edges"]
            };
        }
    }
}

walker:pub reset_demo {
    can wipe with Root entry {
        for repo in [root -->][?:Repo] {
            for i in [repo ->:owns:->][?:Issue] { del i; }
            for c in [repo ->:owns:->][?:Cluster] { del c; }
            for p in [repo ->:owns:->][?:PullRequest] { del p; }
            for u in [repo ->:owns:->][?:Unresolved] { del u; }
        }
        report {"ok": True};
    }
}

walker:pub debug_blast {
    has path: str;

    can find with Root entry {
        for repo in [root -->][?:Repo] {
            matches: list[File] = [repo ->:owns:->][?:File, path == self.path];
            if len(matches) > 0 {
                report compute_blast_radius(matches[0]);
                disengage;
            }
        }
        report -1;
    }
}

# ======================= Person 2 — Ingestion, LLM & PR action =======================
# NOTE: `clustered_into` / `urgency` are placeholders (null / 0.0) until Person 1 ships
# clustering.jac + ranking.jac (PLAN.md Phase B). Never hardcode a fake value here -
# once those agents exist, wire their output in instead of filling these two fields.

walker:pub ingest_issue {
    has external_id: str;
    has title: str;
    has body: str;
    has created_at: str;
    has reactions: int = 0;
    has comment_velocity: int = 0;

    can ingest with Root entry {
        repos: list[Repo] = [root -->][?:Repo];
        if len(repos) == 0 {
            report {"ok": False, "error": "no repo indexed - call reindex_repo first"};
            disengage;
        }
        repo: Repo = repos[0];

        files: list[File] = [repo ->:owns:->][?:File];
        file_paths: list[str] = [f.path for f in files];

        # TODO(P1): once Repo stores the on-disk repo_path it was indexed from,
        # pass that through instead of this seed-demo convention (also used as
        # the reindex_repo request's repo_path throughout CLAUDE.md #6).
        resolution = resolve_issue(self.title, self.body, file_paths, repo_root="seed/repo");
        severity: int = assess_severity(self.title, self.body);
        diff_lines: int = estimate_diff_size(self.title, self.body);

        issue: Issue = Issue(
            external_id=self.external_id,
            title=self.title,
            body=self.body,
            created_at=self.created_at,
            severity=severity,
            estimated_diff_lines=diff_lines,
            resolution_confidence=resolution.confidence,
            resolution_method=resolution.method,
            reactions=self.reactions,
            comment_velocity=self.comment_velocity,
        );
        repo +>:owns:+> issue;

        if resolution.path is None {
            unresolved_matches: list[Unresolved] = [repo ->:owns:->][?:Unresolved];
            unresolved: Unresolved;
            if len(unresolved_matches) > 0 {
                unresolved = unresolved_matches[0];
            } else {
                unresolved = Unresolved();
                repo +>:owns:+> unresolved;
            }
            unresolved +>:parked:+> issue;
            unresolved.count += 1;
            report {
                "issue_id": jid(issue),
                "resolved_to": None,
                "resolution_method": "none",
                "parked": True
            };
            disengage;
        }

        target_matches: list[File] = [f for f in files if f.path == resolution.path];
        target: File = target_matches[0];
        issue +>:resolves_to:+> target;
        maybe_compute_blast_radius(target);

        report {
            "issue_id": jid(issue),
            "resolved_to": target.path,
            "resolution_method": resolution.method,
            "confidence": resolution.confidence,
            "severity": severity,
            "clustered_into": None,
            "urgency": 0.0
        };
    }
}

# generate_pr is human-triggered ONLY (CLAUDE.md #2: no automatic PR generation).
# create_pull_request is a Phase B STUB (integrations/github.jac) returning a
# fake but stable PR - Phase C swaps it for a real GitHub API call behind the
# same signature, so this walker does not change.
walker:pub generate_pr {
    has cluster_id: str;

    can generate with Root entry {
        cluster: any = None;
        try {
            cluster = jobj(self.cluster_id);
        } except Exception {
            cluster = None;
        }
        if not isinstance(cluster, Cluster) {
            report {"ok": False, "error": "cluster not found"};
            disengage;
        }

        repos: list[Repo] = [root -->][?:Repo];
        if len(repos) == 0 {
            report {"ok": False, "error": "no repo indexed"};
            disengage;
        }
        repo: Repo = repos[0];

        targets: list[File] = [cluster ->:cluster_targets:->][?:File];
        target_path: str = cluster.cluster_key;
        if len(targets) > 0 {
            target_path = targets[0].path;
        }

        title: str = f"fix: {cluster.cluster_key}";
        if cluster.title {
            title = f"fix({target_path}): {cluster.title}";
        }
        body: str = cluster.root_cause_summary;

        result = create_pull_request(repo.full_name, title, body);
        if not result.ok {
            report {"ok": False, "error": result.error};
            disengage;
        }

        pr: PullRequest = PullRequest(
            number=result.pr_number,
            url=result.pr_url,
            status="open",
            title=title,
            body=body,
        );
        repo +>:owns:+> pr;
        pr +>:fixes:+> cluster;

        report {
            "ok": True,
            "pr_number": result.pr_number,
            "pr_url": result.pr_url,
            "title": title,
            "files_changed": [target_path]
        };
    }
}
