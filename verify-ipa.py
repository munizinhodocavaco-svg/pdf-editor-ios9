#!/usr/bin/env python3
"""Verify an IPA before installing. Fails fast with clear errors."""
import hashlib, plistlib, zipfile, struct, sys
from pathlib import Path

ipa = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("PDFEditor.ipa")
if not ipa.is_file():
    sys.exit(f"IPA not found: {ipa}")

with zipfile.ZipFile(ipa) as z:
    bad = z.testzip()
    if bad:
        sys.exit(f"CRC failed: {bad}")
    # Find Payload/*.app/Info.plist
    info_path = next(p for p in z.namelist() if p.endswith("/Info.plist"))
    info = plistlib.loads(z.read(info_path))
    # Executable Mach-O
    exe_name = info["CFBundleExecutable"]
    exe_path = info_path.replace("Info.plist", exe_name)
    exe_data = z.read(exe_path)

magic, = struct.unpack("<I", exe_data[:4])
cputype, cpusubtype = struct.unpack("<II", exe_data[4:12])

print(f"✅ {ipa.name} ({ipa.stat().st_size:,} bytes)")
print(f"   Bundle: {info['CFBundleIdentifier']}")
print(f"   Name:   {info.get('CFBundleDisplayName') or info.get('CFBundleName')}")
print(f"   Ver:    {info['CFBundleShortVersionString']} ({info['CFBundleVersion']})")
print(f"   MinOS:  {info.get('MinimumOSVersion', '?')}")
print(f"   Mach-O: magic=0x{magic:08x} cputype={cputype} subtype={cpusubtype} "
    f"({'armv7' if cputype==12 and cpusubtype==9 else 'armv6' if cputype==12 and cpusubtype==6 else 'other'})")
print(f"   Signed: {'_CodeSignature' in str(z.namelist())}")
print(f"   SHA256: {hashlib.sha256(ipa.read_bytes()).hexdigest()}")