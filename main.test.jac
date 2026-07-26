import from graph.nodes {
    Repo,
    File,
    Issue,
    Cluster,
    Unresolved,
    owns,
    resolves_to,
    grouped_in,
    cluster_targets,
    parked,
    imports
}

test "get_queue returns a cluster + singletons + unresolved, sorted by urgency desc" {
    # get_queue only READS graph state - clustering.jac and ranking.jac each
    # have their own by-llm-aware tests already. Build the target shape
    # directly (as maybe_cluster/rank_* would have left it) and check the
    # query/sort/serialization logic in isolation.
    repo = root ++> Repo(full_name="t/queue-e2e", file_count=18);
    validation = repo +>:owns:+> File(path="core/validation.py", blast_radius=14);
    orders = repo +>:owns:+> File(path="services/orders.py", blast_radius=1);
    unresolved_node = repo +>:owns:+> Unresolved();

    cluster_a = repo +>:owns:+> Cluster(
        cluster_key="core/validation.py",
        title="require_fields() crashes on None/unicode",
        blast_radius=14,
        issue_count=5,
        urgency=7.22,
        fix_confidence=0.86
    );
    cluster_a +>:cluster_targets:+> validation;
    for n in range(5) {
        i = repo +>:owns:+> Issue(
            external_id=f"E2E-0{n + 1}",
            title=f"bug {n}",
            body="crash report",
            created_at="2026-01-01",
            severity=9,
            resolution_method="explicit"
        );
        i +>:resolves_to:+> validation;
        i +>:grouped_in:+> cluster_a;
    }

    typo = repo +>:owns:+> Issue(
        external_id="E2E-15",
        title="Typo in confirmation message",
        body="'recieved' should be 'received'",
        created_at="2026-01-01",
        severity=1,
        resolution_method="llm",
        urgency=0.61
    );
    typo +>:resolves_to:+> orders;

    perf = repo +>:owns:+> Issue(
        external_id="E2E-16",
        title="Orders list takes 30s",
        body="perf: full table scan",
        created_at="2026-01-01",
        severity=6,
        resolution_method="llm",
        urgency=1.78
    );
    perf +>:resolves_to:+> orders;

    parked_issue = repo +>:owns:+> Issue(
        external_id="E2E-19",
        title="doesn't work",
        body="doesn't work",
        created_at="2026-01-01"
    );
    unresolved_node +>:parked:+> parked_issue;

    result = root spawn get_queue(full_name="t/queue-e2e");
    resp: QueueResponse = result.reports[0];

    assert resp.file_count == 18;
    assert len(resp.clusters) == 1;
    assert resp.clusters[0].target_path == "core/validation.py";
    assert resp.clusters[0].issue_count == 5;
    assert resp.clusters[0].blast_radius == 14;
    assert resp.clusters[0].max_severity == 9;
    assert len(resp.clusters[0].issues) == 5;

    assert len(resp.singletons) == 2;
    external_ids: list[str] = [s.external_id for s in resp.singletons];
    assert "E2E-15" in external_ids;
    assert "E2E-16" in external_ids;
    # sorted by urgency desc: E2E-16 (1.78) before E2E-15 (0.61)
    assert resp.singletons[0].external_id == "E2E-16";
    assert resp.singletons[1].external_id == "E2E-15";

    assert len(resp.unresolved) == 1;
    assert resp.unresolved[0].external_id == "E2E-19";
}

