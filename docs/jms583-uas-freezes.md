# JMicron JMS583 USB-NVMe enclosures freeze on Linux (UAS)

## Symptoms

With an NVMe SSD in a **JMicron JMS583** enclosure (`lsusb`: `152d:a583 JMicron Technology Corp. JMS583`),
large or parallel I/O stalls for **about 30 seconds** at a time, after which the kernel resets the USB device:

```
sd 1:0:0:0: [sdb] tag#14 uas_eh_abort_handler 0 uas-tag 15 inflight: CMD IN
sd 1:0:0:0: [sdb] tag#14 CDB: Read(10) 28 00 2c 4a 38 00 00 04 00 00
...
scsi host1: uas_eh_host_reset_handler start
usb 4-2: reset SuperSpeed USB device number 2 using xhci_hcd
scsi host1: uas_eh_host_reset_handler success
```

Typical consequences:

- copies and `dd` crawl (repeated 30 s pauses), or fail outright,
- **disk clones made through the enclosure fail or come out corrupt**,
- benchmarks show maximum latencies of about 32 000 ms,
- the SSD's SMART *Power Cycles* and *Unsafe Shutdowns* go up during use, because each reset cuts power to the SSD.

The SSD itself is usually fine: SMART shows no media errors and no error-log entries.

## Cause

The bridge misbehaves with **UAS** (USB Attached SCSI) when several commands are queued
at once. Requests sent one at a time (queue depth 1) work fine, so light use looks normal and only
sustained or parallel I/O freezes.

## Fix: use the `usb-storage` (BOT) driver for this device

The `u` quirk tells the kernel to ignore UAS for this USB ID and use the older
Bulk-Only Transport driver. For a USB 5 Gbps link, sequential speed stays the same.

### Right now, until reboot

```bash
echo 152d:a583:u | sudo tee /sys/module/usb_storage/parameters/quirks
# then UNPLUG the enclosure, wait 5 s, plug it back in (the setting only applies on (re)connect)
lsusb -t | grep -i 'mass storage'     # must say Driver=usb-storage, not Driver=uas
```

### For one boot (Live USB, emergency mode)

Add to the kernel command line (press `e` in GRUB):

```
usb-storage.quirks=152d:a583:u
```

### Permanently

```bash
echo 'options usb-storage quirks=152d:a583:u' | sudo tee /etc/modprobe.d/jms583-no-uas.conf
sudo dracut -f        # only needed if usb-storage is in your initramfs; harmless otherwise
```

To combine with other quirks, separate entries with commas: `quirks=152d:a583:u,0bc2:2322:u`.

## Measured before/after (ADATA LEGEND 710 in a JMS583 enclosure, 5 Gbps port)

| | `uas` (default) | `usb-storage` + quirk |
|---|---|---|
| `hdparm -t --direct` | 351 MB/s, then 9 MB/s (33 s stall) | 354 / 353 MB/s |
| fio seq read 1M QD8 | 11 MB/s avg, max latency 32.5 s | **357 MiB/s**, max latency 34 ms |
| fio rand read 4K QD32 | 10.3k IOPS (with 32 s stalls) | 2.8k IOPS, max 72 ms |
| USB resets | **323 in ~3 h** (full read scan took 193 min) | **0** |
| SSD power cycles during test | +27 | 0 |

The lower 4K QD32 number doesn't matter for cloning or backups, which use large sequential I/O.

## Alternatives

- An enclosure with a different bridge (e.g. Realtek RTL9210/RTL9210B, ASMedia ASM2362/ASM2364).
- A 10 Gbps-rated cable/port. It's faster, but doesn't fix the UAS bug by itself.
