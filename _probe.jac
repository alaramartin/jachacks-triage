import from integrations.js_parser { discover_js_files, js_targets, resolve_specifier }

with entry {
    for root_dir in [".workspace/alaramartin__website", ".workspace/AzizAkturin__TeamSnorlax-UX-Agent"] {
        paths: list[str] = discover_js_files(root_dir);
        pset: set[str] = set(paths);
        edges: int = 0;
        resolved_examples: list[str] = [];
        for rel in paths {
            fh = open(root_dir + "/" + rel, "r", encoding="utf-8", errors="replace");
            src: str = fh.read();
            fh.close();
            tgts = js_targets(src, rel, pset);
            edges += len(tgts);
            if len(tgts) > 0 and len(resolved_examples) < 4 {
                resolved_examples.append(f"{rel} -> {tgts[:3]}");
            }
        }
        print(f"== {root_dir}: {len(paths)} js/ts files, {edges} import edges");
        for e in resolved_examples { print("   ", e); }
    }
}
