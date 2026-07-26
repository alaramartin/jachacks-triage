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
    owns,
    resolves_to,
    grouped_in,
    cluster_targets,
    fixes
}
import from integrations.ast_parser { build_code_substrate, count_import_edges }
import from agents.blast_radius { compute_blast_radius, build_dependency_graph }

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
            repo = (root ++> Repo(full_name=self.full_name))[0];
        }

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
            cluster_views.append(
                ClusterView(
                    id=jid(c),
                    title=c.title,
                    target_path=target_path,
                    blast_radius=c.blast_radius,
                    issue_count=c.issue_count,
                    max_severity=max_sev,
                    urgency=c.urgency,
                    fix_confidence=c.fix_confidence,
                    issues=issue_views
                )
            );
        }
        cluster_views.sort(key=lambda c: ClusterView : c.urgency, reverse=True);

        singleton_views: list[SingletonView] = [];
        unresolved_views: list[UnresolvedView] = [];

        for i in all_issues {
            if jid(i) in clustered_issue_ids {
                continue;
            }
            resolved: list[File] = [i->:resolves_to:->];
            if len(resolved) > 0 {
                singleton_views.append(
                    SingletonView(
                        id=jid(i),
                        external_id=i.external_id,
                        title=i.title,
                        target_path=resolved[0].path,
                        blast_radius=resolved[0].blast_radius,
                        severity=i.severity,
                        urgency=i.urgency,
                        resolution_method=i.resolution_method
                    )
                );
            } else {
                unresolved_views.append(
                    UnresolvedView(id=jid(i), external_id=i.external_id, title=i.title)
                );
            }
        }
        singleton_views.sort(key=lambda s: SingletonView : s.urgency, reverse=True);

        report QueueResponse(
            repo=repo.full_name,
            file_count=repo.file_count,
            clusters=cluster_views,
            singletons=singleton_views,
            unresolved=unresolved_views
        );
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
