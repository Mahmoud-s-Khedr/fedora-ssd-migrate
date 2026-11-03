#!/usr/bin/env bash
# ssd-test.sh — health + performance + surface test for a (new) SSD, e.g. in a USB enclosure.
#
# Usage: sudo ./ssd-test.sh <mode> <device> <expected-serial>
#   read   SMART + read benchmarks. Never writes.                         (~2 min)
#   write  read + 16 GiB write/verify ONLY in unallocated space
#          located after the last partition.                              (~5 min)
#   full   read + full-surface read scan (badblocks, read-only).          (~20-30 min on a healthy link)
#   all    read + write + full.
#
#   <expected-serial> must match `lsblk -dno SERIAL <device>` — protects against a wrong /dev/sdX.
#   Env: SMART_TYPE=sntjmicron (or sat, ...) to force a smartctl -d type; LOG_DIR=dir for the log.
set -uo pipefail
MODE=${1:-}; DEV=${2:-}; SERIAL=${3:-}
usage(){ awk 'NR>1 && !/^#/{exit} NR>1{sub(/^# ?/,"");print}' "$0"; exit 1; }
[[ $MODE =~ ^(read|write|full|all)$ && -n $DEV && -n $SERIAL ]] || usage

NAME=$(basename "$DEV")
LOG_DIR=${LOG_DIR:-.}
LOG="$LOG_DIR/ssd-test_${NAME}_$(date +%Y%m%d_%H%M%S).log"
START_TS=$(date '+%Y-%m-%d %H:%M:%S')

die(){ echo "ABORT: $*"; exit 1; }
hr(){ echo; echo "================ $* ================"; }
smart(){ if [[ -n ${SMART_TYPE:-} ]]; then smartctl -d "$SMART_TYPE" "$@" "$DEV"; else smartctl "$@" "$DEV"; fi; }
temp(){ smart -A 2>/dev/null | grep -iE '^Temperature:' | sed "s/^/[temp $1] /"; }

[[ $EUID -eq 0 ]] || die "run with sudo"
[[ -b $DEV ]] || die "$DEV is not a block device"
[[ "$(lsblk -dno SERIAL "$DEV")" == "$SERIAL" ]] || die "$DEV serial is '$(lsblk -dno SERIAL "$DEV")', expected '$SERIAL'"
lsblk -no MOUNTPOINTS "$DEV" | grep -q . && die "a partition on $DEV is mounted"
for t in smartctl hdparm fio badblocks; do command -v $t >/dev/null || die "missing $t (sudo dnf install smartmontools hdparm fio e2fsprogs)"; done

exec > >(tee "$LOG") 2>&1
echo "Mode: $MODE   Device: $DEV   Log: $LOG   Start: $START_TS"

hr "SMART (before)"
smart -x

hr "hdparm buffered direct read"
hdparm -t --direct "$DEV"; hdparm -t --direct "$DEV"

FIO="fio --filename=$DEV --direct=1 --ioengine=libaio --time_based --group_reporting"
SZ=$(( $(cat /sys/block/$NAME/size) * 512 / 2 ))   # random tests span the first half of the disk
hr "fio SEQ READ 1M QD8 (read-only)"
$FIO --readonly --name=seqread --rw=read --bs=1M --iodepth=8 --runtime=20 --size=$SZ
temp seqread
hr "fio RAND READ 4K QD32 (read-only)"
$FIO --readonly --name=randread32 --rw=randread --bs=4k --iodepth=32 --runtime=20 --size=$SZ
hr "fio RAND READ 4K QD1 (read-only)"
$FIO --readonly --name=randread1 --rw=randread --bs=4k --iodepth=1 --runtime=20 --size=$SZ
temp randread

if [[ $MODE == write || $MODE == all ]]; then
  SEC=512; GiB=$((1024*1024*1024))
  DISK_END=$(( $(cat /sys/block/$NAME/size) * SEC ))
  P_END=0
  for p in /sys/block/$NAME/$NAME*/start; do
    [[ -e $p ]] || continue; d=$(dirname "$p")
    e=$(( ($(cat "$p") + $(cat "$d/size")) * SEC )); (( e > P_END )) && P_END=$e
  done
  OFF=$(( ( (P_END + GiB - 1) / GiB + 2 ) * GiB ))   # >= 2 GiB past the last partition, GiB aligned
  LEN=$(( 16*GiB ))
  (( OFF + LEN < DISK_END - 4*GiB )) || die "not enough unallocated space after the last partition for a 16 GiB test"
  for p in /sys/block/$NAME/$NAME*/start; do
    [[ -e $p ]] || continue; d=$(dirname "$p"); s=$(( $(cat "$p")*SEC )); e=$(( s + $(cat "$d/size")*SEC ))
    (( e <= OFF || s >= OFF+LEN )) || die "write region overlaps $(basename "$d")"
  done
  echo "Write region: offset $((OFF/GiB)) GiB, length $((LEN/GiB)) GiB (unallocated space)"
  W="fio --filename=$DEV --direct=1 --ioengine=libaio --group_reporting --offset=$OFF --size=$LEN"

  hr "fio SEQ WRITE 1M QD8 16GiB + VERIFY (crc32c)"
  $W --name=seqwrite --rw=write --bs=1M --iodepth=8 --verify=crc32c --do_verify=1 --verify_fatal=1
  temp seqwrite
  hr "fio RAND WRITE 4K QD32 30s"
  $W --time_based --name=randwrite32 --rw=randwrite --bs=4k --iodepth=32 --runtime=30
  hr "fio RAND WRITE 4K QD1 20s"
  $W --time_based --name=randwrite1 --rw=randwrite --bs=4k --iodepth=1 --runtime=20
  temp randwrite
  hr "TRIM test region"
  blkdiscard -f -v --offset "$OFF" --length "$LEN" "$DEV" || echo "(discard not supported through this bridge - harmless)"
fi

if [[ $MODE == full || $MODE == all ]]; then
  hr "Full-surface READ scan (badblocks read-only)"
  time badblocks -b 4096 -c 8192 -sv "$DEV"
  temp fullscan
fi

hr "SMART (after)"
smart -A; smart -l error

hr "Kernel messages since start"
journalctl -k --since "$START_TS" --no-pager | grep -iE "$NAME|uas|reset|I/O error|critical|medium" || echo "none"
echo; echo "USB resets during test: $(journalctl -k --since "$START_TS" --no-pager | grep -c 'reset_handler start')"
echo "DONE. Log: $LOG"
