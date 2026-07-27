"""API surface - every walker:pub endpoint lives here (CLAUDE.md #6).
SHARED FILE - highest merge-conflict risk. One endpoint per person per commit.
Pull before you touch it. Never reformat the whole file. See CLAUDE.md #9."""

import from graph.nodes {
    Repo,
    File,
    Issue,
    Cluster,
    PullRequest,
    Unresolved,
    Settings,
    owns,
    resolves_to,
    parked,
    grouped_in,
    cluster_targets,
    fixes
}
import from integrations.ast_parser { build_code_substrate, count_import_edges }
import from agents.blast_radius { compute_blast_radius, build_dependency_graph }
import from agents.triage_agent { resolve_issue, assess_severity, estimate_diff_size }
import from agents.ranking {
    on_issue_resolved,
    weighted_urgency,
    weighted_cluster_urgency
}
import from agents.pr_agent {
    build_pr_for_cluster,
    build_pr_for_issue,
    preview_issue_fix,
    IssueFixPreview
}
import from integrations.github { fetch_open_issues, RemoteIssue }

# ============================== Person 1 — Graph & Agents ==============================
walker:pub reindex_repo {
    has repo_path: str;
    has full_name: str;

    can build with Root entry {
        existing: list[Repo] = [root-->][?:Repo, full_name==self.full_name];
        repo: Repo;
        if len(existing) > 0 {
            repo = existing[0];
        } else {
            # NO `[0]` here - on the demo machine (jac 0.34.7) `++>` returns the
            # bare node; indexing it fails. P1's and P3's machines return a list
            # and DO need `[0]`. See PLAN.md's environment-split table before
            # "fixing" this in either direction.
            repo = root ++> Repo(full_name=self.full_name);
        }
        # Remember where this repo lives on disk so ingest_issue, clustering
        # and pr_agent can read real source instead of assuming "seed/repo".
        repo.repo_path = self.repo_path;

        already_indexed: list[File] = [repo->:owns:->][?:File];
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
        for repo in [root-->][?:Repo] {
            for i in [repo->:owns:->][?:Issue] {
                del i;
            }
            for c in [repo->:owns:->][?:Cluster] {
                del c;
            }
            for p in [repo->:owns:->][?:PullRequest] {
                del p;
            }
            for u in [repo->:owns:->][?:Unresolved] {
                del u;
            }
        }
        report {"ok": True};
    }
}

walker:pub debug_blast {
    has path: str;

    can find with Root entry {
        for repo in [root-->][?:Repo] {
            matches: list[File] = [repo->:owns:->][?:File, path==self.path];
            if len(matches) > 0 {
                report compute_blast_radius(matches[0]);
                disengage;
            }
        }
        report -1;
    }
}

# ======================= Person 2 — Ingestion, LLM & PR action =======================
# Shared by ingest_issue (one issue at a time, e.g. the live-ingestion demo
# beat) and ingest_from_github (a whole repo's open issues at once) so both
# entry points run the exact same Agent 1->2->3->4 cascade and can't drift.
def _ingest_one(
    repo: Repo,
    external_id: str,
    title: str,
    body: str,
    created_at: str,
    reactions: int,
    comment_velocity: int
) -> dict {
    files: list[File] = [repo->:owns:->][?:File];
    file_paths: list[str] = [f.path for f in files];

    resolution = resolve_issue(title, body, file_paths, repo_root=repo.repo_path);
    severity: int = assess_severity(title, body);
    diff_lines: int = estimate_diff_size(title, body);

    issue: Issue = Issue(
        external_id=external_id,
        title=title,
        body=body,
        created_at=created_at,
        severity=severity,
        estimated_diff_lines=diff_lines,
        resolution_confidence=resolution.confidence,
        resolution_method=resolution.method,
        reactions=reactions,
        comment_velocity=comment_velocity,
    );
    repo +>:owns:+> issue;

    if resolution.path is None {
        unresolved_matches: list[Unresolved] = [repo->:owns:->][?:Unresolved];
        unresolved: Unresolved;
        if len(unresolved_matches) > 0 {
            unresolved = unresolved_matches[0];
        } else {
            unresolved = Unresolved();
            repo +>:owns:+> unresolved;
        }
        unresolved +>:parked:+> issue;
        unresolved.count += 1;
        return {
            "issue_id": jid(issue),
            "resolved_to": None,
            "resolution_method": "none",
            "parked": True
        };
    }

    target_matches: list[File] = [
        f
        for f in files
        if f.path == resolution.path
    ];
    target: File = target_matches[0];
    issue +>:resolves_to:+> target;

    # Agent 2 -> 3 -> 4 cascade (blast radius -> clustering -> ranking),
    # triggered the same way CLAUDE.md #5 describes: writing the resolves_to
    # edge, then downstream agents re-read graph state fresh rather than
    # being handed values directly.
    on_issue_resolved(issue, target, repo);

    clustered_into: str | None = None;
    issue_clusters: list[Cluster] = [issue->:grouped_in:->];
    if len(issue_clusters) > 0 {
        clustered_into = issue_clusters[0].cluster_key;
    }

    return {
        "issue_id": jid(issue),
        "resolved_to": target.path,
        "resolution_method": resolution.method,
        "confidence": resolution.confidence,
        "severity": severity,
        "clustered_into": clustered_into,
        "urgency": issue.urgency
    };
}

