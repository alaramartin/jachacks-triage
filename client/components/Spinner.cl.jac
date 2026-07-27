"""The little spinning ring shown inside a button while a PR is being drafted.

Generating a PR is slow on purpose - it reads the real source, runs a full-file
`by llm()` rewrite, syntax-checks it, then opens the PR on GitHub. Without this
the button looked dead for ten-plus seconds.
"""

def:pub Spinner(tone: str = "dark") -> JsxElement {
    stroke = "#07130d" if tone == "dark" else "currentColor";
    return
        <svg
            className="animate-spin"
            width="14"
            height="14"
            viewBox="0 0 24 24"
            fill="none"
            aria-hidden="true"
        >
            <circle
                cx="12"
                cy="12"
                r="9"
                stroke={stroke}
                strokeWidth="3"
                opacity="0.25"
            />
            <path
                d="M21 12a9 9 0 0 0-9-9"
                stroke={stroke}
                strokeWidth="3"
                strokeLinecap="round"
            />
        </svg>;
}
