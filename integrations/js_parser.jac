"""Build the code substrate (File nodes + imports edges) from TypeScript and
JavaScript sources - the sibling of ast_parser.jac, which does the same job for
Python.

Why regex and not a real parser: Jac gives us Python's `ast` for free, but
there is no TS/JS parser in the stdlib and shelling out to node/tsc would make
indexing depend on a toolchain the user may not have installed. What Triage
actually needs from a file is *which repo-relative files it imports* - not a
syntax tree - and import statements are one of the few genuinely regular parts
of the grammar. A false positive has to survive resolution against a real file
on disk to become an edge, so the failure mode is a missing edge, never a
fabricated one.

The output is deliberately identical in shape to ast_parser's: repo-relative
POSIX paths and (importer, imported) pairs. Everything downstream - blast
radius, clustering, ranking, the PR agent - is language-agnostic and needs no
changes."""

import os;
import re;

# Same spirit as ast_parser's SKIP_DIRS, plus the directories a JS repo fills
# with build output and vendored code. Indexing `dist/` would double-count
# every file and wreck the blast-radius numbers with machine-generated copies.
# Test and example trees are excluded, which is NOT just a speed decision.
# `vercel/next.js` has 22,077 indexable JS/TS files and 13,226 of them - 60% -
# live under `test/`, overwhelmingly fixtures: tiny files that import each other
# and nothing real. Indexing them buys nothing (nobody triages a fixture) and
# actively corrupts the product, because blast radius counts fixture-to-fixture
# imports as structural dependency. Excluding them takes next.js from 22,077
# indexable files to 3,277.
#
# Deliberately NOT applied to Python discovery: flask's `tests/conftest.py` is a
# real resolution target in the current baseline, Python repos don't carry
# thousands of fixtures, and changing it would move numbers this project's
# verification depends on.
glob JS_SKIP_DIRS: set[str] = {
         ".git",
         "node_modules",
         "bower_components",
         "dist",
         "build",
         "out",
         "coverage",
         "vendor",
         "__pycache__",
         ".next",
         ".nuxt",
         ".svelte-kit",
         ".turbo",
         ".vercel",
         ".output",
         ".cache",
         "storybook-static",
         "test",
         "tests",
         "__tests__",
         "__mocks__",
         "fixtures",
         "__fixtures__",
         "e2e",
         "examples",
         "example",
         "bench",
         "benchmarks",
         "evals"
     };

# Order matters: this is the extension resolution order for an extensionless
# import, and TS wins over JS the way tsc itself resolves.
glob JS_EXTS: list[str] = [".ts", ".tsx", ".mts", ".cts", ".js", ".jsx", ".mjs", ".cjs"];

"""A file we should index. Excludes build artifacts that survive the directory
filter: minified bundles, sourcemap-adjacent files, and ambient type
declarations (a .d.ts has no runtime behavior for an issue to be about)."""
def _is_indexable(name: str) -> bool {
    lowered: str = name.lower();
    if lowered.endswith(".d.ts") or lowered.endswith(".d.mts") or lowered.endswith(".d.cts") {
        return False;
    }
    if ".min." in lowered or lowered.endswith(".bundle.js") {
        return False;
    }
    for ext in JS_EXTS {
        if lowered.endswith(ext) {
            return True;
        }
    }
    return False;
}

def discover_js_files(repo_path: str) -> list[str] {
    found: list[str] = [];
    for (dirpath, dirnames, filenames) in os.walk(repo_path) {
        dirnames[:] = [
            d
            for d in dirnames
            if d not in JS_SKIP_DIRS and not d.startswith(".")
        ];
        for name in filenames {
            if _is_indexable(name) {
                full: str = os.path.join(dirpath, name);
                rel: str = os.path.relpath(full, repo_path);
                found.append(rel.replace(os.sep, "/"));
            }
        }
    }
    found.sort();
    return found;
}

# Every shape an import specifier reaches us in. Each pattern captures exactly
# the quoted specifier.
glob _SPEC_PATTERNS: list[str] = [
         r"""\bfrom\s*['"]([^'"]+)['"]""",  # import x from 'y' / export * from 'y'
         r"""\bimport\s*['"]([^'"]+)['"]""",  # bare side-effect import 'y'
         r"""\brequire\s*\(\s*['"]([^'"]+)['"]\s*\)""",  # CommonJS
         r"""\bimport\s*\(\s*['"]([^'"]+)['"]\s*\)"""  # dynamic import()
     ];

