"""Self-test for Agent 1 (Triage) — run with `jac test agents/triage_agent.jac`."""

glob file_paths: list[str] = [
    "core/validation.py", "core/config.py", "core/errors.py", "core/db.py",
    "models/order.py", "models/user.py", "models/product.py", "models/cart.py",
    "services/orders.py", "services/users.py", "services/inventory.py",
    "services/pricing.py", "services/upload.py",
    "api/routes_orders.py", "api/routes_users.py", "api/routes_admin.py",
    "utils/logging.py", "utils/csv_export.py",
];

test "explicit traceback resolves without hitting the LLM" {
    body = "Traceback (most recent call last):\n  File \"core/validation.py\", line 12, in require_fields\nTypeError: 'NoneType' object has no attribute 'strip'";
    path = explicit_resolve(body, file_paths);
    assert path == "core/validation.py";
}

test "explicit resolve returns None with no signal" {
    path = explicit_resolve("doesn't work", file_paths);
    assert path is None;
}

test "assess_severity gives sane numbers for three issues" {
    crash_sev = assess_severity(
        "Crash when submitting checkout form",
        "Users report checkout dies with a 500 as soon as they submit the form."
    );
    typo_sev = assess_severity(
        "Typo in order confirmation message",
        "the order confirmation message says 'recieved' instead of 'received'."
    );
    feature_sev = assess_severity(
        "Add a dark mode toggle",
        "It would be great if there was a dark mode option in settings."
    );
    print(f"crash={crash_sev} typo={typo_sev} feature={feature_sev}");
    assert 1 <= crash_sev <= 10;
    assert 1 <= typo_sev <= 10;
    assert 1 <= feature_sev <= 10;
    assert crash_sev > typo_sev;
}

test "resolve_issue hybrid: explicit hit" {
    res = resolve_issue(
        "Crash when submitting checkout form",
        "File \"core/validation.py\", line 12, in require_fields",
        file_paths
    );
    assert res.method == "explicit";
    assert res.path == "core/validation.py";
    assert res.confidence == 0.95;
}

test "resolve_issue hybrid: pure venting parks or falls back safely" {
    res = resolve_issue("doesn't work", "doesn't work", file_paths);
    print(f"vague issue -> path={res.path} conf={res.confidence} method={res.method}");
    assert res.method in ["none", "llm"];
}
