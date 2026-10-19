#!/bin/bash

SCRIPT="$(dirname "$(readlink -f "$0")")/lab1.sh"

if [ "$EUID" -ne 0 ]; then
    echo "run through sudo: sudo $0"
    exit 1
fi

if [ ! -f "$SCRIPT" ]; then
    echo "not found $SCRIPT (should be located next to the tests)"
    exit 1
fi

WORK=$(mktemp -d)
IMG="$WORK/disk.img"
MNT="$WORK/log"
BACKUP="$WORK/backup"
mkdir -p "$MNT" "$BACKUP"

truncate -s 1G "$IMG"
mkfs.ext4 -q -F "$IMG"
mount -o loop "$IMG" "$MNT"

cleanup() {
    umount "$MNT" 2>/dev/null
    rm -rf "$WORK"
}

trap cleanup EXIT

PASS=0
FAIL=0

assert() {
    local desc="$1"; shift
    if "$@"; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"; FAIL=$((FAIL + 1))
    fi
}

run() {
    OUT=$(bash "$SCRIPT" "$@" 2>&1)
    CODE=$?
}

reset() {
    find "$MNT" -mindepth 1 -not -path "$MNT/lost+found*" -delete
    rm -rf "${BACKUP:?}"/*
}

mkfile() {
    dd if=/dev/zero of="$MNT/$1" bs=1M count="$2" status=none
    touch -d "$3 days ago" "$MNT/$1"
}

count_archives() { find "$BACKUP" -name '*.tar.gz' | wc -l; }
first_archive()  { find "$BACKUP" -name '*.tar.gz' | head -1; }

echo "checking arguements"

run
assert "without arguements: code 1" [ "$CODE" -eq 1 ]
assert "without arguements: 'no arguments'"  grep -q "no arguments" <<< "$OUT"

run "$MNT"
assert "only path: code 1" [ "$CODE" -eq 1 ]

run "$MNT" 50
assert "no M: code 1" [ "$CODE" -eq 1 ]

run /no/such/dir 50 2 "$BACKUP"
assert "bad dir: code 1" [ "$CODE" -eq 1 ]
assert "bad dir: 'directory not found'"  grep -q "directory not found" <<< "$OUT"

run "$MNT" abc 2 "$BACKUP"
assert "limit 'abc': code 1" [ "$CODE" -eq 1 ]

run "$MNT" -5 2 "$BACKUP"
assert "limit -5: code 1" [ "$CODE" -eq 1 ]

run "$MNT" 1.5 2 "$BACKUP"
assert "limit 1.5: code 1" [ "$CODE" -eq 1 ]

run "$MNT" 101 2 "$BACKUP"
assert "limit 101: code 1" [ "$CODE" -eq 1 ]

run "$MNT" 50 abc "$BACKUP"
assert "M='abc': code 1" [ "$CODE" -eq 1 ]

run "$MNT" 50 0 "$BACKUP"
assert "M=0: code 1" [ "$CODE" -eq 1 ]

echo "limit not exceeded"

reset

mkfile a.log 1 1
run "$MNT" 90 2 "$BACKUP"
assert "code 0" [ "$CODE" -eq 0 ]
assert "'limit not exceeded'" grep -qi "limit not exceeded" <<< "$OUT"
assert "printed percentage 'usage:'" grep -qi "usage:" <<< "$OUT"
assert "no archive" [ "$(count_archives)" -eq 0 ]
assert "file still there" [ -e "$MNT/a.log" ]

echo "limit exceeded (oldest M files is archiving)"

reset

mkfile old1.log 200 5
mkfile old2.log 200 4
mkfile new1.log 200 1

run "$MNT" 30 2 "$BACKUP"
ARC=$(first_archive)

assert "code 0" [ "$CODE" -eq 0 ]
assert "'limit exceeded'" grep -qi "limit exceeded" <<< "$OUT"
assert "created exactly 1 archive" [ "$(count_archives)" -eq 1 ]
assert "old1.log in archive" bash -c "tar -tzf '$ARC' | grep -qx old1.log"
assert "old2.log in archive" bash -c "tar -tzf '$ARC' | grep -qx old2.log"
assert "new1.log not in archive" bash -c "! tar -tzf '$ARC' | grep -qx new1.log"
assert "old1.log removed" [ ! -e "$MNT/old1.log" ]
assert "old2.log removed" [ ! -e "$MNT/old2.log" ]
assert "new1.log is still there" [ -e "$MNT/new1.log" ]

echo "content in archive is not broken"

reset

echo "secret-text-123" > "$MNT/data.log"
touch -d "3 days ago" "$MNT/data.log"

dd if=/dev/zero of="$MNT/pad.log" bs=1M count=400 status=none
touch -d "1 day ago" "$MNT/pad.log"

run "$MNT" 10 1 "$BACKUP"
ARC=$(first_archive)

assert "code 0" [ "$CODE" -eq 0 ]
assert "text inside archive matches" bash -c "tar -xzOf '$ARC' data.log | grep -qx secret-text-123"

echo "M bigger than files count"

reset

mkfile a.log 400 2
mkfile b.log 1 1

run "$MNT" 10 10 "$BACKUP"

assert "code 0" [ "$CODE" -eq 0 ]
assert "a.log archived and removed" [ ! -e "$MNT/a.log" ]
assert "b.log archived and removed" [ ! -e "$MNT/b.log" ]
assert "архив создан" [ "$(count_archives)" -eq 1 ]

echo "filter (.gz and subdirs skip)"

reset

dd if=/dev/zero of="$MNT/old.gz" bs=1M count=1 status=none
touch -d "10 days ago" "$MNT/old.gz"

mkdir "$MNT/sub"; echo x > "$MNT/sub/inner.log"
touch -d "9 days ago" "$MNT/sub/inner.log"

mkfile big.log 400 3

run "$MNT" 10 1 "$BACKUP"
ARC=$(first_archive)

assert "code 0" [ "$CODE" -eq 0 ]
assert "big.log archived" bash -c "tar -tzf '$ARC' | grep -qx big.log"
assert "old.gz not archived" bash -c "! tar -tzf '$ARC' | grep -q 'old.gz'"
assert "old.gz is still there" [ -e "$MNT/old.gz" ]
assert "sub/inner.log is still there" [ -e "$MNT/sub/inner.log" ]

echo "file's name with space"

reset

mkfile "my file.log" 400 3

run "$MNT" 10 1 "$BACKUP"
ARC=$(first_archive)

assert "code 0" [ "$CODE" -eq 0 ]
assert "file with space in archive" bash -c "tar -tzf '$ARC' | grep -qx 'my file.log'"
assert "file with space removed" [ ! -e "$MNT/my file.log" ]

echo "linit 0 and not empty dir"

reset

mkfile a.log 1 1

run "$MNT" 0 1 "$BACKUP"

assert "limit 0: exceeded" grep -qi "limit exceeded" <<< "$OUT"
assert "limit 0: file archived" [ ! -e "$MNT/a.log" ]

echo "empty dir and limit exceeded (no to archive)"

reset

run "$MNT" 0 1 "$BACKUP"

assert "code 0" [ "$CODE" -eq 0 ]
assert "'no suitable files'" grep -qi "no suitable files" <<< "$OUT"
assert "archive is not created" [ "$(count_archives)" -eq 0 ]

echo "backup dir created if not earlier"

reset

mkfile a.log 400 2
NEWB="$WORK/new_backup_dir"

run "$MNT" 10 1 "$NEWB"

assert "code 0" [ "$CODE" -eq 0 ]
assert "backup dir created" [ -d "$NEWB" ]
assert "archive inside backup" bash -c "ls '$NEWB'/*.tar.gz >/dev/null 2>&1"

echo "two runs(archives not overrite each other)"

reset

mkfile a.log 200 5
mkfile b.log 200 4
mkfile c.log 200 3

run "$MNT" 10 1 "$BACKUP"
run "$MNT" 10 1 "$BACKUP"

assert "created two diff archives" [ "$(count_archives)" -eq 2 ]
assert "c.log is still there" [ -e "$MNT/c.log" ]
assert "a.log removed" [ ! -e "$MNT/a.log" ]
assert "b.log removed" [ ! -e "$MNT/b.log" ]

echo "IN TOTAL: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]

