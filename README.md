# sof-hda-speaker-fix

**One-step audio fix for Intel Arrow Lake-HX audio (`8086:7f50`, SOF DSP) with a Realtek
ALC274 codec on Ubuntu 22.04.** It covers both "no sound card at all / Dummy Output" and
"sound card present but speakers silent".

| Audio hardware   | Model                                                                 |
|------------------|-----------------------------------------------------------------------|
| Audio controller | **Intel Arrow Lake-S/HX PCH audio DSP (Intel ACE)** · PCI ID `8086:7f50` |
| Linux driver     | **Sound Open Firmware (SOF)** · `sof-audio-pci-intel-mtl`, firmware `sof-arl-s.ri` (IPC4) |
| Codec            | **Realtek ALC274** (HD Audio) · codec subsystem `1462:1474`           |
| ALSA card        | `sof-hda-dsp` (generic HDA topology `sof-hda-generic-2ch.tplg`)       |

The issue is in the audio stack, not in the laptop brand. It was found and tested on an
**MSI Vector 16 HX AI (A2XWHG / MS-15M3)**. Other laptops with the same audio chip are likely
affected as well.

```bash
unzip sof-hda-speaker-fix-1.1.0.zip && cd sof-hda-speaker-fix-1.1.0
sudo ./install.sh
```

> This is **not** a port of a Windows driver and contains no Windows code. The Linux kernel
> driver (SOF) already supports this hardware. On Ubuntu 22.04 four things around it are
> missing or wrong, and this package fixes all four.

---

## What it fixes

| # | Problem on a fresh Ubuntu 22.04 install | Symptom | Fix |
|---|---|---|---|
| 1 | **DSP firmware missing.** Ubuntu's `firmware-sof-signed 2.0` has no Arrow Lake-S/HX firmware (`intel/sof-ipc4/arl-s/sof-arl-s.ri`). | No sound card, "Dummy Output", no microphone | Installs the bundled Intel-signed SOF 2.14.1 firmware, plus the generic HDA topologies if they are missing |
| 2 | **Speaker path at −90 dB.** The DSP gains `Pre/Post Mixer Analog Playback Volume` start at 0 (−90 dB), and Ubuntu's `alsa-ucm-conf 1.2.6` never raises them. | Card, volume and stream look fine, but the speakers are silent | Sets them to 0 dB at boot, at card detection and after resume |
| 3 | **SOF disabled by a leftover option.** A common forum workaround is `options snd_intel_dspcfg dsp_driver=1`, which forces the legacy HDA driver. | Speakers may work, the internal microphone never does | Detects the line and comments it out (a backup is kept) |
| 4 | **Kernel too old.** Arrow Lake-S/HX SOF support needs a recent Ubuntu 6.8 HWE kernel. | Same as #1 | Checks the kernel and offers to install/update `linux-generic-hwe-22.04` |

After the fix, all of these work: internal speakers, headphone jack, headset microphone,
internal digital microphone (DMIC) and HDMI/DisplayPort audio.

## Tested on

| Component        | Value                                                          |
|------------------|----------------------------------------------------------------|
| Audio controller | Intel Arrow Lake-S/HX PCH audio DSP `8086:7f50` (subsystem `1462:145c`) |
| Codec            | Realtek ALC274, subsystem `1462:1474`                          |
| Driver           | `sof-audio-pci-intel-mtl`, SOF firmware 2.14.1.1 (`sof-arl-s.ri`) |
| Topology         | `intel/sof-ace-tplg/sof-hda-generic-2ch.tplg`                  |
| alsa-ucm-conf    | 1.2.6.3-1ubuntu1.12                                            |
| OS               | Ubuntu 22.04.5 LTS, kernel `6.8.0-138-generic` (HWE), PulseAudio 15.99 |
| Laptop           | MSI Vector 16 HX AI A2XWHG (MS-15M3), BIOS E15M3IMS.10E        |

Reports from other models are very welcome. Please open an issue with the output of
`./install.sh --check`.

## Installation

Download `sof-hda-speaker-fix-<version>.zip` from the [Releases](../../releases) page, then:

```bash
unzip sof-hda-speaker-fix-1.1.0.zip
cd sof-hda-speaker-fix-1.1.0
sudo ./install.sh
```

If the installer prints **REBOOT REQUIRED**, reboot. Everything else is applied automatically
at the next boot. To verify afterwards:

```bash
./install.sh --check                 # report only, changes nothing
speaker-test -c 2 -t wav -l 1        # unplug headphones first
```

Options:

| Option    | Effect |
|-----------|--------|
| `--check` | Report only; changes nothing; root is not required |
| `--yes`   | Do not ask questions; accept the kernel update and the override fix |
| `--force` | Install even if no supported audio hardware is detected |

Internet access is only needed if the kernel must be updated or `alsa-utils` is missing.
The firmware is bundled in the package.

## What the installer does

1. **Hardware**: looks for the Arrow Lake-S/HX audio controller (`8086:7f50`) or any active
   SOF driver. If it finds neither, it stops and changes nothing.
2. **Packages**: makes sure `alsa-utils` and `alsa-ucm-conf` are present.
3. **Firmware**: verifies the bundled files against `firmware/SHA256SUMS`, then copies each
   file **only if it is missing**. Newer files that your distribution provides are never
   overwritten.
4. **Driver overrides**: finds `dsp_driver=1` lines in `/etc/modprobe.d/` and offers to
   disable them.
