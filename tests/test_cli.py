import json, subprocess, sys, tempfile, unittest
from pathlib import Path
CLI=Path(__file__).parents[1]/"src"/"apple_devtools.py"
class ToolTests(unittest.TestCase):
    def call(self,*a):return subprocess.run([sys.executable,str(CLI),*a],text=True,capture_output=True)
    def test_doctor_marks_windows_limit(self):
        r=self.call("apple-doctor","--json");d=json.loads(r.stdout)
        if sys.platform=="win32":self.assertTrue(d["portable_swift_only"]);self.assertFalse(d["apple_sdk_available"])
    def test_portable_swift_typecheck(self):
        with tempfile.TemporaryDirectory() as x:
            s=Path(x)/"Portable.swift";s.write_text("struct Pair<T> { let first: T; let second: T }\n",encoding="utf-8");r=self.call("apple-typecheck","--path",str(s),"--local","--json");self.assertEqual(r.returncode,0,r.stderr+r.stdout);self.assertEqual(json.loads(r.stdout)["status"],"passed")
    def test_swiftui_routes_on_windows(self):
        with tempfile.TemporaryDirectory() as x:
            s=Path(x)/"AppleOnly.swift";s.write_text('import SwiftUI\nstruct V: View { var body: some View { Text("x") } }\n',encoding="utf-8");r=self.call("apple-typecheck","--path",str(s),"--local","--json")
            if sys.platform=="win32":self.assertEqual(json.loads(r.stdout)["status"],"routed")
    def test_sdk_interface_requires_valid_modules(self):
        missing=self.call("apple-sdk-interface","--sdk","iphoneos")
        self.assertNotEqual(missing.returncode,0)
        self.assertIn("provide one or more Swift module names",missing.stderr)
        invalid=self.call("apple-sdk-interface","SwiftUI/../../Secrets","--sdk","iphoneos")
        self.assertNotEqual(invalid.returncode,0)
        self.assertIn("invalid Swift module name",invalid.stderr)
if __name__=="__main__":unittest.main()
