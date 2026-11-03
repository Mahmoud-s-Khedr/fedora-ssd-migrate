# Cloning Fedora onto a bigger SSD

Goal: move everything from the current internal SSD to a new, bigger one so that, after
swapping the drives, the laptop boots and **everything is exactly as it was**: apps,
settings, SSH keys, Wi-Fi, Docker/Postgres data, browser logins and open tabs.

The method is a **byte-for-byte copy** (`dd`) of the whole disk, done while the system
is **not running**, followed by a byte-for-byte **verification** (`cmp`). Because every
byte is copied, the new disk has the same partition table, filesystem UUIDs and
partition GUIDs. `fstab`, GRUB and the firmware's UEFI boot entry keep working with no changes.

Time: about 10 minutes of preparation, then about 12 minutes to copy and about 12 minutes to verify for a
256 GB source over a 5 Gbps USB link. After the swap, about 2 minutes to grow the partition.

---

## Why not copy from the running system?

A running system keeps writing to its disk. Btrfs commits every ~30 s, plus the journal,
browsers saving their session/cookie files every few seconds, Docker, Postgres, etc.
`dd` reads the disk front to back over ~12 minutes, so different parts of the copy would come
from different moments. A Btrfs copy like that may not mount, or may contain
corrupted files (often exactly the browser profile you wanted to keep).
That is the most common reason a "live" clone fails.

So the copy is made from a **Live USB** (main method) or from **emergency mode with
the root filesystem read-only** (fallback if you have no USB stick).

---

## What you need

- A USB stick of **4 GB or more** (it will be erased) with a Fedora Workstation Live image.
- The new SSD in its USB enclosure.
- Internet in the live session (to download the script). If you have none, see the box below.

**USB enclosure with a JMicron JMS583 chip (USB ID `152d:a583`)?** It freezes under load
with Linux's UAS driver. The script works around it with `--usb-quirk 152d:a583:u`.
See [jms583-uas-freezes.md](jms583-uas-freezes.md).

---

## Step 0 — Before you start (on your normal system)

1. **Turn on tab restore in your browsers**, so they reopen your tabs after any restart:
   - Firefox: Settings → General → *Open previous windows and tabs*
   - Chrome/Chromium: Settings → On startup → *Continue where you left off*
2. **Write down your disk details**. You can also read them again in the live session with `--list`:
   ```bash
   lsblk -dno NAME,SIZE,MODEL,SERIAL,TRAN
   cat /sys/block/nvme0n1/device/serial      # serial of the CURRENT internal NVMe
   cat /sys/block/sdX/size                   # sectors of the NEW disk in the enclosure
   ```
3. **Create the Live USB**:
   ```bash
   sudo dnf install mediawriter
   ```
   Open *Fedora Media Writer* → *Download automatically* → Fedora Workstation → write to the stick.

## Step 1 — Shut down cleanly

Close the browsers normally (so they save their session) and **shut down** the laptop.
Don't suspend it and don't hard power-off.

**Don't boot your normal Fedora again until the swap is done.** Anything you change there
after this point would not be on the new disk.

## Step 2 — Boot the Live USB

1. Plug in the Live USB stick **and** the SSD enclosure. If the laptop has a 10 Gbps port, use it for the enclosure.
2. Power on and open the boot menu. On HP laptops press **F9**; on others, usually F12, F11 or Esc.
3. Choose the USB stick, then **Start Fedora / Try Fedora** (not *Install*).
4. If GNOME offers to mount any disk, **don't**. Close those notifications.

## Step 3 — Get the script and find your disks

Open **Terminal** in the live session and connect to Wi-Fi if needed:

```bash
curl -LO https://raw.githubusercontent.com/Mahmoud-s-Khedr/fedora-ssd-migrate/main/scripts/clone-to-new-ssd
chmod +x clone-to-new-ssd
sudo ./clone-to-new-ssd --list
```

Example output:

```
DEVICE     MODEL                      SERIAL                      SECTORS      GiB  DRIVER
nvme0n1    NV33525GBY3G1-S            XXXXXXXXXXXXXXX           500118192      238  -
sda        Flash Drive                ...                        60063744       28  usb-storage
sdb        GEND 710                   DD5641XXXXXXX            1000215216      476  uas
```

- **Source** = your current internal disk → use its **SERIAL**.
- **Target** = the new SSD → use its **MODEL** and **SECTORS**.

> **No internet in the live session?** Before Step 1, copy `scripts/clone-to-new-ssd` onto a
> second USB stick or SD card (FAT/exFAT), plug it in during the live session, and run it from there
> with `sudo bash /run/media/liveuser/<stick>/clone-to-new-ssd ...`.

## Step 4 — Dry run, then copy

Dry run first. It only identifies the disks and runs the safety checks, and writes nothing:

