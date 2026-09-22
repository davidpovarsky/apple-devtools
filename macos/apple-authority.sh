#!/bin/bash
set -euo pipefail
operation="${1:-doctor}"; sdk="${APPLE_SDK:-iphonesimulator}"; project_path="${APPLE_PATH:-}"; scheme="${APPLE_SCHEME:-}"; destination="${APPLE_DESTINATION:-platform=iOS Simulator,name=iPhone 17}"
mkdir -p .apple-devtools-logs; log=".apple-devtools-logs/${operation}.log"
choose_xcode(){
  mode="${APPLE_XCODE:-default}"
  if [[ "$mode" == beta ]];then for x in /Applications/Xcode*beta*.app;do [[ -d "$x" ]]&&export DEVELOPER_DIR="$x/Contents/Developer"&&return;done;echo 'No beta Xcode installed'>&2;exit 2;fi
  if [[ "$mode" == stable ]];then for x in /Applications/Xcode*.app;do [[ -d "$x" && "$x" != *beta* ]]&&export DEVELOPER_DIR="$x/Contents/Developer"&&return;done;echo 'No stable Xcode installed'>&2;exit 2;fi
}
discover(){ [[ -n "$project_path" ]]&&return;project_path="$(find . -maxdepth 4 -name '*.xcworkspace' -not -path '*.xcodeproj/*' -not -path '*/.*' -print -quit)";[[ -n "$project_path" ]]||project_path="$(find . -maxdepth 4 -name '*.xcodeproj' -not -path '*/.*' -print -quit)"; }
filtered(){ set +e;"$@">"$log" 2>&1;code=$?;set -e;grep -nE 'error:|fatal error:|warning:|BUILD (SUCCEEDED|FAILED)|TEST (SUCCEEDED|FAILED)|The following build commands failed' "$log"|tail -120||true;echo "full_log=$log";return "$code"; }
choose_xcode
case "$operation" in
sdk-info|doctor)
  echo "active_xcode=$(xcodebuild -version|tr '\n' ' ')";echo "developer_dir=${DEVELOPER_DIR:-$(xcode-select -p)}"
  for x in /Applications/Xcode*.app;do if [[ -d "$x" ]];then xv="$(DEVELOPER_DIR="$x/Contents/Developer" xcodebuild -version)";printf 'installed_xcode=%s: %s\n' "$x" "${xv%%$'\n'*}";fi;done
  for s in macosx iphoneos iphonesimulator watchos watchsimulator appletvos appletvsimulator xros xrsimulator;do xcrun --sdk "$s" --show-sdk-version 2>/dev/null|sed "s/^/$s=/"||true;done
  xcrun simctl list devices available -j>.apple-devtools-logs/simulators.json;;
