# sof-hda-speaker-fix

**Silent internal speakers fix for Intel Arrow Lake-HX audio (`8086:7f50`, SOF DSP) with a
Realtek ALC274 codec on Ubuntu 22.04.**

| Audio hardware   | Model                                                                 |
|------------------|-----------------------------------------------------------------------|
| Audio controller | **Intel Arrow Lake-S/HX PCH audio DSP (Intel ACE)** · PCI ID `8086:7f50` |
| Linux driver     | **Sound Open Firmware (SOF)** · `sof-audio-pci-intel-mtl`, firmware `sof-arl-s.ri` (IPC4) |
| Codec            | **Realtek ALC274** (HD Audio) · codec subsystem `1462:1474`           |
| ALSA card        | `sof-hda-dsp` (generic HDA topology `sof-hda-generic-2ch.tplg`)       |

The issue is in the audio stack, not in the laptop brand. It was found and tested on an
**MSI Vector 16 HX AI (A2XWHG / MS-15M3)**. Other laptops with the same kind of hardware may
have the same issue: an Intel SOF audio DSP (Arrow Lake, Meteor Lake or Lunar Lake) using the
generic HDA topology with a Realtek HDA codec, on a distribution with an older `alsa-ucm-conf`.

With this hardware, the speakers are silent on Linux even though everything looks fine. The sound
card is detected, the volume is up and nothing is muted. Applications "play", and headphones may
work, but the speakers stay silent. Windows plays sound normally on the same machine.

The cause is two internal DSP gain stages that start at **−90 dB**. This package raises them to
0 dB and keeps them there across reboots and suspend/resume.

> This is **not** a driver and contains no vendor code. The kernel driver (SOF) already works. The
> fix is a single ALSA mixer setting that the userspace configuration on older distributions
> never applies.

---

## Symptoms

- `aplay -l` shows a `sof-hda-dsp` card with a Realtek ALC274 codec.
- PipeWire/PulseAudio shows "Speaker". The volume slider moves and nothing is muted.
- `speaker-test` runs without errors, but the speakers make no sound.
- The playback stream does reach the codec (`/proc/asound/card*/pcm0p/sub0/status` shows
  `hw_ptr` advancing).

## Root cause

Arrow Lake-HX laptops use Intel's SOF audio DSP with the generic HDA topology
(`intel/sof-ace-tplg/sof-hda-generic-2ch.tplg`). Audio passes through two DSP gain controls
before it reaches the codec:

| ALSA control                               | Default after boot | Needed         |
|--------------------------------------------|--------------------|----------------|
| `Pre Mixer Analog Playback Volume`         | **0 = −90 dB**     | 45 = 0 dB      |
| `Post Mixer Analog Playback Volume`        | **0 = −90 dB**     | 45 = 0 dB      |
| `Pre Mixer Deepbuffer HDA Analog Volume`   | 45 = 0 dB          | 45 = 0 dB      |

Newer `alsa-ucm-conf` profiles set these gains when the card is opened. Ubuntu 22.04 ships
`alsa-ucm-conf 1.2.6.x`, which never touches them, and PipeWire does not expose them as
volume sliders. So the speaker path sits at −90 dB, which is effectively silence.

