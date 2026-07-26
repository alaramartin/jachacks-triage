import from graph.nodes { Repo, File, Issue, Cluster }

test "rank_issue applies the locked formula" {
    repo = Repo(full_name="t/r", file_count=18);
    f = File(path="core/validation.py", blast_radius=14);
    issue = Issue(external_id="X-1", title="t", body="b", created_at="2026-01-01", severity=9, estimated_diff_lines=0);

    got = rank_issue(issue, f, repo);

    # urgency = 6*(14/18) + 3*(9/10) - 1*min(0/100,1) = 4.666... + 2.7 - 0 = 7.36 (truncated to 2dp)
    assert got == 7.36;
    assert issue.urgency == 7.36;
}

test "rank_cluster uses MAX severity and MAX diff across members" {
    repo = Repo(full_name="t/r2", file_count=18);
    f = File(path="core/validation.py", blast_radius=14);
    cluster = Cluster(cluster_key="core/validation.py", blast_radius=14);
    low = Issue(external_id="X-2", title="t", body="b", created_at="2026-01-01", severity=3, estimated_diff_lines=200);
    high = Issue(external_id="X-3", title="t", body="b", created_at="2026-01-01", severity=9, estimated_diff_lines=5);

    got = rank_cluster(cluster, [low, high], repo);

    # max severity=9, max diff=200 -> diff_norm capped at 1.0
    # urgency = 6*(14/18) + 3*(9/10) - 1*1.0 = 4.666.. + 2.7 - 1.0 = 6.36
    assert got == 6.36;
    assert cluster.urgency == 6.36;
}