5. **Kernel**: checks that the running kernel knows this DSP. If it does not, the installer
   either points to an installed kernel that does, or offers the Ubuntu HWE kernel update.
6. **Gain fix**: installs `sof-gain-fix` and applies the 0 dB gains:

| Path                                            | Purpose                                              |
|-------------------------------------------------|------------------------------------------------------|
| `/usr/local/sbin/sof-gain-fix`                  | the tool itself (Bash, ~120 lines, readable)         |
| `/etc/udev/rules.d/99-sof-gain-fix.rules`       | re-applies the gains whenever a sound card appears   |
| `/etc/systemd/system/sof-gain-fix.service`      | applies the gains once more after boot (safety net)  |
| `/usr/lib/systemd/system-sleep/sof-gain-fix`    | re-applies the gains after suspend/resume            |
| `/etc/default/sof-gain-fix`                     | optional configuration (all lines commented out)     |
| `/lib/firmware/intel/...`                       | bundled firmware, only the files that were missing   |

The gain tool also runs `alsactl store`. ALSA's own state restore therefore keeps the correct
values, and the udev rule overrides a stale saved state that would mute the speakers.

## Bundled firmware

| File | Source |
|------|--------|
| `firmware/intel/sof-ipc4/arl-s/sof-arl-s.ri` | [thesofproject/sof-bin](https://github.com/thesofproject/sof-bin) v2.14.1, Intel-signed |
| `firmware/intel/sof-ace-tplg/sof-hda-generic*.tplg` | Ubuntu 22.04 `firmware-sof-signed` 2.0-1ubuntu4.7 |

The files are unmodified and are redistributed under the SOF firmware release licence
([firmware/LICENCE.Intel](firmware/LICENCE.Intel)). Details and checksums are in
[firmware/SOURCES.md](firmware/SOURCES.md).

## The gain tool

```text
sof-gain-fix status            show SOF cards, codecs and the gain controls (read-only)
sof-gain-fix apply             set the gain controls to 0 dB
sof-gain-fix apply --dry-run   show what would change, change nothing
```

Example output on an affected machine before the fix:

```text
card 1 (sofhdadsp):
  would set 'Pre Mixer Analog Playback Volume' 0 -> 45 (-90.0 dB -> 0.0 dB)
  would set 'Post Mixer Analog Playback Volume' 0 -> 45 (-90.0 dB -> 0.0 dB)
  ok       'Pre Mixer Deepbuffer HDA Analog Volume' = 45 (0.0 dB)
```

`/etc/default/sof-gain-fix` takes two settings:

- `CONTROLS="name1;name2;..."` replaces the list of controls. Use it if your topology names
  the gain stages differently.
- `TARGET_DB=0` sets the target gain in dB. The tool never goes above 0 dB.

### Quick test without installing

```bash
CARD=$(grep -m1 -i sof /proc/asound/cards | awk '{print $1}')
amixer -c "$CARD" cset name='Pre Mixer Analog Playback Volume'  45,45
amixer -c "$CARD" cset name='Post Mixer Analog Playback Volume' 45,45
```

## Uninstall

```bash
sudo ./uninstall.sh           # removes the gain tool, udev rule, service and sleep hook
sudo ./uninstall.sh --purge   # also removes the firmware files this package added
```

`--purge` only removes files that this package installed; it records them in
`/var/lib/sof-hda-speaker-fix/`. Without that firmware the sound card disappears again, so
use `--purge` only once your distribution ships the firmware.

## Troubleshooting

- **Still "Dummy Output" after the reboot.** Run `./install.sh --check` and
  `journalctl -k -b | grep -i sof`. Look for `Booted firmware version`. A
  `firmware file ... not found` line means the firmware is missing. A kernel that does not
  know `8086:7f50` shows no SOF lines at all.
- **The gains show 0 dB but there is still no sound.** Unplug the headphones. Unmute `Master`
  and `Speaker` in `alsamixer -c <card>`. Select "Speaker" as the output in Settings → Sound.
- **The internal microphone is quiet.** Raise "Input volume" in Settings → Sound. The internal
  mic's hardware control is `Dmic0 Capture Volume`, and PulseAudio/PipeWire drive it.
- **The gains go back to 0 after a reboot.** Run `journalctl -b -u sof-gain-fix` and
  `sof-gain-fix status`, and open an issue with the output.

## A note on speaker protection

On Windows, the Realtek driver applies its own speaker processing (EQ and protection tuned
for this chassis). Linux plays audio without that processing. Normal listening is fine, but
avoid long periods at maximum volume, especially with bass-heavy content.

## How the cause was found

The aim was to find out what Windows does that Linux does not. We traced the Windows audio
stack (Realtek driver registry settings, ETW traces of the ACPI and power sequence during
playback) and compared it with the codec, pin, GPIO and power state on Linux. The kernel side
turned out to be correct: the codec was powered, the pins were configured and the stream
reached the DAC. The missing pieces were the DSP firmware, which Ubuntu 22.04 does not ship
for this chip, and the DSP gains that newer UCM profiles set. No Windows driver code is used
or redistributed.

The proper long-term fixes belong in the distribution (`firmware-sof-signed`,
`alsa-ucm-conf`). Until then, this package works around them.

## License

Scripts: [MIT](LICENSE). Bundled firmware: SOF firmware release licence
([firmware/LICENCE.Intel](firmware/LICENCE.Intel)). This project is not affiliated with MSI,
Intel or Realtek. Use it at your own risk.
