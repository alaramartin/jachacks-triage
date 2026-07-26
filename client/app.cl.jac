"""Triage client entry - manual routing (no pages/ dir, per CLAUDE.md's flat client/ layout)."""

import from "@jac/runtime" { Router, Routes, Route }
import from .screens.LoginScreen { LoginScreen }
import from .screens.RepoPickerScreen { RepoPickerScreen }
import from .screens.QueueScreen { QueueScreen }
import from .cluster_view { ClusterView }

def:pub app() -> JsxElement {
    return <Router>
        <Routes>
            <Route path="/" element={<LoginScreen />} />
            <Route path="/repos" element={<RepoPickerScreen />} />
            <Route path="/queue" element={<QueueScreen />} />
            <Route path="/cluster/:id" element={<ClusterView />} />
        </Routes>
    </Router>;
}
