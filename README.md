# apple-devtools

Reusable, project-independent Apple-platform validation for coding agents.

The commands choose the cheapest authoritative layer: portable Swift checks on
Windows, installed Xcode SDK/compiler checks on macOS, and small links to current
Apple documentation for semantic guidance. They never claim Windows validates
Apple-only SDK modules.

Commands: `apple-sdk-info`, `apple-sdk-interface`, `apple-api`, `apple-symbol`, `apple-doc`,
`apple-typecheck`, `apple-build`, `apple-test`, `apple-test-focused`, `apple-sim`,
`apple-signing-doctor`, `apple-entitlements`, `apple-archive-check`, `apple-ci`,
and `apple-doctor`. Use `--json` for compact machine-readable output.

## Reusable workflow

```yaml
jobs:
  apple:
    uses: davidpovarsky/apple-devtools/.github/workflows/apple-authority.yml@main
    with:
      operation: build
      runs_on: '["macos-26"]'
```

For a self-hosted runner, pass labels such as
`'["self-hosted","macOS","ARM64"]'`. Xcode selection is process-local and never
changes the machine permanently. Full logs are workflow artifacts; console output
is filtered. Other agents can read `.agents/skills/apple-devtools/SKILL.md`.

No signing keys, tokens, profiles, or secret values are printed or committed.

Export complete public Swift module interfaces from an installed device SDK with:

```powershell
apple-sdk-interface SwiftUI SwiftUICore --sdk iphoneos --xcode stable
```

The macOS authority stores the selected arm64 device interfaces and a manifest
containing the Xcode/SDK identity, source paths, target variant, and SHA-256
hashes in the workflow artifact's `sdk-interfaces` directory.
