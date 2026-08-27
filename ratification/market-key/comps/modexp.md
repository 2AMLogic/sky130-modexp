# modexp comp data (generated, public-sources-only)

Generated 2026-08-27 from the upstream comp library's `modexp.md` entry by an internal, private-repo-only tool. This is a derived, filtered copy — regenerate rather than hand-edit. Every row below cites a public vendor datasheet or a public distributor pricing page; nothing internal survived extraction.

## Comparable parts

| Vendor | Part | Class | RSA support | Throughput | Package | Price | Source |
|---|---|---|---|---|---|---|---|
| NXP | SE050 (e.g. SE050E2) | Plug & Trust secure element (CC EAL6+, FIPS 140-2 L3) | RSA cipher for de-/encryption, up to 4096-bit; ECC, AES, 3DES, SHA also on-die | **Not published** in the public datasheet — no operation-time or ops/sec table found (checked the full document; see Re-verify) | HX2QFN20, 3×3×0.32 mm | not fetched | Datasheet: [nxp.com/docs/en/data-sheet/SE050-DATASHEET.pdf](https://www.nxp.com/docs/en/data-sheet/SE050-DATASHEET.pdf) (Rev. 3.8, 18 Oct 2023) |
| Espressif | ESP32 (e.g. ESP32-D0WD-V3) | General-purpose Wi-Fi/BT MCU with an on-die "RSA Accelerator" peripheral (large-number modular-exponentiation hardware) | Hardware modular exponentiation, operand lengths `N` ∈ {512, 1024, 1536, 2048, 2560, 3072, 3584, 4096} bits — the same 512-bit-step parameterization shape as our own `WIDTH` axis, at a much wider range | **Not published** in the Technical Reference Manual — the RSA chapter documents the register/memory-block protocol only, no cycle-count or timing formula | QFN 5×5 mm (also QFN 6×6 mm, NRND) | not fetched | TRM: [documentation.espressif.com/esp32_technical_reference_manual_en.pdf](https://documentation.espressif.com/esp32_technical_reference_manual_en.pdf) (v5.8), Ch. 15 "RSA Accelerator". Datasheet: [documentation.espressif.com/esp32_datasheet_en.pdf](https://documentation.espressif.com/esp32_datasheet_en.pdf) |

