# Authority selection

- Exact API signature, availability, module, entitlement, or build validity:
  use the requested installed Xcode SDK/compiler.
- Semantics, recommended use, migration guidance, release notes, or samples:
  use current pages on `developer.apple.com`.
- Portable Swift syntax, SPM, or fast unit checks: use local Swift/SourceKit.
- Apple framework compile, simulator, signing, archive, or provisioning work:
  use macOS/Xcode.
- If current published docs differ from the installed SDK, label both facts and
  do not imply that a documented beta API exists in the installed stable SDK.

Never create an offline Apple documentation mirror. Keep excerpts and symbol
queries targeted.
