"""Build the code substrate (File nodes + imports edges) from a Python repo.
Owner: Person 1. Uses Python's `ast` module directly - Jac has all of PyPI."""

import ast;
import os;

import from graph.nodes { Repo, File, owns, imports }

def _module_name(rel_path: str) -> str {
    without_ext: str = rel_path[:-3] if rel_path.endswith(".py") else rel_path;
    return without_ext.replace("/", ".");
}

def _discover_python_files(repo_path: str) -> list[str] {
    found: list[str] = [];
    for (dirpath, _dirnames, filenames) in os.walk(repo_path) {
        for name in filenames {
            if name.endswith(".py") {
                full: str = os.path.join(dirpath, name);
                rel: str = os.path.relpath(full, repo_path);
                found.append(rel.replace(os.sep, "/"));
            }
        }
    }
    found.sort();
    return found;
}

def _resolved_targets(file_path: str, module_map: dict[str, str]) -> list[str] {
    targets: list[str] = [];
    fh = open(file_path, "r");
    source: str = fh.read();
    fh.close();
    tree = ast.parse(source, filename=file_path);
    for node in ast.walk(tree) {
        if isinstance(node, ast.Import) {
            for alias in node.names {
                if alias.name in module_map {
                    targets.append(module_map[alias.name]);
                }
            }
        } elif isinstance(node, ast.ImportFrom) {
            if node.level == 0 and node.module is not None {
                if node.module in module_map {
                    targets.append(module_map[node.module]);
                }
                for alias in node.names {
                    full: str = f"{node.module}.{alias.name}";
                    if full in module_map {
                        targets.append(module_map[full]);
                    }
                }
            }
        }
    }
    return targets;
}

"""Walk repo_path, create one File node per .py file plus `imports` edges
between them (intra-repo only - stdlib/third-party imports are dropped
because they never appear in module_map). Returns files_indexed / import_edges."""
def build_code_substrate(repo_path: str, repo: Repo) -> dict[str, int] {
    rel_paths: list[str] = _discover_python_files(repo_path);
    module_map: dict[str, str] = {};
    for rel in rel_paths {
        module_map[_module_name(rel)] = rel;
    }

    file_nodes: dict[str, File] = {};
    for rel in rel_paths {
        full_path: str = os.path.join(repo_path, rel);
        fh = open(full_path, "r");
        source: str = fh.read();
        fh.close();
        loc: int = len(source.splitlines());
        f: File = File(path=rel, loc=loc);
        repo +>:owns:+> f;
        file_nodes[rel] = f;
    }

    edge_count: int = 0;
    seen: set[tuple[str, str]] = set();
    for rel in rel_paths {
        full_path: str = os.path.join(repo_path, rel);
        targets: list[str] = _resolved_targets(full_path, module_map);
        for target_rel in targets {
            if target_rel == rel {
                continue;
            }
            pair: tuple[str, str] = (rel, target_rel);
            if pair in seen {
                continue;
            }
            seen.add(pair);
            src: File = file_nodes[rel];
            tgt: File = file_nodes[target_rel];
            src +>:imports:+> tgt;
            edge_count += 1;
        }
    }

    repo.file_count = len(rel_paths);
    return {"files_indexed": len(rel_paths), "import_edges": edge_count};
}

def count_import_edges(files: list[File]) -> int {
    total: int = 0;
    for f in files {
        total += len([f ->:imports:->]);
    }
    return total;
}
