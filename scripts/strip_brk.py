#!/usr/bin/env python3
"""Strip BRK junk from the linked Recoil-Br.dylib (post-link step).

frida-gum (statically linked from the devkit) contains tagged `brk` traps that
survive into our dylib and are picked up by JIT debuggers as SIGILL noise:

  * brk #0x539 (1337) — gum's exception-handling probe. Executed once at gum
    init with x0=0, x1=x2=0x539, x3=3; gum expects its own exception handler
    to reply x0=0x1337 and step past. External JIT tools intercept it first
    and spam "Skipping breakpoint: brk immediate 0x539". We replace it with
    NOP: the probe then deterministically returns "exceptions unsupported"
    (x0 stays 0) — exactly what happens today when the tool skips it, so the
    runtime behaviour is unchanged and proven, minus the signal.
  * brk #0x3E8 (1000) — gum stub entries shaped `brk; b <common tail>`; the
    following branch keeps the flow valid after the NOP, and these stubs are
    never executed in normal operation anyway.

Everything else (`brk #1` = llvm.trap) is real crash-path code — it is
reported but NOT touched by default (pass --traps to NOP it too; runtime
noise from it is already covered by the jit_handler.js debugger script).

The scanner only looks at sections carrying S_ATTR_*INSTRUCTIONS, and the
probe is located by its unique argument-setup anchor (movz x1,#0x539;
movz x2,#0x539; movz x3,#3) rather than by the brk alone. Idempotent: an
already patched probe (same anchor + NOP) is recognised and reported.

Usage:
  python3 scripts/strip_brk.py <dylib>              # patch in place
  python3 scripts/strip_brk.py <dylib> --dry-run    # report only
  python3 scripts/strip_brk.py <dylib> --out PATH   # write patched copy
  python3 scripts/strip_brk.py <dylib> --traps      # also NOP llvm.trap etc.
  python3 scripts/strip_brk.py <dylib> --no-strict  # don't fail when the
                                                    # probe pattern is absent
Exit codes: 0 = patched/already clean; 1 = probe pattern not found (strict
mode) or the file could not be processed.
"""
import argparse
import struct
import sys

MH_MAGIC_64 = 0xFEEDFACF
LC_SEGMENT_64 = 0x19
S_ATTR_SOME_INSTRUCTIONS = 0x00000400
S_ATTR_PURE_INSTRUCTIONS = 0x00000800
EXEC_SECT_FLAGS = S_ATTR_SOME_INSTRUCTIONS | S_ATTR_PURE_INSTRUCTIONS

NOP = 0xD503201F
BRK_MASK = 0xFFE0001F
BRK_BASE = 0xD4200000
B_MASK = 0xFC000000
B_BASE = 0x14000000

PROBE_IMM = 0x539
STUB_IMM = 0x3E8

# gum probe layout (offsets relative to the anchor = movz x1,#0x539):
#   -0x04 mov x0,#0   | +0x00 mov x1,#0x539 | +0x04 mov x2,#0x539
#   +0x08 mov x3,#3   | +0x0C mov x4,x8     | +0x10 mov x5,x9
#   +0x14 brk #0x539  (or NOP once patched)
PROBE_ANCHOR = (0xD280A721, 0xD280A722, 0xD2800063)  # movz x1/x2 #0x539, movz x3 #3
PROBE_BRK_OFFSET = 0x14


def brk_imm(word):
    """Return the brk immediate if the word encodes `brk #imm`, else None."""
    if (word & BRK_MASK) == BRK_BASE:
        return (word >> 5) & 0xFFFF
    return None


def word_at(data, pos):
    return struct.unpack_from("<I", data, pos)[0]


def exec_sections(data):
    """Return [(name, fileoff, filesize)] of executable sections."""
    if len(data) < 32 or struct.unpack_from("<I", data, 0)[0] != MH_MAGIC_64:
        raise ValueError("not a little-endian 64-bit Mach-O (fat binaries unsupported)")
    ncmds = struct.unpack_from("<I", data, 16)[0]
    off = 32
    zones = []
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", data, off)
        if cmd == LC_SEGMENT_64:
            seg = data[off + 8:off + 24].split(b"\0")[0].decode("latin1")
            nsects = struct.unpack_from("<I", data, off + 64)[0]
            so = off + 72
            for _s in range(nsects):
                sect = data[so:so + 16].split(b"\0")[0].decode("latin1")
                ssize = struct.unpack_from("<Q", data, so + 40)[0]
                offset = struct.unpack_from("<I", data, so + 48)[0]
                flags = struct.unpack_from("<I", data, so + 64)[0]
                if flags & EXEC_SECT_FLAGS and ssize:
                    zones.append((f"{seg},{sect}", offset, ssize))
                so += 80
        off += size
    return zones


