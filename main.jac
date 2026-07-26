"""Triage - Entry Point.

Server-side walker:pub / def:pub endpoints (owned by Person 1 / Person 2) are
imported here as they land. Client-side UI is Person 3's `client/` module.
"""

cl {
    import ".client/global.css";
    import from .client.app { app as ClientApp }

    def:pub app -> JsxElement {
        return <ClientApp/>;
    }
}
