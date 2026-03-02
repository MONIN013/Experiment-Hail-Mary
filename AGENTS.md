# Repository Instructions

## Compatibility Policy

- Backward compatibility is forbidden in this repository.
- Do not add compatibility wrappers, alias fields, fallback symbol names, dual-write logic, or legacy parameter acceptance.
- When a contract changes, update callers and tests to the new contract instead of preserving the old one.
- When implementation and spec disagree, choose one canonical contract, update the codebase to it, and remove the obsolete path.
- If a breaking change is required, make it explicit in docs and tests. Do not silently preserve old behavior.

## Change Rules

- Remove deprecated code instead of leaving migration shims behind.
- Validate the current canonical symbols and APIs directly. Do not downgrade missing symbols to optional unless the spec explicitly marks them optional.
- Prefer a hard failure over hidden fallback behavior when configuration or published interfaces are wrong.
