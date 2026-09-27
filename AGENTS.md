# AGENTS

- MUST NOT disable compiler warnings
- MUST NOT use magic methods to cast types (e.g. `Obj.magic`)
- MUST NOT modify any dune file during development unless explicitly asked

See `.agents/skills/` for platform-specific development guides and `docs/agent-guide/` for design specifications.
- Avoid O(n²) `List` patterns such as `List.concat` and repeated `List.append` on large sequences; when the project already depends on the `rrbvec` package, use `Rrbvec` vectors instead.
