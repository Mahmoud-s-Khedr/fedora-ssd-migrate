# fedora-ssd-migrate

Scripts and step-by-step guides to:

1. **Test a new SSD**, including one in a USB enclosure: SMART health, read/write benchmarks,
   write-and-verify, and a full-surface read scan, without touching existing data.
2. **Move a Fedora (Btrfs) system onto a bigger SSD** with a byte-for-byte clone made
   **offline**, **verified byte-for-byte**, so the new disk boots with everything exactly as before.
   That includes apps, settings, keys, and browser sessions.
3. **Fix JMicron JMS583 USB-NVMe enclosures** that freeze under Linux's UAS driver.

Built and tested on Fedora 44 (kernel 7.2) moving from a 256 GB NVMe to a 512 GB ADATA LEGEND 710
through a JMS583 enclosure.

## Quick start

```bash
git clone https://github.com/Mahmoud-s-Khedr/fedora-ssd-migrate.git
cd fedora-ssd-migrate

# 1. Test the new SSD (read-only)
lsblk -dno NAME,SIZE,MODEL,SERIAL,TRAN
sudo ./scripts/ssd-test.sh read /dev/sdX <serial>

# 2. Clone: boot a Fedora Live USB, then
curl -LO https://raw.githubusercontent.com/Mahmoud-s-Khedr/fedora-ssd-migrate/main/scripts/clone-to-new-ssd
chmod +x clone-to-new-ssd
sudo ./clone-to-new-ssd --list
sudo ./clone-to-new-ssd --check --src-serial '<old disk serial>' --tgt-model '<new disk model>' --tgt-sectors <N> [--usb-quirk 152d:a583:u]
sudo ./clone-to-new-ssd         --src-serial '<old disk serial>' --tgt-model '<new disk model>' --tgt-sectors <N> [--usb-quirk 152d:a583:u]
```

**Read [docs/cloning-and-migrating.md](docs/cloning-and-migrating.md) before cloning.** The steps
before and after the copy matter.

## Contents

| Path | What it is |
|---|---|
| [`scripts/ssd-test.sh`](scripts/ssd-test.sh) | SSD test: `read` / `write` / `full` / `all` modes |
| [`scripts/clone-to-new-ssd`](scripts/clone-to-new-ssd) | Offline whole-disk clone with safety checks, `cmp` verification and GPT fix-up |
| [`clone.conf.example`](clone.conf.example) | Optional config file for `clone-to-new-ssd` |
| [`docs/testing-a-new-ssd.md`](docs/testing-a-new-ssd.md) | How to run the tests and read the results |
| [`docs/cloning-and-migrating.md`](docs/cloning-and-migrating.md) | Full migration guide (Live USB, with an emergency-mode fallback) |
| [`docs/jms583-uas-freezes.md`](docs/jms583-uas-freezes.md) | JMS583 freeze/reset problem and the `usb-storage` quirk fix |

## Safety design of `clone-to-new-ssd`

- Disks are matched by **serial / model / exact sector count**, never by `/dev/sdX` names, which change.
- It refuses to run if any partition of the source is mounted **read-write**, or the target is mounted at all.
- It refuses if the target is smaller than the source.
- `--check` runs every check and writes nothing. A real run requires typing `YES`.
- After `dd` it drops caches and `cmp`s the full source size against the target. It only reports success
  if they're identical.
- The source disk is only ever read.

## Requirements

`bash`, `dd`, `cmp`, `sfdisk`, `blockdev`, `findmnt`, `lsblk` (all present on Fedora and its Live
image). For the tests, also `smartmontools`, `hdparm`, `fio` and `e2fsprogs` (`badblocks`):

```bash
sudo dnf install smartmontools hdparm fio e2fsprogs
```

## Disclaimer

These scripts write raw disks. Read the docs, run `--check` first, and keep a backup.
Provided as-is, under the [MIT License](LICENSE).
