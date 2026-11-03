# Testing a new SSD with `ssd-test.sh`

`scripts/ssd-test.sh` checks a new SSD's health, speed and surface. It's designed for a drive in a
USB enclosure that already contains data you don't want to lose, for example a failed clone attempt:
read tests never write, and the write test only touches **unallocated space after the last partition**.

## 1. Find the device and its serial

```bash
lsblk -dno NAME,SIZE,MODEL,SERIAL,TRAN
```

Pass the `SERIAL` column exactly. The script refuses to run if `/dev/sdX` turns out to be a different disk.
Behind a USB bridge this is often the **bridge's** serial, not the SSD's.

## 2. Run

```bash
sudo ./scripts/ssd-test.sh read  /dev/sdX <serial>   # ~2 min, read-only
sudo ./scripts/ssd-test.sh write /dev/sdX <serial>   # + 16 GiB write/verify in free space, ~5 min
sudo ./scripts/ssd-test.sh full  /dev/sdX <serial>   # + read every sector (badblocks -sv, read-only)
sudo ./scripts/ssd-test.sh all   /dev/sdX <serial>   # everything
```

- **JMS583 enclosures:** add `SMART_TYPE=sntjmicron` if `smartctl` can't read SMART on its own,
  and apply the UAS fix first ([jms583-uas-freezes.md](jms583-uas-freezes.md)). Otherwise the
  results mostly measure USB resets.
- The log is written to the current directory (`LOG_DIR=...` to change it).
- Partitions on the device must not be mounted.
- The write test needs at least about 22 GiB of unallocated space after the last partition.
  It writes a pattern, reads it back with a crc32c check, and then TRIMs the region (if the bridge supports it).

## 3. Read the results

| Where | Good | Bad sign |
|---|---|---|
| SMART *overall-health* | `PASSED` | anything else |
| *Media and Data Integrity Errors*, *Error Information Log Entries* | `0` | > 0 |
| *Available Spare* / *Percentage Used* | 100 % / 0 % on a new drive | low spare, high wear on a "new" drive |
| *Power On Hours*, *Data Units Written* | a few hours, roughly what you wrote yourself | hundreds of hours: a used or returned drive |
| *Unsafe Shutdowns*, *Power Cycles* (before vs after) | unchanged during the test | increasing during the test = the USB link is resetting the drive |
| Temperature | well below the *Warning Comp. Temp.* threshold | near or above it under load |
| `hdparm` | the two runs are similar | one run much slower (a stall) |
| fio `clat ... max=` | milliseconds | about 32 000 ms (`32,xxx k` usec) = USB reset |
| fio seq write + verify | `err= 0` | verify errors |
| badblocks | `Pass completed, 0 bad blocks found. (0/0/0 errors)` | any errors |
| *Kernel messages* / *USB resets during test* | `none` / `0` | `uas_eh_abort_handler`, `reset ... using xhci_hcd`, `I/O error` |

Expected sequential speed through USB: about 350–450 MB/s on 5 Gbps, about 900–1000 MB/s on 10 Gbps.
The drive's NVMe speed is only reachable in an M.2 slot.

## Example: ADATA LEGEND 710 512 GB in a JMS583 enclosure

- SMART PASSED, 0 media errors, 0 log entries, 100 % spare, 0 % used, 39–54 °C.
- 16 GiB write + crc32c verify: OK. Full surface read: **0 bad blocks**.
- But **323 USB resets** in about 3 h with the default `uas` driver, and *Unsafe Shutdowns* went from 14 to 41.
  After the `152d:a583:u` quirk: 0 resets, steady 357 MiB/s.

Verdict: a healthy drive in a buggy enclosure. Fine to install internally. Use the quirk while it's in the enclosure.
