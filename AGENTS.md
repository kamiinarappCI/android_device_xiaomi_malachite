# Agent rules for everything under E:\Dev

## Git identity

Every commit (author and committer) uses:

- name: `Noam`
- email: `noamtu123@users.noreply.github.com`

Never use any other email address. Before the first commit in a repo run
`git config user.email`; if it prints anything else, fix it with
`git config user.email noamtu123@users.noreply.github.com`. Local repo config
overrides global config, so check both. In temporary clones and worktrees set it
before committing. Do not put real email addresses in commit messages, docs or PRs.
