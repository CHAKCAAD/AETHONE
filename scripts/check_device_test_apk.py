#!/usr/bin/env python3
"""CI gate for the device-test artifact (job device-test-apk).

Reads `aapt2 dump xmltree --file AndroidManifest.xml <apk>` output and checks:

  release APK (com.chakcaad.aethone, the one users get):
    * <application> is NOT debuggable;
    * DeviceTestReceiver (the debug-only device hook) is NOT declared;
    * ShieldTestReceiver (CI emulator driver) is declared exported=false;
  DA APK (com.chakcaad.aethone.da, device-test only):
    * debuggable;
    * DeviceTestReceiver declared, exported, protected by android.permission.DUMP;
    * ShieldTestReceiver still exported=false.

Usage: check_device_test_apk.py <release|da> <xmltree.txt>
Exit 0 = pass, 1 = fail (each failure printed as ::error::).
"""
import re
import sys

DEVICE_HOOK = "com.chakcaad.aethone.shield.DeviceTestReceiver"
CI_HOOK = "com.chakcaad.aethone.shield.ShieldTestReceiver"


def elements(text):
    """Yield (tag, attrs) for every element in aapt2 xmltree output."""
    tag, attrs = None, {}
    for line in text.splitlines():
        s = line.strip()
        m = re.match(r"E: (\S+)", s)
        if m:
            if tag is not None:
                yield tag, attrs
            tag, attrs = m.group(1), {}
            continue
        m = re.match(r"A: (?:http://schemas\.android\.com/apk/res/android:)?([A-Za-z]+)(?:\(0x[0-9a-f]+\))?=(.*)$", s)
        if m and tag is not None:
            attrs[m.group(1)] = m.group(2).strip()
    if tag is not None:
        yield tag, attrs


def val(v):
    if v is None:
        return None
    v = v.strip()
    m = re.match(r'"([^"]*)"', v)
    if m:
        return m.group(1)
    if v in ("true", "false"):
        return v
    m = re.search(r"0x([0-9a-f]+)$", v)
    if m:  # (type 0x12)0xffffffff -> true ; 0x0 -> false
        return "false" if int(m.group(1), 16) == 0 else "true"
    return v


def main():
    kind, path = sys.argv[1], sys.argv[2]
    text = open(path, encoding="utf-8", errors="replace").read()
    els = list(elements(text))
    errors = []
    app = [a for t, a in els if t == "application"]
    if not app:
        print("::error::no <application> element in the xmltree dump")
        return 1
    debuggable = val(app[0].get("debuggable")) == "true"
    pkg = next((val(a.get("package")) for t, a in els if t == "manifest"), None)
    def full(n):  # relative class names (".shield.X") resolve against the namespace
        return "com.chakcaad.aethone" + n if n and n.startswith(".") else n
    receivers = {full(val(a.get("name"))): a for t, a in els if t == "receiver"}
    dev = receivers.get(DEVICE_HOOK)
    ci = receivers.get(CI_HOOK)
    print(f"package={pkg} debuggable={debuggable} receivers={sorted(k for k in receivers if k)}")
    if ci is None:
        errors.append(f"{CI_HOOK} not declared (expected, exported=false)")
    elif val(ci.get("exported")) != "false":
        errors.append(f"{CI_HOOK} exported={val(ci.get('exported'))} (must be false)")
    if kind == "release":
        if pkg != "com.chakcaad.aethone":
            errors.append(f"release package is {pkg}")
        if debuggable:
            errors.append("release APK is debuggable")
        if dev is not None:
            errors.append(f"release APK declares the debug-only {DEVICE_HOOK}")
    elif kind == "da":
        if pkg != "com.chakcaad.aethone.da":
            errors.append(f"DA package is {pkg}")
        if not debuggable:
            errors.append("DA APK is not debuggable (run-as / hooks would not work)")
        if dev is None:
            errors.append(f"DA APK lacks {DEVICE_HOOK}")
        else:
            if val(dev.get("exported")) != "true":
                errors.append(f"{DEVICE_HOOK} not exported (adb could not reach it)")
            if val(dev.get("permission")) != "android.permission.DUMP":
                errors.append(f"{DEVICE_HOOK} permission={val(dev.get('permission'))} (must be android.permission.DUMP)")
    else:
        print(f"::error::unknown kind {kind}")
        return 1
    for e in errors:
        print(f"::error::device-test manifest gate ({kind}): {e}")
    if not errors:
        print(f"device-test manifest gate ({kind}): PASS")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
