"""Hand-built mock data - mirrors mocks/queue.json and mocks/cluster_detail.json.

Plain dicts, not `obj` instances: Jac's client (.cl.jac) codegen compiles
`SomeObj(field=val)` construction to a bare JS function call missing `new`,
which throws `TypeError: Class constructor X cannot be invoked without 'new'`
at runtime (confirmed - jac check does not catch this, it's a real compiler
gap in this jaclang/jac-client version). Dict literals sidestep it entirely
and match the JSON contract in CLAUDE.md §6 more literally anyway.

Person 3 Phase A: the whole UI renders from these globs, no backend running.
Phase C (~3:30): swap the call sites in the screens for `sv import`-ed live
endpoints and delete this file's usage (kept only as a fallback/demo seed).
"""

glob:pub mock_queue: dict = {
    "repo": "triage-demo/shipyard",
    "file_count": 18,
    "clusters": [
        {
            "id": "n:Cluster:mock-validation",
            "title": "require_fields() crashes on None and non-ASCII input",
            "target_path": "core/validation.py",
            "blast_radius": 14,
            "issue_count": 5,
            "max_severity": 9,
            "urgency": 7.22,
            "fix_confidence": 0.86,
            "issues": [
                {"id": "n:Issue:seed-01", "external_id": "SEED-01", "title": "Crash when submitting checkout form", "severity": 9, "resolution_method": "explicit"},
                {"id": "n:Issue:seed-02", "external_id": "SEED-02", "title": "Product names with emoji get silently truncated", "severity": 5, "resolution_method": "llm"},
                {"id": "n:Issue:seed-03", "external_id": "SEED-03", "title": "Signup fails for international phone numbers", "severity": 7, "resolution_method": "llm"},
                {"id": "n:Issue:seed-04", "external_id": "SEED-04", "title": "TypeError: expected str, got NoneType on order save", "severity": 9, "resolution_method": "explicit"},
                {"id": "n:Issue:seed-05", "external_id": "SEED-05", "title": "CSV export skips rows with blank fields", "severity": 6, "resolution_method": "llm"},
            ],
        },
        {
            "id": "n:Cluster:mock-product",
            "title": "price_cents type mismatch and unbounded stock adjustment",
            "target_path": "models/product.py",
            "blast_radius": 5,
            "issue_count": 3,
            "max_severity": 8,
            "urgency": 3.87,
            "fix_confidence": 0.71,
            "issues": [
                {"id": "n:Issue:seed-06", "external_id": "SEED-06", "title": "Price shows as 0.00 for sale items", "severity": 7, "resolution_method": "explicit"},
                {"id": "n:Issue:seed-07", "external_id": "SEED-07", "title": "Cart total doesn't match sum of items", "severity": 7, "resolution_method": "llm"},
                {"id": "n:Issue:seed-08", "external_id": "SEED-08", "title": "Inventory count goes negative after refunds", "severity": 8, "resolution_method": "explicit"},
            ],
        },
        {
            "id": "n:Cluster:mock-upload",
            "title": "upload.py has no size cap and ignores EXIF orientation",
            "target_path": "services/upload.py",
            "blast_radius": 1,
            "issue_count": 2,
            "max_severity": 6,
            "urgency": 1.88,
            "fix_confidence": 0.64,
            "issues": [
                {"id": "n:Issue:seed-09", "external_id": "SEED-09", "title": "Image upload hangs on files over 5MB", "severity": 6, "resolution_method": "llm"},
                {"id": "n:Issue:seed-10", "external_id": "SEED-10", "title": "Uploaded avatars appear rotated 90 degrees", "severity": 4, "resolution_method": "llm"},
            ],
        },
    ],
    "singletons": [
        {"id": "n:Issue:seed-18", "external_id": "SEED-18", "title": "Password reset email never arrives", "target_path": "services/users.py", "blast_radius": 1, "severity": 8, "urgency": 2.48, "resolution_method": "llm"},
        {"id": "n:Issue:seed-17", "external_id": "SEED-17", "title": "Admin dashboard 500s on bulk edit", "target_path": "api/routes_admin.py", "blast_radius": 0, "severity": 9, "urgency": 2.40, "resolution_method": "explicit"},
        {"id": "n:Issue:seed-16", "external_id": "SEED-16", "title": "Orders list takes 30s with 10k rows", "target_path": "services/orders.py", "blast_radius": 1, "severity": 6, "urgency": 1.78, "resolution_method": "llm"},
        {"id": "n:Issue:seed-11", "external_id": "SEED-11", "title": "🚨 URGENT — logging blew up my disk, EVERYTHING gone", "target_path": "utils/logging.py", "blast_radius": 0, "severity": 5, "urgency": 1.40, "resolution_method": "llm"},
        {"id": "n:Issue:seed-14", "external_id": "SEED-14", "title": "Add a dark mode toggle", "target_path": "core/config.py", "blast_radius": 3, "severity": 2, "urgency": 1.20, "resolution_method": "llm"},
        {"id": "n:Issue:seed-12", "external_id": "SEED-12", "title": "CRITICAL!!! profile page completely broken!!!", "target_path": "api/routes_users.py", "blast_radius": 0, "severity": 4, "urgency": 1.08, "resolution_method": "llm"},
        {"id": "n:Issue:seed-15", "external_id": "SEED-15", "title": "Typo in order confirmation message", "target_path": "services/orders.py", "blast_radius": 1, "severity": 1, "urgency": 0.61, "resolution_method": "llm"},
    ],
    "unresolved": [
        {"id": "n:Issue:seed-13", "external_id": "SEED-13", "title": "This app is a disaster, nothing works"},
        {"id": "n:Issue:seed-19", "external_id": "SEED-19", "title": "doesn't work"},
        {"id": "n:Issue:seed-20", "external_id": "SEED-20", "title": "pls fix asap thanks"},
    ],
};

