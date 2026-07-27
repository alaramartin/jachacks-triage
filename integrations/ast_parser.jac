"""Build the code substrate (File nodes + imports edges) from a Python repo.
Owner: Person 1. Uses Python's `ast` module directly - Jac has all of PyPI."""

import ast;
import os;

import from graph.nodes { Repo, File, owns, imports }

# Directories that are never the project's own source. Cloned third-party
# repos are full of these and indexing them would both wreck the blast-radius
# numbers and take minutes.
glob SKIP_DIRS: set[str] = {
         ".git",
         ".hg",
         ".tox",
         ".venv",
         "venv",
         "env",
         "node_modules",
         "__pycache__",
         ".mypy_cache",
         ".pytest_cache",
         "site-packages",
         "build",
         "dist",
         ".eggs"
     };

def _module_name(rel_path: str) -> str {
    without_ext: str = rel_path[:-3] if rel_path.endswith(".py") else rel_path;
    return without_ext.replace("/", ".");
}

def _read_text(path: str) -> str {
    # Real repos contain latin-1 fixtures and deliberately broken encoding
    # test files; one of them must not take the whole index down.
    fh = open(path, "r", encoding="utf-8", errors="replace");
    source: str = fh.read();
    fh.close();
    return source;
}

def _discover_python_files(repo_path: str) -> list[str] {
    found: list[str] = [];
    for (dirpath, dirnames, filenames) in os.walk(repo_path) {
        # In-place filter is what makes os.walk skip descending into these.
        dirnames[:] = [
            d
            for d in dirnames
            if d not in SKIP_DIRS and not d.startswith(".")
        ];
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

"""The importable module name for a file, i.e. its path relative to its
package root rather than to the repo. `src/mypkg/core/db.py` is imported as
`mypkg.core.db`, not `src.mypkg.core.db` - the package root is the highest
directory in the chain that still has an `__init__.py`. Without this, every
src-layout or monorepo-subdirectory repo indexes with almost no import edges."""
def _importable_name(repo_path: str, rel: str) -> str {
    parts: list[str] = rel.split("/");
    dirs: list[str] = parts[:-1];
    start: int = len(dirs);
    while start > 0 {
        candidate: str = os.path.join(
            repo_path, os.sep.join(dirs[start - 1:]), "__init__.py"
        );
        if not os.path.isfile(candidate) {
            break;
        }
        start -= 1;
    }
    return _module_name("/".join(parts[start:]));
}

"""Dotted module name -> repo-relative path. Each file is registered under
both its package-root-relative name and its repo-root-relative one (they're
the same in a flat repo like the seed). `pkg/__init__.py` additionally
answers to bare `pkg`, since that's what `import pkg` resolves to - without
it, every package-level import in a real repo drops out of the graph."""
def build_module_map(repo_path: str, rel_paths: list[str]) -> dict[str, str] {
    module_map: dict[str, str] = {};
    for rel in rel_paths {
        names: list[str] = [_module_name(rel), _importable_name(repo_path, rel)];
        for name in names {
            if name not in module_map {
                module_map[name] = rel;
            }
            if name.endswith(".__init__") {
                package: str = name[:-len(".__init__")];
                if package and package not in module_map {
                    module_map[package] = rel;
                }
            }
        }
    }
    return module_map;
}

"""Resolve `from . import x` / `from ..pkg import y` against the importing
file's own package. Real repos lean on relative imports heavily; the seed repo
doesn't use them at all, so this is purely additive to the demo numbers."""
def _relative_base(rel_path: str, level: int) -> str | None {
    parts: list[str] = rel_path.split("/");
    parts = parts[:-1];  # drop the filename -> the containing package
    if level > 1 {
        if len(parts) < level - 1 {
            return None;
        }
        parts = parts[:len(parts) - (level - 1)];
    }
    return ".".join(parts);
}

def _resolved_targets(
    file_path: str, rel_path: str, module_map: dict[str, str]
) -> list[str] {
    targets: list[str] = [];
    try {
        tree = ast.parse(_read_text(file_path), filename=file_path);
    } except Exception {
        # Unparseable file (py2 syntax, a deliberate parser-test fixture, a
        # newer grammar than this interpreter): index it as a node, just with
        # no outgoing imports.
        return targets;
    }
    for node in ast.walk(tree) {
        if isinstance(node, ast.Import) {
            for alias in node.names {
                if alias.name in module_map {
                    targets.append(module_map[alias.name]);
                }
            }
        } elif isinstance(node, ast.ImportFrom) {
            base: str | None = node.module;
            if node.level > 0 {
                package: str | None = _relative_base(rel_path, node.level);
                if package is None {
                    continue;
                }
                base = f"{package}.{node.module}" if node.module else package;
                base = base.strip(".");
            }
            if not base {
                continue;
            }
            if base in module_map {
                targets.append(module_map[base]);
            }
            for alias in node.names {
                full: str = f"{base}.{alias.name}";
                if full in module_map {
                    targets.append(module_map[full]);
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
    module_map: dict[str, str] = build_module_map(repo_path, rel_paths);

    file_nodes: dict[str, File] = {};
    for rel in rel_paths {
        full_path: str = os.path.join(repo_path, rel);
        loc: int = len(_read_text(full_path).splitlines());
        f: File = File(path=rel, loc=loc);
        repo +>:owns:+> f;
        file_nodes[rel] = f;
    }

    edge_count: int = 0;
    seen: set[tuple[str, str]] = set();
    for rel in rel_paths {
        full_path: str = os.path.join(repo_path, rel);
        targets: list[str] = _resolved_targets(full_path, rel, module_map);
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
        total += len([f->:imports:->]);
    }
    return total;
}