walker:pub ingest_issue {
    has external_id: str;
    has title: str;
    has body: str;
    has created_at: str;
    has reactions: int = 0;
    has comment_velocity: int = 0;

    can ingest with Root entry {
        repos: list[Repo] = [root-->][?:Repo];
        if len(repos) == 0 {
            report {"ok": False, "error": "no repo indexed - call reindex_repo first"};
            disengage;
        }
        repo: Repo = repos[0];

        report _ingest_one(
            repo,
            self.external_id,
            self.title,
            self.body,
            self.created_at,
            self.reactions,
            self.comment_velocity
        );
    }
}

# Pulls a repo's OPEN issues straight from the GitHub REST API and runs each
# one through the same Agent 1 cascade as ingest_issue - this is what lets
# Triage point at any real repo's real issue queue instead of a canned
# issues.json fixture (CLAUDE.md's "nothing should be hardcoded" rule).
# Safe to call repeatedly: issues already present (matched by external_id,
# which is the GitHub issue number) are skipped rather than duplicated.
walker:pub ingest_from_github {
    has full_name: str = "";

    can ingest with Root entry {
        repos: list[Repo] = [root-->][?:Repo];
        if len(repos) == 0 {
            report {"ok": False, "error": "no repo indexed - call reindex_repo first"};
            disengage;
        }
        repo: Repo = repos[0];
        target_full_name: str = self.full_name if self.full_name else repo.full_name;

        already: set[str] = {i.external_id for i in [repo->:owns:->][?:Issue]};

        remote_issues: list[RemoteIssue] = fetch_open_issues(target_full_name);
        results: list[dict] = [];
        skipped: int = 0;
        for ri in remote_issues {
            if ri.external_id in already {
                skipped += 1;
                continue;
            }
            results.append(
                _ingest_one(
                    repo,
                    ri.external_id,
                    ri.title,
                    ri.body,
                    ri.created_at,
                    ri.reactions,
                    ri.comment_velocity
                )
            );
        }

        report {
            "ok": True,
            "repo": target_full_name,
            "fetched": len(remote_issues),
            "ingested": len(results),
            "skipped_existing": skipped,
            "results": results
        };
    }
}

