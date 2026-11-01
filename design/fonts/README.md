# design/fonts/ — IRANYekanX font family

## Status: LICENSE PENDING — private repo until final release

The owner confirmed (2026-11-01) to vendor these files now so that UI work is
never blocked by missing font assets. A license document will be added before
any public release; until then the repository stays private.

## Family

- IRANYekanX (11 weights: UltraLight → ExtraBlack)
- Vendor: https://fontiran.com — Copyright (c) 2021 Moslem Ebrahimi
- Embedded license string (name table ID 13): "To use this font, it is
  necessary to obtain the license from www.fontiran.com"
- License URL (name table ID 14): https://fontiran.com/licenses

## Verification

Every file was verified byte-for-byte against the SHA256 inventory recorded in
`evidence/transfer/fonts_excluded_license.txt` at transfer time
(`sha256sum -c` on all 11 files: OK). The files are added verbatim, as that
manifest instructs once the owner confirms.

## Rules

- Do NOT redistribute outside this private repository while the license
  document is pending.
- Do NOT rename the files; UI code and the audit evidence reference these
  exact names.
- When the license document arrives, drop it in this directory and update the
  status line above from "LICENSE PENDING" to the license type.
