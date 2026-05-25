Skills are organized into bucket folders under `skills/`:

- `engineering/` — debugging, auditing, security scanning, code review
- `productivity/` — engineering communication and process
- `cicd/` — CI/CD pipeline management

Every skill must have a `SKILL.md` with YAML frontmatter (`name` and `description`) in its own directory under the appropriate bucket.

CI/CD commands live in `skills/cicd/{skill-name}/commands/` and are copied/symlinked to `~/.claude/commands/`.

Each bucket folder has a `README.md` that lists every skill with a one-line description, linking to its `SKILL.md`.

The top-level `README.md` is the full catalog — it must list every skill across all buckets.