`sof-gain-fix` sets these controls to 0 dB (unity gain, the topology's intended value). It
touches nothing else.

## Tested on

| Component        | Value                                                          |
|------------------|----------------------------------------------------------------|
| Audio controller | Intel Arrow Lake-S/HX PCH audio DSP `8086:7f50` (subsystem `1462:145c`) |
| Codec            | Realtek ALC274, subsystem `1462:1474`                          |
| Driver           | `sof-audio-pci-intel-mtl`, SOF firmware 2.14.1.1 (`sof-arl-s.ri`) |
| Topology         | `intel/sof-ace-tplg/sof-hda-generic-2ch.tplg`                  |
| alsa-ucm-conf    | 1.2.6.3-1ubuntu1.12                                            |
| OS               | Ubuntu 22.04.5 LTS, kernel `6.8.0-138-generic` (HWE)           |
| Laptop           | MSI Vector 16 HX AI A2XWHG (MS-15M3), BIOS E15M3IMS.10E        |

Reports from other models are very welcome. Please open an issue with the output of
`sof-gain-fix status`.

## Does this apply to me?

Run this check without installing anything (no root needed):

```bash
amixer -c "$(grep -m1 -i sof /proc/asound/cards | awk '{print $1}')" contents \
  | grep -A2 -E "(Pre|Post) Mixer .*Volume"
```

If you see `: values=0,0` for `Pre Mixer Analog Playback Volume` or
`Post Mixer Analog Playback Volume`, this fix applies to you. If those controls do not exist,
your problem is something else (see [Troubleshooting](#troubleshooting)).

## Requirements

- The SOF driver is in use: `lspci -k | grep -A3 -i audio` shows
  `Kernel driver in use: sof-audio-pci-intel-mtl` (or another `sof-audio-pci-*`).
  On Ubuntu 22.04 that needs the **HWE kernel (6.8)**: `sudo apt install linux-generic-hwe-22.04`.
- The SOF firmware is present. `linux-firmware` provides it. Check `dmesg | grep -i sof` for
  `Booted firmware version`.
- `alsa-utils` (for `amixer` / `alsactl`): `sudo apt install alsa-utils`.

## Installation

Download the latest `sof-hda-speaker-fix-<version>.zip` from the
[Releases](../../releases) page, then:

```bash
unzip sof-hda-speaker-fix-1.0.0.zip
cd sof-hda-speaker-fix-1.0.0
sudo ./install.sh
```

Or install from a clone:

```bash
git clone https://github.com/printbora/sof-hda-speaker-fix.git
cd sof-hda-speaker-fix
sudo ./install.sh
```

The installer checks first. If your machine has no SOF card with these controls, it stops and
changes nothing (`--force` overrides this). The fix takes effect immediately and no reboot is
needed. To test it, unplug your headphones and run:

```bash
speaker-test -c 2 -t wav -l 1
```

### Quick fix without installing

To try it once (it lasts until the next reboot unless you save it):

```bash
CARD=$(grep -m1 -i sof /proc/asound/cards | awk '{print $1}')
amixer -c "$CARD" cset name='Pre Mixer Analog Playback Volume'  45,45
amixer -c "$CARD" cset name='Post Mixer Analog Playback Volume' 45,45
sudo alsactl store   # optional: keep the values across reboots
```

## What gets installed

| Path                                            | Purpose                                              |
|-------------------------------------------------|------------------------------------------------------|
| `/usr/local/sbin/sof-gain-fix`                  | the tool itself (Bash, ~120 lines, readable)    |
| `/etc/udev/rules.d/99-sof-gain-fix.rules`       | re-applies the gains whenever a sound card appears   |
| `/etc/systemd/system/sof-gain-fix.service`      | applies the gains once more after boot (safety net)  |
| `/usr/lib/systemd/system-sleep/sof-gain-fix`    | re-applies the gains after suspend/resume            |
| `/etc/default/sof-gain-fix`                     | optional configuration (all lines commented out)     |

The installer also runs `alsactl store`, so ALSA's own state restore keeps the right values.

## Usage

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

### Configuration

`/etc/default/sof-gain-fix` takes two settings:

- `CONTROLS="name1;name2;..."` replaces the list of controls. Use it if your topology names
  the gain stages differently.
- `TARGET_DB=0` sets the target gain in dB. The tool never goes above 0 dB.

## Uninstall

```bash
sudo ./uninstall.sh
```

This removes every installed file. The gain values stay as they are. Setting them back to
−90 dB would only silence your speakers again.

## Troubleshooting

- **The controls do not exist / "no SOF sound card found".** The SOF driver is not active.
  Check `lspci -k` and `dmesg | grep -i sof`. On Ubuntu 22.04, install the HWE kernel. If SOF
  cannot load at all, a fallback is the legacy HDA driver
  (`echo "options snd_intel_dspcfg dsp_driver=1" | sudo tee /etc/modprobe.d/sof-off.conf`, then
  reboot). Speakers and headphones work with it, but the **internal microphone does not**,
  because it needs the DSP.
- **The gains show 0 dB but there is still no sound.** Unplug the headphones. Unmute `Master`
  and `Speaker` in `alsamixer -c <card>`. Remove a stale WirePlumber state
  (`rm -rf ~/.local/state/wireplumber`, then
  `systemctl --user restart wireplumber pipewire pipewire-pulse`).
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
reached the DAC. The missing piece was in userspace: the DSP gains that newer UCM profiles
set. No Windows driver code is used or redistributed.

The proper long-term fix belongs in `alsa-ucm-conf` (or a distribution backport). Until then,
this package works around it.

## License

[MIT](LICENSE). This project is not affiliated with MSI, Intel or Realtek. Use it at your
own risk.