# generate_pr is human-triggered ONLY (CLAUDE.md #2: no automatic PR generation).
# All GitHub-specific + LLM-fix domain logic lives in agents/pr_agent.jac
# (Person 2) - this walker just resolves the cluster/repo and reports the result.
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

        repos: list[Repo] = [root-->][?:Repo];
        if len(repos) == 0 {
            report {"ok": False, "error": "no repo indexed"};
            disengage;
        }
        repo: Repo = repos[0];

        targets: list[File] = [cluster->:cluster_targets:->][?:File];
        target_path: str = cluster.cluster_key;
        if len(targets) > 0 {
            target_path = targets[0].path;
        }

        result = build_pr_for_cluster(cluster, repo);
        if not result.ok {
            report {"ok": False, "error": result.error};
            disengage;
        }

        title: str = f"fix: {cluster.cluster_key}";
        if cluster.title {
            title = f"fix({target_path}): {cluster.title}";
        }

        pr: PullRequest = PullRequest(
            number=result.pr_number,
            url=result.pr_url,
            status="open",
            title=title,
            body=cluster.root_cause_summary,
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

# Same human-only trigger as generate_pr, for a standalone issue that never
# clustered. The cluster stays the headline unit of action (CLAUDE.md #2) -
# this just means a lone issue isn't a dead end in the UI.
walker:pub generate_pr_for_issue {
    has issue_id: str;

    can generate with Root entry {
        issue: any = None;
        try {
            issue = jobj(self.issue_id);
        } except Exception {
            issue = None;
        }
        if not isinstance(issue, Issue) {
            report {"ok": False, "error": "issue not found"};
            disengage;
        }

        repos: list[Repo] = [root-->][?:Repo];
        if len(repos) == 0 {
            report {"ok": False, "error": "no repo indexed"};
            disengage;
        }
        repo: Repo = repos[0];

        targets: list[File] = [issue->:resolves_to:->][?:File];
        target_path: str = targets[0].path if len(targets) > 0 else "";

        result = build_pr_for_issue(issue, repo);
        if not result.ok {
            report {"ok": False, "error": result.error};
            disengage;
        }

        title: str = f"fix({target_path}): {issue.title}"
            if target_path
            else f"fix: {issue.title}";

        pr: PullRequest = PullRequest(
            number=result.pr_number,
            url=result.pr_url,
            status="open",
            title=title,
            body=issue.title,
        );
        repo +>:owns:+> pr;
        # CLAUDE.md #4.2 documents `fixes` as PullRequest -> Cluster; a
        # standalone issue has no Cluster, so the same edge lands on the Issue.
        # Nothing reads it in the other direction, so this is additive.
        pr +>:fixes:+> issue;

        report {
            "ok": True,
            "pr_number": result.pr_number,
            "pr_url": result.pr_url,
            "title": title,
            "files_changed": [target_path]
        };
    }
}

# Powers the hover card on the queue's standalone rows: two sentences, "the
# issue" and "the fix". Same by llm() call generate_pr_for_issue uses to derive
# a root cause, so what you read on hover is what the PR gets built from.
walker:pub get_issue_fix_preview {
    has issue_id: str;

    can preview with Root entry {
        issue: any = None;
        try {
            issue = jobj(self.issue_id);
        } except Exception {
            issue = None;
        }
        if not isinstance(issue, Issue) {
            report {"ok": False, "error": "issue not found"};
            disengage;
        }

        targets: list[File] = [issue->:resolves_to:->][?:File];
        if len(targets) == 0 {
            report {"ok": False, "error": "issue isn't resolved onto a file"};
            disengage;
        }

        preview: IssueFixPreview = preview_issue_fix(
            targets[0].path, issue.title, issue.body
        );
        report {
            "ok": True,
            "issue_summary": preview.issue_summary,
            "fix_summary": preview.fix_summary
        };
    }
}

# ======================= Person 1 — Queue + Cluster Detail (Phase B/C) =======================
obj IssueSummary {
    has id: str;
    has external_id: str;
    has title: str;
    has severity: int;
    has resolution_method: str;
}

obj ClusterView {
    has id: str;
    has title: str;
    has target_path: str;
    has blast_radius: int;
    has issue_count: int;
    has max_severity: int;
    has urgency: float;
    has fix_confidence: float;
    has issues: list[IssueSummary];
    # A PR already drafted for this cluster (via the `fixes` edge). Empty url
    # means none - the UI files those with a PR into its "Drafted PRs" section,
    # so the state survives a page reload instead of living only in React.
    has pr_number: int = 0;
    has pr_url: str = "";
}

obj SingletonView {
    has id: str;
    has external_id: str;
    has title: str;
    has target_path: str;
    has blast_radius: int;
    has severity: int;
    has urgency: float;
    has resolution_method: str;
    has pr_number: int = 0;
    has pr_url: str = "";
}

obj UnresolvedView {
    has id: str;
    has external_id: str;
    has title: str;
}

obj QueueResponse {
    has repo: str;
    has file_count: int;
    has clusters: list[ClusterView];
    has singletons: list[SingletonView];
    has unresolved: list[UnresolvedView];
}

walker:pub get_queue {
    has full_name: str;
    has reports: list[QueueResponse] = [];

    can build with Root entry {
        matches: list[Repo] = [root-->][?:Repo, full_name==self.full_name];
        if len(matches) == 0 {
            report QueueResponse(
                repo=self.full_name,
                file_count=0,
                clusters=[],
                singletons=[],
                unresolved=[]
            );
            disengage;
        }
        repo: Repo = matches[0];

        all_issues: list[Issue] = [repo->:owns:->][?:Issue];
        all_clusters: list[Cluster] = [repo->:owns:->][?:Cluster];

        # (REACH, PLAN.md Phase C step 3) Read-time re-rank against the repo's
        # current Settings - defaults to the locked blast-dominant weights if
        # set_weights was never called. Never touches the stored Issue/Cluster
        # .urgency (that stays whatever the ingest-time cascade wrote), so the
        # demo's default numbers are unaffected unless a viewer moves sliders.
        settings_matches: list[Settings] = [repo->:owns:->][?:Settings];
        settings: Settings = settings_matches[0]
            if len(settings_matches) > 0
            else Settings();
        max_reactions: int = max([i.reactions for i in all_issues], default=0);
        max_comment_velocity: int = max(
            [i.comment_velocity for i in all_issues], default=0
        );

        cluster_views: list[ClusterView] = [];
        clustered_issue_ids: set[str] = set();

        for c in all_clusters {
            targets: list[File] = [c->:cluster_targets:->];
            target_path: str = targets[0].path if len(targets) > 0 else "";
            members: list[Issue] = [c<-:grouped_in:<-];
            issue_views: list[IssueSummary] = [];
            max_sev: int = 0;
            for m in members {
                clustered_issue_ids.add(jid(m));
                if m.severity > max_sev {
                    max_sev = m.severity;
                }
                issue_views.append(
                    IssueSummary(
                        id=jid(m),
                        external_id=m.external_id,
                        title=m.title,
                        severity=m.severity,
                        resolution_method=m.resolution_method
                    )
                );
            }
            cluster_urgency: float = weighted_cluster_urgency(
                c.blast_radius,
                members,
                repo.file_count,
                max_reactions,
                max_comment_velocity,
                settings
            )
                if len(members) > 0
                else c.urgency;
            cluster_prs: list[PullRequest] = [c<-:fixes:<-][?:PullRequest];
            cluster_views.append(
                ClusterView(
                    id=jid(c),
                    title=c.title,
                    target_path=target_path,
                    blast_radius=c.blast_radius,
                    issue_count=c.issue_count,
                    max_severity=max_sev,
                    urgency=cluster_urgency,
                    fix_confidence=c.fix_confidence,
                    issues=issue_views,
                    pr_number=cluster_prs[0].number if len(cluster_prs) > 0 else 0,
                    pr_url=cluster_prs[0].url if len(cluster_prs) > 0 else ""
                )
            );
        }
        cluster_views.sort(
            key=lambda (c: ClusterView) { return c.urgency; }, reverse=True
        );

        singleton_views: list[SingletonView] = [];
        unresolved_views: list[UnresolvedView] = [];

        for i in all_issues {
            if jid(i) in clustered_issue_ids {
                continue;
            }
            resolved: list[File] = [i->:resolves_to:->];
            if len(resolved) > 0 {
                singleton_urgency: float = weighted_urgency(
                    resolved[0].blast_radius,
                    i.severity,
                    i.estimated_diff_lines,
                    i.reactions,
                    i.comment_velocity,
                    repo.file_count,
                    max_reactions,
                    max_comment_velocity,
                    settings
                );
                issue_prs: list[PullRequest] = [i<-:fixes:<-][?:PullRequest];
                singleton_views.append(
                    SingletonView(
                        id=jid(i),
                        external_id=i.external_id,
                        title=i.title,
                        target_path=resolved[0].path,
                        blast_radius=resolved[0].blast_radius,
                        severity=i.severity,
                        urgency=singleton_urgency,
                        resolution_method=i.resolution_method,
                        pr_number=issue_prs[0].number if len(issue_prs) > 0 else 0,
                        pr_url=issue_prs[0].url if len(issue_prs) > 0 else ""
                    )
                );
            } else {
                unresolved_views.append(
                    UnresolvedView(id=jid(i), external_id=i.external_id, title=i.title)
                );
            }
        }
        singleton_views.sort(
            key=lambda (s: SingletonView) { return s.urgency; }, reverse=True
        );

        report QueueResponse(
            repo=repo.full_name,
            file_count=repo.file_count,
            clusters=cluster_views,
            singletons=singleton_views,
            unresolved=unresolved_views
        );
    }
}

# (REACH, PLAN.md Phase C step 3) Writes the repo's personalization weights;
# get_queue re-ranks its response against whatever is stored here. The
# ingest-time cascade (on_issue_resolved) never reads this - the demo's
# stored urgency stays blast-dominant-by-default regardless of slider state.
walker:pub set_weights {
    has full_name: str;
    has w_blast: float = 6.0;
    has w_sev: float = 3.0;
    has w_diff: float = 1.0;
    has w_reactions: float = 0.0;
    has w_comment_velocity: float = 0.0;

    can build with Root entry {
        matches: list[Repo] = [root-->][?:Repo, full_name==self.full_name];
        if len(matches) == 0 {
            report {"ok": False, "error": "no repo indexed - call reindex_repo first"};
            disengage;
        }
        repo: Repo = matches[0];

        settings_matches: list[Settings] = [repo->:owns:->][?:Settings];
        settings: Settings = settings_matches[0]
            if len(settings_matches) > 0
            else repo +>:owns:+> Settings();

        settings.w_blast = self.w_blast;
        settings.w_sev = self.w_sev;
        settings.w_diff = self.w_diff;
        settings.w_reactions = self.w_reactions;
        settings.w_comment_velocity = self.w_comment_velocity;

        report {
            "ok": True,
            "w_blast": settings.w_blast,
            "w_sev": settings.w_sev,
            "w_diff": settings.w_diff,
            "w_reactions": settings.w_reactions,
            "w_comment_velocity": settings.w_comment_velocity
        };
    }
}

obj IssueDetail {
    has id: str;
    has external_id: str;
    has title: str;
    has body: str;
    has severity: int;
    has resolution_method: str;
}

obj ClusterDetailResponse {
    has id: str;
    has title: str;
    has root_cause_summary: str;
    has target_path: str;
    has blast_radius: int;
    has urgency: float;
    has fix_confidence: float;
    has proposed_fix_summary: str;
    has issues: list[IssueDetail];
    has graph: dict[str, list];
    has existing_pr: dict[str, object] | None;
}

walker:pub get_cluster_detail {
    has cluster_id: str;

    can build with Root entry {
        all_repos: list[Repo] = [root-->][?:Repo];
        matches: list[Cluster] = [];

        for r in all_repos {
            for c in [r->:owns:->][?:Cluster] {
                if jid(c) == self.cluster_id {
                    matches.append(c);
                }
            }
        }

        if len(matches) > 0 {
            cluster: Cluster = matches[0];
            targets: list[File] = [cluster->:cluster_targets:->];

            if len(targets) > 0 {
                target: File = targets[0];

                members: list[Issue] = [cluster<-:grouped_in:<-];
                issue_views: list[IssueDetail] = [];
                for m in members {
                    issue_views.append(
                        IssueDetail(
                            id=jid(m),
                            external_id=m.external_id,
                            title=m.title,
                            body=m.body,
                            severity=m.severity,
                            resolution_method=m.resolution_method
                        )
                    );
                }

                prs: list[PullRequest] = [cluster<-:fixes:<-][?:PullRequest];
                existing_pr: dict[str, object] | None = None;
                if len(prs) > 0 {
                    p: PullRequest = prs[0];
                    existing_pr = {
                        "number": p.number,
                        "url": p.url,
                        "status": p.status,
                        "title": p.title
                    };
                }

                report ClusterDetailResponse(
                    id=jid(cluster),
                    title=cluster.title,
                    root_cause_summary=cluster.root_cause_summary,
                    target_path=target.path,
                    blast_radius=cluster.blast_radius,
                    urgency=cluster.urgency,
                    fix_confidence=cluster.fix_confidence,
                    proposed_fix_summary=cluster.proposed_fix_summary,
                    issues=issue_views,
                    graph=build_dependency_graph(target),
                    existing_pr=existing_pr
                );
                disengage;
            }
        }

        report {"ok": False, "error": "cluster not found"};
    }
}

# ======================= Person 3 — Client entry point =======================
cl {
    import ".client/global.css";
    import from .client.app { app as ClientApp }

    def:pub app -> JsxElement {
        return <ClientApp/>;
    }
}