glob:pub mock_cluster_detail: dict = {
    "id": "n:Cluster:mock-validation",
    "title": "require_fields() crashes on None and non-ASCII input",
    "root_cause_summary": "All five reports trace to core/validation.py: require_fields() has no None check, so str(None) == \"None\" silently passes as a non-empty value and downstream code crashes calling .strip() on None; normalize_text() slices encoded UTF-8 bytes instead of characters, corrupting or truncating any multi-byte text (emoji, accents, non-Latin scripts).",
    "target_path": "core/validation.py",
    "blast_radius": 14,
    "urgency": 7.22,
    "fix_confidence": 0.86,
    "proposed_fix_summary": "Add a None guard in require_fields() before the length check, and normalize_text() should slice on decoded characters (or use a grapheme-safe truncation) instead of raw UTF-8 bytes.",
    "issues": [
        {
            "id": "n:Issue:seed-01", "external_id": "SEED-01", "title": "Crash when submitting checkout form",
            "body": "Traceback (most recent call last):\n  File \"api/routes_orders.py\", line 41, in create_order\n  File \"services/orders.py\", line 22, in place_order\n  File \"models/order.py\", line 15, in validate\n  File \"core/validation.py\", line 12, in require_fields\nAttributeError: 'NoneType' object has no attribute 'strip'",
            "severity": 9, "resolution_method": "explicit",
        },
        {
            "id": "n:Issue:seed-02", "external_id": "SEED-02", "title": "Product names with emoji get silently truncated",
            "body": "I named a product \"🚀 Rocket Mug\" and after saving it shows up as \"🚀 Rocket M\" in the catalog. Doesn't happen with plain ASCII names.",
            "severity": 5, "resolution_method": "llm",
        },
        {
            "id": "n:Issue:seed-03", "external_id": "SEED-03", "title": "Signup fails for international phone numbers",
            "body": "Tried to sign up with my UK number \"+44 7911 123456\" and the form says the phone field is required, even though I typed it in. Works fine with US numbers.",
            "severity": 7, "resolution_method": "llm",
        },
        {
            "id": "n:Issue:seed-04", "external_id": "SEED-04", "title": "TypeError: expected str, got NoneType on order save",
            "body": "Traceback (most recent call last):\n  File \"models/order.py\", line 18, in save\n  File \"core/validation.py\", line 12, in require_fields\nTypeError: expected str, got NoneType",
            "severity": 9, "resolution_method": "explicit",
        },
        {
            "id": "n:Issue:seed-05", "external_id": "SEED-05", "title": "CSV export skips rows with blank fields",
            "body": "Exporting orders to CSV, any row that had an empty shipping note just vanishes from the export entirely instead of showing up with a blank cell.",
            "severity": 6, "resolution_method": "llm",
        },
    ],
    "graph": {
        "nodes": [
            {"id": "core/validation.py", "label": "core/validation.py", "role": "target", "hops": 0},
            {"id": "core/config.py", "label": "core/config.py", "role": "neutral", "hops": 0},
            {"id": "core/errors.py", "label": "core/errors.py", "role": "neutral", "hops": 0},
            {"id": "utils/logging.py", "label": "utils/logging.py", "role": "neutral", "hops": 0},
            {"id": "core/db.py", "label": "core/db.py", "role": "dependent", "hops": 1},
            {"id": "models/order.py", "label": "models/order.py", "role": "dependent", "hops": 1},
            {"id": "models/user.py", "label": "models/user.py", "role": "dependent", "hops": 1},
            {"id": "models/product.py", "label": "models/product.py", "role": "dependent", "hops": 1},
            {"id": "models/cart.py", "label": "models/cart.py", "role": "dependent", "hops": 1},
            {"id": "services/upload.py", "label": "services/upload.py", "role": "dependent", "hops": 1},
            {"id": "services/orders.py", "label": "services/orders.py", "role": "dependent", "hops": 2},
            {"id": "services/users.py", "label": "services/users.py", "role": "dependent", "hops": 2},
            {"id": "services/inventory.py", "label": "services/inventory.py", "role": "dependent", "hops": 2},
            {"id": "services/pricing.py", "label": "services/pricing.py", "role": "dependent", "hops": 2},
            {"id": "utils/csv_export.py", "label": "utils/csv_export.py", "role": "dependent", "hops": 2},
            {"id": "api/routes_admin.py", "label": "api/routes_admin.py", "role": "dependent", "hops": 2},
            {"id": "api/routes_orders.py", "label": "api/routes_orders.py", "role": "dependent", "hops": 3},
            {"id": "api/routes_users.py", "label": "api/routes_users.py", "role": "dependent", "hops": 3},
        ],
        "edges": [
            {"from_file": "core/db.py", "to_file": "core/validation.py"},
            {"from_file": "models/order.py", "to_file": "core/validation.py"},
            {"from_file": "models/order.py", "to_file": "core/db.py"},
            {"from_file": "models/order.py", "to_file": "core/errors.py"},
            {"from_file": "models/user.py", "to_file": "core/validation.py"},
            {"from_file": "models/user.py", "to_file": "core/db.py"},
            {"from_file": "models/product.py", "to_file": "core/validation.py"},
            {"from_file": "models/product.py", "to_file": "core/db.py"},
            {"from_file": "models/cart.py", "to_file": "models/product.py"},
            {"from_file": "models/cart.py", "to_file": "core/validation.py"},
            {"from_file": "services/orders.py", "to_file": "models/order.py"},
            {"from_file": "services/orders.py", "to_file": "core/errors.py"},
            {"from_file": "services/users.py", "to_file": "models/user.py"},
            {"from_file": "services/inventory.py", "to_file": "models/product.py"},
            {"from_file": "services/inventory.py", "to_file": "core/db.py"},
            {"from_file": "services/pricing.py", "to_file": "models/cart.py"},
            {"from_file": "services/pricing.py", "to_file": "models/product.py"},
            {"from_file": "services/upload.py", "to_file": "core/validation.py"},
            {"from_file": "services/upload.py", "to_file": "core/config.py"},
            {"from_file": "api/routes_orders.py", "to_file": "services/orders.py"},
            {"from_file": "api/routes_orders.py", "to_file": "services/pricing.py"},
            {"from_file": "api/routes_users.py", "to_file": "services/users.py"},
            {"from_file": "api/routes_admin.py", "to_file": "services/inventory.py"},
            {"from_file": "api/routes_admin.py", "to_file": "services/upload.py"},
            {"from_file": "utils/logging.py", "to_file": "core/config.py"},
            {"from_file": "utils/csv_export.py", "to_file": "models/order.py"},
        ],
    },
    "existing_pr": None,
};