def find_probe(data, zones):
    """Locate the gum probe via its argument-setup anchor.

    Returns (target_pos or None, state) where state is one of:
    'probe' (brk #0x539 at the expected spot), 'patched' (NOP there),
    'drifted' (anchor present but neither brk nor NOP at target),
    'absent' (no anchor in code).
    """
    for _name, off, size in zones:
        for pos in range(off, off + (size & ~3) - PROBE_BRK_OFFSET - 4, 4):
            if (word_at(data, pos) == PROBE_ANCHOR[0]
                    and word_at(data, pos + 4) == PROBE_ANCHOR[1]
                    and word_at(data, pos + 8) == PROBE_ANCHOR[2]):
                target = pos + PROBE_BRK_OFFSET
                w = word_at(data, target)
                if w == 0xD4200000 | (PROBE_IMM << 5):
                    return target, "probe"
                if w == NOP:
                    return target, "patched"
                return target, "drifted"
    return None, "absent"


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("dylib", help="path to Recoil-Br.dylib")
    ap.add_argument("--out", help="write patched copy here instead of in place")
    ap.add_argument("--dry-run", action="store_true", help="report only, no writes")
    ap.add_argument("--traps", action="store_true",
                    help="also NOP brk #1 (llvm.trap) and any other brk in code")
    ap.add_argument("--no-strict", action="store_true",
                    help="exit 0 even when the gum probe pattern is absent")
    ap.add_argument("--backup", help="save the original to this path before patching")
    args = ap.parse_args()

    data = bytearray(open(args.dylib, "rb").read())
    try:
        zones = exec_sections(data)
    except ValueError as e:
        print(f"strip_brk: ERROR: {e}")
        return 1
    if not zones:
        print("strip_brk: ERROR: no executable sections found")
        return 1
    for name, off, size in zones:
        print(f"  code zone {name:<28} file {off:#x}..{off + size:#x}")

    probe_pos, probe_state = find_probe(data, zones)

    patches = []       # (file_offset, old_word, new_word, reason)
    report = {}        # imm -> {"code": n, "patched": n, "kept": n}

    def slot(imm):
        return report.setdefault(imm, {"code": 0, "patched": 0, "kept": 0})

    if probe_state in ("probe", "patched", "drifted"):
        imm = brk_imm(word_at(data, probe_pos)) or PROBE_IMM
        r = slot(imm)
        r["code"] += 1
        if probe_state == "probe":
            patches.append((probe_pos, word_at(data, probe_pos), NOP,
                            "gum exception probe (anchor ok)"))
            r["patched"] += 1
        elif probe_state == "patched":
            r["kept"] += 1
        else:
            r["kept"] += 1
            print(f"strip_brk: WARNING: probe anchor found but target {probe_pos:#x} "
                  f"holds {word_at(data, probe_pos):#x} (neither brk nor NOP)")

    for _name, off, size in zones:
        for pos in range(off, off + (size & ~3), 4):
            word = word_at(data, pos)
            imm = brk_imm(word)
            if imm is None or (imm == PROBE_IMM and probe_state != "absent"):
                continue
            r = slot(imm)
            r["code"] += 1
            nxt = word_at(data, pos + 4) if pos + 8 <= len(data) else 0
            if imm == PROBE_IMM:  # brk #0x539 without the anchor - patch, but say so
                patches.append((pos, word, NOP,
                                "brk #0x539 WITHOUT gum anchor (layout drifted)"))
                r["patched"] += 1
            elif imm == STUB_IMM:
                if (nxt & B_MASK) == B_BASE:
                    patches.append((pos, word, NOP, "gum stub (brk; b <tail>)"))
                    r["patched"] += 1
                else:
                    r["kept"] += 1
                    print(f"strip_brk: note: brk #{imm:#x} at {pos:#x} without a "
                          f"following branch - left as is")
            elif args.traps:
                patches.append((pos, word, NOP,
                                "trap (--traps; llvm.trap reaches UB after NOP)"))
                r["patched"] += 1
            else:
                r["kept"] += 1

    print()
    if report:
        print(f"  {'brk imm':<10} {'in code':<9} {'patched':<9} kept")
        for imm in sorted(report):
            r = report[imm]
            print(f"  #{imm:#06x}    {r['code']:<9} {r['patched']:<9} {r['kept']}")
    else:
        print("  no brk instructions inside code sections")
    print()

    if probe_state == "patched":
        print("strip_brk: probe already patched (anchor + NOP) - nothing to do")
        return 0

    if not patches:
        print("strip_brk: nothing patched")
        if probe_state == "absent" and not args.no_strict:
            print("strip_brk: STRICT: gum probe pattern not found - has gum changed?")
            return 1
        return 0

    for pos, _old, new, why in patches:
        struct.pack_into("<I", data, pos, new)
        print(f"  patch {pos:#x}: -> {new:#x}   ({why})")

    if args.dry_run:
        print(f"strip_brk: dry run, {len(patches)} word(s) would be patched")
        return 0
    if args.backup:
        open(args.backup, "wb").write(bytes(open(args.dylib, "rb").read()))
    out = args.out or args.dylib
    with open(out, "wb") as f:
        f.write(data)
    print(f"strip_brk: wrote {out} ({len(patches)} word(s) patched)")

    # verification pass
    left = []
    for _name, off, size in zones:
        for pos in range(off, off + (size & ~3), 4):
            imm = brk_imm(word_at(data, pos))
            if imm is not None and not (imm == PROBE_IMM and pos == probe_pos
                                        and probe_state == "probe"):
                left.append((pos, imm))
    if left:
        print("strip_brk: note: remaining brk in code (by design, see --traps): "
              + ", ".join(f"{p:#x}(#{i:#x})" for p, i in left))
    else:
        print("strip_brk: verified: no brk left in code sections")
    return 0


if __name__ == "__main__":
    sys.exit(main())