def _specifiers(source: str) -> list[str] {
    out: list[str] = [];
    seen: set[str] = set();
    for pattern in _SPEC_PATTERNS {
        for spec in re.findall(pattern, source) {
            if spec not in seen {
                seen.add(spec);
                out.append(spec);
            }
        }
    }
    return out;
}

"""Collapse `a/b/../c` and `./d` into a clean repo-relative path. Deliberately
not os.path.normpath: that uses the host separator and would produce
backslashes on Windows, and repo-relative paths here are always POSIX."""
def _normalize(path: str) -> str {
    parts: list[str] = [];
    for segment in path.split("/") {
        if segment == "" or segment == "." {
            continue;
        }
        if segment == ".." {
            if len(parts) > 0 {
                parts.pop();
            }
            continue;
        }
        parts.append(segment);
    }
    return "/".join(parts);
}

"""Every candidate file a resolved base path could mean, in tsc's own order:
the path itself, then with each extension appended, then as a directory with
an index file. Plus the TS-ESM convention where source says `./foo.js` but the
file on disk is `foo.ts`."""
def _candidates(base: str) -> list[str] {
    out: list[str] = [base];
    for ext in JS_EXTS {
        out.append(base + ext);
    }
    for ext in JS_EXTS {
        out.append(f"{base}/index{ext}");
    }
    for js_ext in [".js", ".jsx", ".mjs", ".cjs"] {
        if base.endswith(js_ext) {
            stem: str = base[:-len(js_ext)];
            for ts_ext in [".ts", ".tsx", ".mts", ".cts"] {
                out.append(stem + ts_ext);
            }
        }
    }
    return out;
}

"""Bases to try for an aliased or root-relative specifier. `@/x` and `~/x` are
the near-universal Next/Vite/tsconfig-paths convention for "from the project
root", which in practice means the repo root or a src/-style directory. We try
each and let resolution against real files decide - a guess that matches
nothing simply produces no edge."""
glob _ROOT_DIRS: list[str] = ["", "src/", "app/", "lib/"];

def _alias_bases(rest: str) -> list[str] {
    return [prefix + rest for prefix in _ROOT_DIRS];
}

"""Turn one import specifier into a repo-relative path, or None.

None covers everything that isn't a file in this repo: npm packages, node
builtins, CSS/asset imports that resolve to no source file. That mirrors
ast_parser dropping stdlib and third-party Python imports - an `imports` edge
only ever means "this file in this repo depends on that file in this repo"."""
def resolve_specifier(
    spec: str, importer_rel: str, path_set: set[str]
) -> str | None {
    bases: list[str] = [];

    if spec.startswith("./") or spec.startswith("../") or spec == "." or spec == ".." {
        importer_dir: str = "/".join(importer_rel.split("/")[:-1]);
        bases.append(_normalize(f"{importer_dir}/{spec}"));
    } elif spec.startswith("@/") or spec.startswith("~/") {
        bases = [_normalize(b) for b in _alias_bases(spec[2:])];
    } elif spec.startswith("/") {
        bases.append(_normalize(spec));
    } else {
        # A bare specifier is USUALLY an npm package. It can also be an
        # internal module when tsconfig sets baseUrl (`import "components/x"`),
        # so it's tried against the repo - but only accepted if it hits a real
        # file, which a package name won't.
        bases = [_normalize(b) for b in _alias_bases(spec)];
    }

    for base in bases {
        if not base {
            continue;
        }
        for candidate in _candidates(base) {
            if candidate in path_set {
                return candidate;
            }
        }
    }
    return None;
}

"""The repo-relative files `source` imports. `path_set` is every indexed JS/TS
path in the repo, which is what makes resolution exact rather than guessed."""
def js_targets(source: str, importer_rel: str, path_set: set[str]) -> list[str] {
    targets: list[str] = [];
    for spec in _specifiers(source) {
        resolved: str | None = resolve_specifier(spec, importer_rel, path_set);
        if resolved is not None {
            targets.append(resolved);
        }
    }
    return targets;
}

"""typescript / javascript, for File.language. Purely descriptive - nothing
branches on it - but it is what lets the UI say what it actually indexed."""
def js_language_of(rel_path: str) -> str {
    lowered: str = rel_path.lower();
    for ext in [".ts", ".tsx", ".mts", ".cts"] {
        if lowered.endswith(ext) {
            return "typescript";
        }
    }
    return "javascript";
}