```bash
sudo ./clone-to-new-ssd --check \
  --src-serial 'SOURCE_SERIAL' --tgt-model 'TARGET_MODEL' --tgt-sectors TARGET_SECTORS \
  --usb-quirk 152d:a583:u
```

Check the two lines it prints:

```
SOURCE (copy FROM): /dev/nvme0n1  <old SSD model>  serial ...  238 GiB
TARGET (copy TO):   /dev/sdb      <new SSD model>              476 GiB
```

Then run the same command **without `--check`** and type `YES` when asked.

If the enclosure is on the freezing `uas` driver, the script asks you to **unplug it, wait 5 s,
and plug it back in**. After that it uses the stable `usb-storage` driver.

It then:

1. copies the whole source disk to the target (`dd`, about 12 min at about 350 MB/s),
2. **compares every byte** of the two disks (`cmp`, about 12 min) and prints
   **`IDENTICAL - the copy is perfect.`**,
3. moves the GPT backup header to the end of the new disk, so the partition table spans all of it.

If it prints a red **ABORT**, **FAIL** or **VERIFY FAILED**: don't swap the drives. Your
current SSD is untouched. Fix the cause (usually the USB connection) and run it again.

## Step 5 — Swap the drives and grow the partition

1. `poweroff`, unplug everything, and disconnect the laptop's power.
2. Take out the old SSD and put the new one in the M.2 slot. **Keep the old SSD as a backup.**
3. Boot normally. GRUB, Fedora and your desktop should come up exactly as before.
   If the firmware says "no boot device", open the boot menu (F9) and pick *Fedora*.
4. Use the extra space. The main Btrfs partition is still the old size until you grow it:
   ```bash
   sudo dnf install cloud-utils-growpart        # if growpart is missing
   lsblk                                        # confirm the disk is nvme0n1 and the Btrfs partition is 3
   sudo growpart /dev/nvme0n1 3
   sudo btrfs filesystem resize max /
   df -h /
   ```
5. Optional: tell the new SSD which blocks are free, because `dd` wrote every block:
   ```bash
   sudo fstrim -av
   ```

## What changes and what doesn't

| Same as before | Different |
|---|---|
| All files, apps, settings, `/home`, `/etc` | Disk model and serial number (nothing in Fedora or your apps depends on them) |
| Browser cookies, logins, saved passwords, open tabs (with tab restore on) | More free space (after Step 5.4) |
| SSH/GPG keys, GNOME keyring, Wi-Fi passwords | Running programs aren't restored. It's the same as after a normal restart |
| Docker images/volumes, databases, project folders | |
| Filesystem UUIDs, partition GUIDs, GRUB, UEFI boot entry | |

## Rules for the two disks afterwards

- **Never connect the old and new disk to the same running system at the same time.**
  They have identical UUIDs, so Fedora might mount the wrong one, and Btrfs handles duplicate
  filesystem IDs badly.
- When you're sure the new disk is fine and want to reuse the old one, connect it to the
  running system in the enclosure, check its serial with `lsblk -o NAME,SERIAL,MODEL`, and erase it:
  `sudo wipefs -a /dev/sdX` (or repartition it in GNOME Disks).

---

## Fallback: emergency mode (no USB stick)

Fedora boots with the root filesystem read-only (`ro` on the kernel line) and only remounts it
read-write later. Emergency mode stops before that, so the disk can't change during the copy.

1. On the normal system, install the script **onto the root filesystem**. Don't use `/tmp`,
   which is cleared at reboot, or `/home`, which isn't mounted in emergency mode:
   ```bash
   sudo install -m 755 scripts/clone-to-new-ssd /usr/local/sbin/clone-to-new-ssd
   ```
   Optionally save the options in `/etc/clone-to-new-ssd.conf` (see `clone.conf.example`) so you don't have to type them later.
2. Close browsers, keep the enclosure plugged in, and reboot.
3. In GRUB (press Esc while booting if it's hidden), select your entry, press **`e`**, and add this to the
   end of the `linux` line, then press **Ctrl+X**:
   ```
   systemd.unit=emergency.target systemd.setenv=SYSTEMD_SULOGIN_FORCE=1 usb-storage.quirks=152d:a583:u
   ```
   (`SYSTEMD_SULOGIN_FORCE=1` gives a root shell even though Fedora's root account is locked.)
4. In the root shell: `findmnt -no OPTIONS /` must start with `ro`. Then run
   `clone-to-new-ssd` with the same options as in Step 4 (or none, if you saved a config).
5. When it reports `IDENTICAL`, run `poweroff` and continue with Step 5.

If emergency mode still refuses because the root account is locked, use
`init=/bin/bash usb-storage.quirks=152d:a583:u` instead. Run the script as
`/usr/local/sbin/clone-to-new-ssd`, and power off with `poweroff -f`.
