# AGENTS

- MUST NOT disable compiler warnings
- MUST NOT use magic methods to cast types (e.g. `Obj.magic`)
- MUST NOT modify any dune file during development unless explicitly asked

See `.agents/skills/` for platform-specific development guides and `docs/agent-guide/` for design specifications.
- **Supported backends**: NSH is the default desktop backend; Apple/iOS, Android and Web/Melange remain maintained. Desktop migrations must preserve the Apple Swift packages, Android Gradle/JNI backend and mobile build/test tooling used by `logseq/mobile` and `logseq/logseq_journal`. Do not retire mobile backends without explicit approval.
- **Reactive API (mandatory)**: Always load `.agents/skills/lui-reactive/SKILL.md` before writing or editing view code that builds `Lui_elements`. Direct `dyn` calls are forbidden; `reactive` is the only reactive form.
- Avoid O(n²) `List` patterns such as `List.concat` and repeated `List.append` on large sequences; when the project already depends on the `rrbvec` package, use `Rrbvec` vectors instead.
- All PR descriptions and code comments must be written in English.
- All documentation must be written in English.
- Record every public API, wire-contract, default and event behavior change in `docs/api-migrations.md`, including compatibility rules and concrete migration examples for downstream applications.
- Do not commit downloaded third-party dependency trees, caches, build outputs or demo recordings. Use pinned dependencies and authorized forks, and review both staged files and the complete PR diff before pushing.
