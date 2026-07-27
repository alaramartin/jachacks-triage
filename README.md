# Triage

## Inspiration

At one point or another, we have all dealt with a huge repository of code with dozens of open issues. How do you know which one is a minor fix and how do you know which one is quietly breaking half your app? We wanted to build an app that ranks and fixes the most critical issues in your app, so you can focus on building rather than debugging.

## What it does

Triage builds a live dependency graph of your repository, resolves every open issue onto the exact function or file it points at, and then does two things a traditional LLM can’t: it ranks issues by structural blast radius (how many files in your codebase depend on the code that issue touches) and it clusters issues that silently describe the same underlying bug (even if they share zero words in common) because they land on the same node in the graph.

When you're ready to fix something, click a single button and you have a fully drafted pull request with the root cause and blast-radius evidence already written into it. Triage will never open that PR on its own; a human always reviews and clicks the button.

## How we built it

Triage is nearly 100% Jac!

The data model is one graph with two node families: a permanent "code substrate" of File nodes connected by imports edges (built by parsing the repo's actual Python AST), and a dynamic "issue layer" of Issue, Cluster, and PullRequest nodes that attach onto it. Four separate agents (triage, blast-radius, clustering, and ranking) are triggered by graph state changing, so writing one edge (an issue resolving onto a file) cascades through the whole pipeline automatically.

The “Triage Agent” locates where the bug lives. The “Blast Radius Agent” walks along import lines to count every file that depends on the buggy file. The “Clustering Agent” checks if multiple issues share the same root cause; if so, it merges them into a cluster.
We used Jac's by llm() construct to guess which file an ambiguously-worded issue is about, score severity, and decide whether a group of issues sharing a file actually share one root cause.

## Challenges we ran into

We ran into three key challenges:
Initially, we weren’t sure how to represent our program as a graph. We considered making two separate graphs (one for the codebase and one for the issues), but we decided to merge them into one graph because it would not require syncing two databases.
Additionally, we struggled to decide which features to base our ranking off of. We decided to use a mix of “blast radius” (how many files an issue impacts downstream) and “semantic meaning” (calculated by a by llm() call on the issue’s title and body) because weighting structural impact heavily ensures that quiet but critical bugs touching core code float above minor issues.
Our different machines had different environments, so we struggled to run the same code. We ended up merging our code onto one environment and deploying there.

## Accomplishments that we're proud of

We were able to successfully build four distinct Jac agents that coordinate entirely through graph state changes (never by calling each other directly) proving Jac's object-spatial model as an effective coordination layer.
We were able to write the entire stack in Jac, including graph algorithms and UI components.
Our program is able to successfully take dozens of issues, merge and rank them, and draft automatic PR requests, speeding up the process of software development!

## What we learned

Code is not linear. Codebases have dozens of files that depend on one another in unique ways. Standard LLMs only have a snapshot of code, which is why our project (which relies on a graph of dependencies) speeds up software development.
Having humans in the loop is crucial. Rather than allowing the agents to automatically spam repositories with PRs, the user can control what PR requests are generated and approve them as needed.
Use multiple agents. Using Jac, we built four agents that each worked on separate tasks to speed up our program.

## What's next for Triage

We would like to add more ranking features. For example, if a repository had more upvotes, comments, or mentions, issues would be assigned a higher score as those issues would be affecting real-world users. We would also like to make ranking preference customizable to the user. For instance, the user could choose their top priority to be semantic severity.
