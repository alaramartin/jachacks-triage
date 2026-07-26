"""API surface - every walker:pub endpoint lives here (CLAUDE.md #6).
SHARED FILE - highest merge-conflict risk. One endpoint per person per commit.
Pull before you touch it. Never reformat the whole file. See CLAUDE.md #9."""

import from graph.nodes { Repo, File, Issue, Cluster, PullRequest, Unresolved, owns }
import from integrations.ast_parser { build_code_substrate, count_import_edges }
import from agents.blast_radius { compute_blast_radius }

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
            repo = (root ++> Repo(full_name=self.full_name))[0];
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
