# Changelog

## 0.2.0 (Unreleased)

Initial release.

- Rust core runtime and CLI engine (replaces shell runtime)
- Installer uses GitHub archive download + quiet build output
- Installer safely replaces old symlinks without clobbering source files
- Spec-driven build→review→fix loop
- Namespaced skills for loop workflow: spec-loop-spec, spec-loop-status
- Claude Code stream-json integration
- Circuit breaker and session resume support
- Charm.sh-inspired terminal UX
- Per-project configuration via `.speclooprc`
- Structured session logging (JSON + Markdown)