api)
  module="${APPLE_MODULE:?module required}";symbol="${APPLE_SYMBOL:?symbol required}"
  case "$sdk" in macosx)target=arm64-apple-macosx;;iphoneos)target=arm64-apple-ios;;iphonesimulator)target=arm64-apple-ios-simulator;;watchos)target=arm64-apple-watchos;;watchsimulator)target=arm64-apple-watchos-simulator;;appletvos)target=arm64-apple-tvos;;appletvsimulator)target=arm64-apple-tvos-simulator;;xros)target=arm64-apple-xros;;xrsimulator)target=arm64-apple-xros-simulator;;*)echo "Unsupported SDK: $sdk";exit 2;;esac
  out="$(mktemp -d)";xcrun swift-symbolgraph-extract -module-name "$module" -sdk "$(xcrun --sdk "$sdk" --show-sdk-path)" -target "$target" -output-dir "$out">/dev/null
  jq --arg q "$symbol" '[.symbols[]|select((.identifier.precise|contains($q)) or (.names.title|contains($q)))|{title:.names.title,precise:.identifier.precise,path:.pathComponents,availability:.availability}]|.[:20]' "$out"/*.symbols.json;;
sdk-interface)
  modules_input="${APPLE_MODULES:?comma-separated Swift modules required}"
  sdkroot="$(xcrun --sdk "$sdk" --show-sdk-path)"
  sdk_version="$(xcrun --sdk "$sdk" --show-sdk-version)"
  xcode_version="$(xcodebuild -version)"
  developer_dir="${DEVELOPER_DIR:-$(xcode-select -p)}"
  artifact_dir=".apple-devtools-logs/sdk-interfaces"
  rm -rf "$artifact_dir"
  mkdir -p "$artifact_dir"
  manifest_modules="$(mktemp)"
  printf '{}\n' > "$manifest_modules"
  IFS=',' read -ra modules <<< "$modules_input"
  selected_target=""
  for module in "${modules[@]}"; do
    module="$(echo "$module" | tr -d '[:space:]')"
    [[ "$module" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { echo "Invalid Swift module: $module" >&2; exit 2; }
    interface_dir="$sdkroot/System/Library/Frameworks/$module.framework/Modules/$module.swiftmodule"
    [[ -d "$interface_dir" ]] || { echo "Swift module interface directory not found: $interface_dir" >&2; exit 2; }
    selected=""
    exact="$interface_dir/arm64-apple-ios.swiftinterface"
    if [[ -f "$exact" ]]; then
      selected="$exact"
    else
      while IFS= read -r candidate; do selected="$candidate"; break; done < <(find "$interface_dir" -maxdepth 1 -type f -name 'arm64*-apple-ios*.swiftinterface' ! -name '*simulator*' ! -name '*macabi*' | LC_ALL=C sort)
    fi
    [[ -n "$selected" ]] || { echo "No arm64 iOS device Swift interface found for $module in $interface_dir" >&2; exit 2; }
    target="$(basename "$selected" .swiftinterface)"
    [[ "$target" == arm64*-apple-ios* && "$target" != *simulator* && "$target" != *macabi* ]] || { echo "Selected interface is not an arm64 iOS device variant: $selected" >&2; exit 2; }
    if [[ -n "$selected_target" && "$selected_target" != "$target" ]]; then
      echo "Selected interface targets differ: $selected_target and $target" >&2
      exit 2
    fi
    selected_target="$target"
    destination="$artifact_dir/$module.swiftinterface"
    cp "$selected" "$destination"
    sha256="$(shasum -a 256 "$selected" | awk '{print $1}')"
    updated="$(mktemp)"
    jq --arg module "$module" --arg source "$selected" --arg artifact "$module.swiftinterface" --arg sha256 "$sha256" '. + {($module): {sourceFile: $source, artifactFile: $artifact, sha256: $sha256}}' "$manifest_modules" > "$updated"
    mv "$updated" "$manifest_modules"
  done
  jq -n \
    --arg schemaVersion "1" \
    --arg xcodeVersion "$xcode_version" \
    --arg developerDir "$developer_dir" \
    --arg sdk "$sdk" \
    --arg sdkRoot "$sdkroot" \
    --arg sdkVersion "$sdk_version" \
    --arg target "$selected_target" \
    --slurpfile modules "$manifest_modules" \
    '{schemaVersion: ($schemaVersion | tonumber), xcodeVersion: $xcodeVersion, developerDir: $developerDir, sdk: $sdk, sdkRoot: $sdkRoot, sdkVersion: $sdkVersion, target: $target, modules: $modules[0]}' > "$artifact_dir/manifest.json"
  rm -f "$manifest_modules"
  jq . "$artifact_dir/manifest.json";;
typecheck) [[ -n "$project_path" ]]||{ echo 'APPLE_PATH must name a Swift file';exit 2;};filtered xcrun --sdk "$sdk" swiftc -typecheck -sdk "$(xcrun --sdk "$sdk" --show-sdk-path)" "$project_path";;
signing-doctor) security find-identity -v -p codesigning|sed -E 's/[0-9A-F]{40}/<certificate-hash>/g';count="$(find "$HOME/Library/MobileDevice/Provisioning Profiles" -maxdepth 1 -name '*.mobileprovision' 2>/dev/null|wc -l||true)";printf 'provisioning_profiles=%s\n' "${count// /}";;
entitlements) [[ -n "$project_path" ]]||{ echo 'APPLE_PATH must name an app/archive/binary';exit 2;};codesign -d --entitlements :- "$project_path" >"$log" 2>&1||true;grep -vE 'TeamIdentifier|application-identifier|keychain-access-groups' "$log"|head -100;;
archive-check) [[ -n "$project_path" ]]||{ echo 'APPLE_PATH must name an xcarchive';exit 2;};plutil -p "$project_path/Info.plist"|head -100;find "$project_path/Products/Applications" -maxdepth 1 -name '*.app' -print;;
build|ci|sim|test|test-focused)
  discover;if [[ "$project_path" == *.xcworkspace ]];then base=(-workspace "$project_path");else base=(-project "$project_path");fi
  xcodebuild "${base[@]}" -list -json>.apple-devtools-logs/project.json;[[ -n "$scheme" ]]||scheme="$(jq -r '.project.schemes[0] // .workspace.schemes[0]' .apple-devtools-logs/project.json)";xcodebuild "${base[@]}" -scheme "$scheme" -showBuildSettings>.apple-devtools-logs/build-settings.log;grep -E 'SDKROOT|SUPPORTED_PLATFORMS|.*DEPLOYMENT_TARGET|PRODUCT_BUNDLE_IDENTIFIER' .apple-devtools-logs/build-settings.log|head -80
  args=(xcodebuild "${base[@]}" -scheme "$scheme" -destination "$destination")
  [[ "$operation" == build || "$operation" == ci || "$operation" == sim ]]&&args+=(build);[[ "$operation" == test ]]&&args+=(test);if [[ "$operation" == test-focused ]];then args+=(test);[[ -n "${APPLE_ONLY_TESTING:-}" ]]&&args+=("-only-testing:${APPLE_ONLY_TESTING}");fi;filtered "${args[@]}";;
compile-sweep)
  if [[ -f "./build-xcframework.sh" ]]; then
    echo "=== Preparing build inputs and regenerating project ==="
    command -v xcodegen >/dev/null || brew install xcodegen
    gem list -i xcodeproj >/dev/null || gem install xcodeproj --no-document
    [[ -f app/Config/Secrets.xcconfig.example && ! -f app/Config/Secrets.xcconfig ]] && cp app/Config/Secrets.xcconfig.example app/Config/Secrets.xcconfig
    chmod +x build-xcframework.sh utilities/scripts/patch-app-icon.rb 2>/dev/null || true
    ./build-xcframework.sh release
    (cd app && xcodegen generate)
    [[ -f utilities/scripts/verify-apple-identity.py ]] && python3 utilities/scripts/verify-apple-identity.py
  fi
  [[ -n "$project_path" && "$project_path" == *.xcodeproj ]] || project_path="$(find . -maxdepth 4 -name '*.xcodeproj' -not -path '*/.*' -print -quit)"
  echo "Using project: $project_path"
  failed=()

  scheme="${APPLE_SCHEME:-PinkhaRelease}"
  echo "::group::Compile scheme $scheme (main app)"
  app_log=".apple-devtools-logs/${scheme}-compile.log"
  if ! xcodebuild build \
    -project "$project_path" \
    -scheme "$scheme" \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -derivedDataPath ".apple-devtools-logs/DerivedData-Preflight" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO 2>&1 | tee "$app_log"; then
    echo "::error::Compilation failed for scheme $scheme"
    grep -nE 'error:|fatal error:|The following build commands failed' "$app_log" | tail -60 || true
    failed+=("$scheme")
  else
    echo "Compilation succeeded for scheme $scheme"
  fi
  echo "::endgroup::"

  targets_input="${APPLE_TARGETS:-ChavrusaNotesShare,ChavrusaNotesWidgets}"
  IFS=',' read -ra targets <<< "$targets_input"
  for target in "${targets[@]}"; do
    target="$(echo "$target" | tr -d '[:space:]')"
    [[ -z "$target" ]] && continue
    echo "::group::Compile target $target"
    target_log=".apple-devtools-logs/${target}-compile.log"
    if ! xcodebuild build \
      -project "$project_path" \
      -target "$target" \
      -configuration Release \
      -sdk iphoneos \
      CODE_SIGNING_ALLOWED=NO \
      CODE_SIGN_IDENTITY="" \
      CODE_SIGNING_REQUIRED=NO 2>&1 | tee "$target_log"; then
      echo "::error::Compilation failed for target $target"
      grep -nE 'error:|fatal error:|The following build commands failed' "$target_log" | tail -60 || true
      failed+=("$target")
    else
      echo "Compilation succeeded for target $target"
    fi
    echo "::endgroup::"
  done
  if [ ${#failed[@]} -gt 0 ]; then
    echo "::error::Diagnostic compile sweep failed for: ${failed[*]}"
    exit 1
  fi
  echo "Diagnostic compile sweep passed for all targets and scheme"
  ;;
*)echo "Unknown operation: $operation" >&2;exit 2;;esac