test "get_cluster_detail returns issues plus a hop-annotated dependency graph" {
    repo = root ++> Repo(full_name="t/detail", file_count=4);
    validation = repo +>:owns:+> File(path="core/validation.py", blast_radius=3);
    db = repo +>:owns:+> File(path="core/db.py");
    order = repo +>:owns:+> File(path="models/order.py");
    orders_svc = repo +>:owns:+> File(path="services/orders.py");

    db +>:imports:+> validation;
    order +>:imports:+> validation;
    order +>:imports:+> db;
    orders_svc +>:imports:+> order;

    cluster = repo +>:owns:+> Cluster(
        cluster_key="core/validation.py",
        title="require_fields crashes",
        root_cause_summary="s",
        blast_radius=3,
        issue_count=2,
        urgency=5.0,
        fix_confidence=0.5,
        proposed_fix_summary="Add a None guard."
    );
    cluster +>:cluster_targets:+> validation;

    i1 = repo +>:owns:+> Issue(
        external_id="D-1",
        title="a",
        body="ba",
        created_at="2026-01-01",
        severity=8,
        resolution_method="explicit"
    );
    i1 +>:resolves_to:+> validation;
    i1 +>:grouped_in:+> cluster;
    i2 = repo +>:owns:+> Issue(
        external_id="D-2",
        title="b",
        body="bb",
        created_at="2026-01-01",
        severity=5,
        resolution_method="llm"
    );
    i2 +>:resolves_to:+> validation;
    i2 +>:grouped_in:+> cluster;

    result = root spawn get_cluster_detail(cluster_id=jid(cluster));
    resp: ClusterDetailResponse = result.reports[0];

    assert resp.target_path == "core/validation.py";
    assert resp.blast_radius == 3;
    assert resp.proposed_fix_summary == "Add a None guard.";
    assert len(resp.issues) == 2;
    assert resp.existing_pr is None;

    nodes_by_id: dict = {n["id"]: n for n in resp.graph["nodes"]};
    assert nodes_by_id["core/validation.py"]["role"] == "target";
    assert nodes_by_id["core/validation.py"]["hops"] == 0;
    assert nodes_by_id["core/db.py"]["hops"] == 1;
    assert nodes_by_id["models/order.py"]["hops"] == 1;
    assert nodes_by_id["services/orders.py"]["hops"] == 2;

    edge_pairs: list = [(e["from"], e["to"]) for e in resp.graph["edges"]];
    assert ("core/db.py", "core/validation.py") in edge_pairs;
    assert ("models/order.py", "core/validation.py") in edge_pairs;
    assert ("models/order.py", "core/db.py") in edge_pairs;
    assert ("services/orders.py", "models/order.py") in edge_pairs;
}

test "get_cluster_detail reports an error for an unknown cluster id" {
    result = root spawn get_cluster_detail(cluster_id="n:Cluster:does-not-exist");
    resp: dict = result.reports[0];
    assert resp["ok"] == False;
}

test "set_weights changes get_queue's ranking without touching stored Issue.urgency" {
    repo = root ++> Repo(full_name="t/weights", file_count=10);
    target = repo +>:owns:+> File(path="core/db.py", blast_radius=2);
    # Low blast/severity but the loudest reactions in the repo - with default
    # (blast-dominant) weights this should rank low; with reactions weighted
    # up and everything else zeroed, it should be the only signal that matters.
    loud = repo +>:owns:+> Issue(
        external_id="W-1",
        title="loud",
        body="b",
        created_at="2026-01-01",
        severity=1,
        estimated_diff_lines=0,
        reactions=40,
        comment_velocity=0,
        resolution_method="llm",
        urgency=0.11
    );
    loud +>:resolves_to:+> target;

    set_result = root spawn set_weights(
        full_name="t/weights",
        w_blast=0.0,
        w_sev=0.0,
        w_diff=0.0,
        w_reactions=1.0,
        w_comment_velocity=0.0
    );
    set_resp: dict = set_result.reports[0];
    assert set_resp["ok"] == True;
    assert set_resp["w_reactions"] == 1.0;

    result = root spawn get_queue(full_name="t/weights");
    resp: QueueResponse = result.reports[0];

    # Sole issue -> max_reactions == its own reactions -> reactions_norm == 1.0
    # -> urgency == 1.0 * 1.0 == 1.0, all other weights zeroed out.
    assert resp.singletons[0].urgency == 1.0;
    # get_queue's re-rank must never mutate the stored Issue node.
    assert loud.urgency == 0.11;
}
