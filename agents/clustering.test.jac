import from byllm.lib { MockLLM }
import from graph.nodes { Repo, File, Issue, owns, resolves_to }

glob llm = MockLLM(
         model_name="mockllm",
         config={
             "outputs": [
                 RootCauseGate(
                     same_root_cause=True,
                     title="require_fields() crashes on None/unicode",
                     root_cause_summary="None guard + unicode-safe truncation missing.",
                     proposed_fix_summary="Add a None guard and normalize unicode before length checks."
                 ),
                 RootCauseGate(
                     same_root_cause=False,
                     title="",
                     root_cause_summary="",
                     proposed_fix_summary=""
                 )
             ]
         }
     );

test "5 issues sharing one root cause form a single cluster" {
    repo = Repo(full_name="t/validation", file_count=18);
    target = repo +>:owns:+> File(path="core/validation.py", blast_radius=14);

    members: list[Issue] = [];
    for n in range(5) {
        i = repo +>:owns:+> Issue(
            external_id=f"SEED-0{n + 1}",
            title=f"bug {n}",
            body="crash report",
            created_at="2026-01-01",
            severity=9,
            estimated_diff_lines=10
        );
        i +>:resolves_to:+> target;
        members.append(i);
    }

    cluster = maybe_cluster(target);

    assert cluster is not None;
    assert cluster.issue_count == 5;
    assert cluster.blast_radius == 14;
    assert cluster.proposed_fix_summary == "Add a None guard and normalize unicode before length checks.";
    assert len([target<-:resolves_to:<-]) == 5;
}

test "two issues on the same file with different root causes do NOT cluster (SEED-15/16 guard)" {
    repo = Repo(full_name="t/orders", file_count=18);
    target = repo +>:owns:+> File(path="services/orders.py", blast_radius=1);

    typo = repo +>:owns:+> Issue(
        external_id="SEED-15",
        title="Typo in confirmation message",
        body="'recieved' should be 'received'",
        created_at="2026-01-01",
        severity=1,
        estimated_diff_lines=1
    );
    typo +>:resolves_to:+> target;

    perf = repo +>:owns:+> Issue(
        external_id="SEED-16",
        title="Orders list takes 30s with 10k rows",
        body="perf: full table scan",
        created_at="2026-01-01",
        severity=6,
        estimated_diff_lines=40
    );
    perf +>:resolves_to:+> target;

    cluster = maybe_cluster(target);

    assert cluster is None;
}
