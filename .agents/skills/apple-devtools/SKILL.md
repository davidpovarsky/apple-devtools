---
name: apple-devtools
description: Verify Swift and Apple-platform code with portable Windows Swift tools, real installed Xcode SDKs, focused builds/tests, simulator tooling, signing metadata, entitlements, archives, symbol graphs, and current Apple documentation. Use for iOS, iPadOS, macOS, watchOS, tvOS, visionOS, SwiftUI, UIKit, AppKit, Swift compiler, Xcode, SDK availability, deployment-target, entitlement, signing, simulator, or Apple CI work.
---

# Apple Devtools

Use the installed `apple-*` commands from any project directory.

1. Prefer `apple-typecheck --path FILE --local` for portable Swift/SPM code.
2. Never treat Windows as authoritative for Apple-only modules. Let
   `apple-typecheck` route those sources to macOS, or invoke a focused remote
   command explicitly.
3. For exact declarations, signatures, framework presence, or availability,
   query the installed SDK with `apple-api MODULE SYMBOL` or `apple-symbol`.
   Use `apple-sdk-interface MODULE... --sdk iphoneos` when complete public
   module interfaces are required as read-only generator inputs.
4. For semantics, migration advice, release notes, and examples, use
   `apple-doc TERMS` and retrieve only the relevant current Apple page.
5. Use `apple-build`, `apple-test-focused`, or `apple-ci` only when cheaper
   checks cannot establish correctness. Avoid full suites unless necessary.
6. Use `--xcode stable` or `--xcode beta` per invocation. Never permanently
   switch the runner's developer directory.
7. Prefer `--json` and report summaries plus workflow/artifact URLs. Do not
   paste full logs or symbol graphs.

Run `apple-doctor --json` before diagnosing toolchain availability. Run
`apple-sdk-info` when installed Xcode/SDK/simulator versions matter.

Read [authority.md](references/authority.md) only when choosing between SDK,
documentation, Windows Swift, and remote Xcode is ambiguous.
