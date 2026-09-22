#!/usr/bin/env python3
from __future__ import annotations
import argparse, json, os, platform, re, shutil, subprocess, sys, urllib.parse
from pathlib import Path

APPLE_MODULES={"AppKit","ARKit","AuthenticationServices","AVKit","CallKit","CloudKit","CoreML","HealthKit","MapKit","MetalKit","PassKit","RealityKit","SwiftData","SwiftUI","TVUIKit","UIKit","VisionKit","WatchKit","WidgetKit"}
REMOTE={"apple-sdk-info":"sdk-info","apple-sdk-interface":"sdk-interface","apple-api":"api","apple-symbol":"api","apple-build":"build","apple-test":"test","apple-test-focused":"test-focused","apple-sim":"sim","apple-signing-doctor":"signing-doctor","apple-entitlements":"entitlements","apple-archive-check":"archive-check","apple-ci":"ci","apple-compile-sweep":"compile-sweep"}

def emit(v,j=False):
    print(json.dumps(v,separators=(",",":"),sort_keys=True) if j else (" ".join(f"{k}={x}" for k,x in v.items()) if isinstance(v,dict) else v))
def run(a,cwd=None): return subprocess.run(a,cwd=cwd,text=True,capture_output=True)
def ver(n):
    p=shutil.which(n)
    if not p:return None
    if n=="python": return {"path":sys.executable,"version":platform.python_version()}
    try:r=run([p,"--version"])
    except OSError:return {"path":p,"version":"present"}
    lines=(r.stdout or r.stderr).strip().splitlines()
    return {"path":p,"version":lines[0] if lines else "unknown"}
def imports(p):
    found=set(re.findall(r"^\s*(?:@testable\s+)?import\s+([A-Za-z_]\w*)",p.read_text(encoding="utf-8"),re.M))
    return sorted(found&APPLE_MODULES)
def slug():
    r=run(["gh","repo","view","--json","nameWithOwner","--jq",".nameWithOwner"])
    return r.stdout.strip() if r.returncode==0 else ""
def dispatch(op,n,extra=None):
    if not shutil.which("gh"):raise SystemExit("GitHub CLI is required for macOS/Xcode dispatch")
    target=n.repository or slug(); fields={"operation":op,"repository":target,"ref":n.ref,"xcode":n.xcode,"sdk":n.sdk,"path":n.path or "","scheme":n.scheme or "","destination":n.destination or "","only_testing":n.only_testing or "","targets":getattr(n,"targets",None) or "","runs_on":getattr(n,"runs_on",None) or ""}
    fields.update(extra or {}); cmd=["gh","workflow","run","apple-authority.yml","--repo","davidpovarsky/apple-devtools","--ref",n.toolkit_ref]
    for k,v in fields.items():
        if v:cmd += ["-f",f"{k}={v}"]
    rc=subprocess.run(cmd).returncode
    if rc:raise SystemExit(rc)
    emit({"status":"dispatched","operation":op,"repository":target or "apple-devtools"},n.json);return 0
def add_common(p):
    p.add_argument("--json",action="store_true");p.add_argument("--repository");p.add_argument("--ref",default="main");p.add_argument("--toolkit-ref",default=os.environ.get("APPLE_DEVTOOLS_REF","main"));p.add_argument("--xcode",choices=("default","stable","beta"),default="default");p.add_argument("--sdk",default="iphonesimulator");p.add_argument("--path");p.add_argument("--scheme");p.add_argument("--destination");p.add_argument("--only-testing");p.add_argument("--targets");p.add_argument("--runs-on")
def main(argv=None):
    a=list(sys.argv[1:] if argv is None else argv); invoked=Path(sys.argv[0]).stem.lower(); cmd=invoked if invoked.startswith("apple-") else (a.pop(0) if a else "apple-doctor")
    p=argparse.ArgumentParser(prog=cmd);add_common(p);p.add_argument("terms",nargs="*");p.add_argument("--local",action="store_true");n=p.parse_args(a)
    if cmd=="apple-doctor":
        tools={x:ver(x) for x in ("swift","swiftc","sourcekit-lsp","swift-format","git","gh","python")};data={"platform":platform.system(),"portable_swift_only":platform.system()=="Windows","apple_sdk_available":platform.system()=="Darwin" and bool(shutil.which("xcrun")),"tools":tools};emit(data,n.json);return 0 if tools["swift"] and tools["swiftc"] else 1
    if cmd=="apple-doc":
        q=" ".join(n.terms);emit({"authority":"Apple Developer Documentation","query":q,"url":"https://developer.apple.com/search/?q="+urllib.parse.quote(q)},n.json);return 0
    if cmd=="apple-typecheck":
        if not n.path:p.error("--path is required")
        source=Path(n.path).resolve();mods=imports(source)
        if platform.system()=="Windows" and mods:
            if n.local:emit({"status":"routed","authority":"macOS/Xcode","apple_modules":mods},n.json);return 0
            return dispatch("typecheck",n)
        compiler=shutil.which("swiftc")
        if not compiler:raise SystemExit("swiftc is not available")
        r=run([compiler,"-typecheck",str(source)]);diag="\n".join((r.stdout+r.stderr).splitlines()[-80:]);emit({"status":"passed" if r.returncode==0 else "failed","authority":"local Swift compiler","diagnostics":diag},n.json);return r.returncode
    if cmd in ("apple-api","apple-symbol"):
        if len(n.terms)<2:p.error("provide MODULE SYMBOL, for example: SwiftUI searchable")
        return dispatch("api",n,{"module":n.terms[0],"symbol":n.terms[1]})
    if cmd=="apple-sdk-interface":
        if not n.terms:p.error("provide one or more Swift module names, for example: SwiftUI SwiftUICore")
        invalid=[module for module in n.terms if not re.fullmatch(r"[A-Za-z_]\w*",module)]
        if invalid:p.error("invalid Swift module name: "+invalid[0])
        return dispatch("sdk-interface",n,{"modules":",".join(n.terms)})
    if cmd=="apple-sdk-info" and n.local and platform.system()!="Darwin":emit({"platform":platform.system(),"apple_sdks":[],"note":"Real Apple SDK discovery requires macOS/Xcode"},n.json);return 0
    if cmd in REMOTE:return dispatch(REMOTE[cmd],n)
    p.error(f"unknown command: {cmd}")
if __name__=="__main__":raise SystemExit(main())
