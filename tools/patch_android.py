#!/usr/bin/env python3
"""Patches a freshly generated Flutter project for Bluetooth + notifications.
Usage: patch_android.py <project_dir>   (idempotent)"""
import re, sys, pathlib

root = pathlib.Path(sys.argv[1])
ok = True

# ---- AndroidManifest.xml ----
manifest = root / "android/app/src/main/AndroidManifest.xml"
text = manifest.read_text()
if "BLUETOOTH_SCAN" in text:
    print("manifest: already patched")
else:
    perms = """    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-feature android:name="android.hardware.bluetooth_le" android:required="true" />

"""
    new, n = re.subn(r"(\s*)<application", "\n" + perms + r"    <application", text, count=1)
    if n:
        manifest.write_text(new)
        print("manifest: patched")
    else:
        ok = False
        print("manifest: COULD NOT PATCH - add the permissions from README.md by hand")

# ---- app/build.gradle(.kts): core library desugaring ----
kts = root / "android/app/build.gradle.kts"
groovy = root / "android/app/build.gradle"
if kts.exists():
    g = kts.read_text()
    if "isCoreLibraryDesugaringEnabled" in g:
        print("gradle: already patched")
    else:
        g, n1 = re.subn(r"(compileOptions\s*\{)", r"\1\n        isCoreLibraryDesugaringEnabled = true", g, count=1)
        g += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
        if n1:
            kts.write_text(g)
            print("gradle: patched")
        else:
            ok = False
            print("gradle: COULD NOT PATCH - see README.md")
elif groovy.exists():
    g = groovy.read_text()
    if "coreLibraryDesugaringEnabled" in g:
        print("gradle: already patched")
    else:
        g, n1 = re.subn(r"(compileOptions\s*\{)", r"\1\n        coreLibraryDesugaringEnabled true", g, count=1)
        g += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n"
        if n1:
            groovy.write_text(g)
            print("gradle: patched")
        else:
            ok = False
            print("gradle: COULD NOT PATCH - see README.md")
else:
    ok = False
    print("gradle: build file not found")

sys.exit(0 if ok else 1)
