# Register new Swift files in Freeify.xcodeproj (Sources phase + Freeify group).
import re, sys
path = "Freeify.xcodeproj/project.pbxproj"
s = open(path).read()
for name in sys.argv[1:]:
    if f"path = {name};" in s:
        continue
    used = set(re.findall(r"\b(A[0-9A-F]{23})\b", s))
    n = 1
    while f"A1{n:022X}" in used or f"A2{n:022X}" in used:
        n += 1
    build, ref = f"A1{n:022X}", f"A2{n:022X}"
    s = s.replace("/* End PBXBuildFile section */",
        f"\t\t{build} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref} /* {name} */; }};\n/* End PBXBuildFile section */")
    s = s.replace("/* End PBXFileReference section */",
        f"\t\t{ref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = \"<group>\"; }};\n/* End PBXFileReference section */")
    s = s.replace("\t\t\t\tA20000000000000000000005 /* Info.plist */,",
        f"\t\t\t\t{ref} /* {name} */,\n\t\t\t\tA20000000000000000000005 /* Info.plist */,")
    s = re.sub(r"(A30000000000000000000002 /\* Sources \*/ = \{[^}]*?files = \()([^)]*)\)",
        lambda m: f"{m.group(1)}{m.group(2)}, {build})", s, count=1)
    print(name, build, ref)
open(path, "w").write(s)
