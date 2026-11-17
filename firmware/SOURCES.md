# Bundled firmware

These files are unmodified binaries redistributed under the SOF firmware release licence
([LICENCE.Intel](LICENCE.Intel)). They are installed **only if the file is missing** on the
target system. Existing (for example newer, distribution-provided) files are never overwritten.

| File | Source | Version |
|------|--------|---------|
| `intel/sof-ipc4/arl-s/sof-arl-s.ri` | [thesofproject/sof-bin](https://github.com/thesofproject/sof-bin), `v2.14.x/sof-ipc4-v2.14.1/arl-s/intel-signed/` | SOF 2.14.1 (Intel-signed) |
| `intel/sof-ace-tplg/sof-hda-generic*.tplg` | Ubuntu 22.04 package `firmware-sof-signed` (built from sof-bin) | 2.0-1ubuntu4.7 |

Why they are needed: Ubuntu 22.04's `firmware-sof-signed 2.0` does not contain the DSP
firmware for Intel Arrow Lake-S/HX (`sof-arl-s.ri`). Without it the kernel cannot boot the
audio DSP and no sound card appears at all ("Dummy Output").

Checksums: [SHA256SUMS](SHA256SUMS) (verified by `install.sh` before anything is copied).
