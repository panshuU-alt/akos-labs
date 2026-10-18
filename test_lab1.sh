#!/bin/bash

SCRIPT="$(dirname "$(readlink -f "$0")")/lab1.sh"

if [ "$EUID" -ne 0 ]; then
    echo "Запусти через sudo: sudo $0"
    exit 1
fi

if [ ! -f "$SCRIPT" ]; then
    echo "Не найден $SCRIPT (lab1.sh должен лежать рядом с тестами)"
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

echo "== 1. Проверка аргументов =="

run
assert "без аргументов: код 1" [ "$CODE" -eq 1 ]
assert "без аргументов: 'no arguments'"  grep -q "no arguments" <<< "$OUT"

run "$MNT"
assert "только путь: код 1" [ "$CODE" -eq 1 ]

run "$MNT" 50
assert "нет M: код 1" [ "$CODE" -eq 1 ]

run /no/such/dir 50 2 "$BACKUP"
assert "нет папки: код 1" [ "$CODE" -eq 1 ]
assert "нет папки: 'directory not found'"  grep -q "directory not found" <<< "$OUT"

run "$MNT" abc 2 "$BACKUP"
assert "порог 'abc': код 1" [ "$CODE" -eq 1 ]

run "$MNT" -5 2 "$BACKUP"
assert "порог -5: код 1" [ "$CODE" -eq 1 ]

run "$MNT" 1.5 2 "$BACKUP"
assert "порог 1.5: код 1" [ "$CODE" -eq 1 ]

run "$MNT" 101 2 "$BACKUP"
assert "порог 101: код 1" [ "$CODE" -eq 1 ]

run "$MNT" 50 abc "$BACKUP"
assert "M='abc': код 1" [ "$CODE" -eq 1 ]

run "$MNT" 50 0 "$BACKUP"
assert "M=0: код 1" [ "$CODE" -eq 1 ]

echo "== 2. Порог не превышен =="

reset

mkfile a.log 1 1
run "$MNT" 90 2 "$BACKUP"
assert "код 0" [ "$CODE" -eq 0 ]
assert "'limit not exceeded'" grep -qi "limit not exceeded" <<< "$OUT"
assert "выводится процент 'usage:'" grep -qi "usage:" <<< "$OUT"
assert "архив не создан" [ "$(count_archives)" -eq 0 ]
assert "файл на месте" [ -e "$MNT/a.log" ]

echo "== 3. Порог превышен: архивируются M самых старых =="

reset

mkfile old1.log 200 5
mkfile old2.log 200 4
mkfile new1.log 200 1

run "$MNT" 30 2 "$BACKUP"
ARC=$(first_archive)

assert "код 0" [ "$CODE" -eq 0 ]
assert "'limit exceeded'" grep -qi "limit exceeded" <<< "$OUT"
assert "создан ровно 1 архив" [ "$(count_archives)" -eq 1 ]
assert "в архиве old1.log" bash -c "tar -tzf '$ARC' | grep -qx old1.log"
assert "в архиве old2.log" bash -c "tar -tzf '$ARC' | grep -qx old2.log"
assert "в архиве НЕТ new1.log" bash -c "! tar -tzf '$ARC' | grep -qx new1.log"
assert "old1.log удалён из папки" [ ! -e "$MNT/old1.log" ]
assert "old2.log удалён из папки" [ ! -e "$MNT/old2.log" ]
assert "new1.log остался" [ -e "$MNT/new1.log" ]

echo "== 4. Содержимое файла в архиве не повреждено =="

reset

echo "secret-text-123" > "$MNT/data.log"
touch -d "3 days ago" "$MNT/data.log"

dd if=/dev/zero of="$MNT/pad.log" bs=1M count=400 status=none
touch -d "1 day ago" "$MNT/pad.log"

run "$MNT" 10 1 "$BACKUP"
ARC=$(first_archive)

assert "код 0" [ "$CODE" -eq 0 ]
assert "текст внутри архива совпадает" bash -c "tar -xzOf '$ARC' data.log | grep -qx secret-text-123"

echo "== 5. M больше, чем файлов =="

reset

mkfile a.log 400 2
mkfile b.log 1 1

run "$MNT" 10 10 "$BACKUP"

assert "код 0" [ "$CODE" -eq 0 ]
assert "a.log заархивирован и удалён" [ ! -e "$MNT/a.log" ]
assert "b.log заархивирован и удалён" [ ! -e "$MNT/b.log" ]
assert "архив создан" [ "$(count_archives)" -eq 1 ]

echo "== 6. Фильтрация: .gz и подпапки не трогаем =="

reset

dd if=/dev/zero of="$MNT/old.gz" bs=1M count=1 status=none
touch -d "10 days ago" "$MNT/old.gz"

mkdir "$MNT/sub"; echo x > "$MNT/sub/inner.log"
touch -d "9 days ago" "$MNT/sub/inner.log"

mkfile big.log 400 3

run "$MNT" 10 1 "$BACKUP"
ARC=$(first_archive)

assert "код 0" [ "$CODE" -eq 0 ]
assert "big.log заархивирован" bash -c "tar -tzf '$ARC' | grep -qx big.log"
assert "old.gz не заархивирован" bash -c "! tar -tzf '$ARC' | grep -q 'old.gz'"
assert "old.gz остался" [ -e "$MNT/old.gz" ]
assert "sub/inner.log остался" [ -e "$MNT/sub/inner.log" ]

echo "== 7. Имена файлов с пробелами =="

reset

mkfile "my file.log" 400 3

run "$MNT" 10 1 "$BACKUP"
ARC=$(first_archive)

assert "код 0" [ "$CODE" -eq 0 ]
assert "файл с пробелом в архиве" bash -c "tar -tzf '$ARC' | grep -qx 'my file.log'"
assert "файл с пробелом удалён" [ ! -e "$MNT/my file.log" ]

echo "== 8. Порог 0 и непустая папка =="

reset

mkfile a.log 1 1

run "$MNT" 0 1 "$BACKUP"

assert "порог 0: превышен" grep -qi "limit exceeded" <<< "$OUT"
assert "порог 0: файл заархивирован" [ ! -e "$MNT/a.log" ]

echo "== 9. Пустая папка при превышении (нечего архивировать) =="

reset

run "$MNT" 0 1 "$BACKUP"

assert "код 0" [ "$CODE" -eq 0 ]
assert "'no suitable files'" grep -qi "no suitable files" <<< "$OUT"
assert "архив не создан" [ "$(count_archives)" -eq 0 ]

echo "== 10. Папка бэкапа создаётся, если её нет =="

reset

mkfile a.log 400 2
NEWB="$WORK/new_backup_dir"

run "$MNT" 10 1 "$NEWB"

assert "код 0" [ "$CODE" -eq 0 ]
assert "папка бэкапа создана" [ -d "$NEWB" ]
assert "в ней лежит архив" bash -c "ls '$NEWB'/*.tar.gz >/dev/null 2>&1"

echo "== 11. Два запуска подряд: архивы не затирают друг друга =="

reset

mkfile a.log 200 5
mkfile b.log 200 4
mkfile c.log 200 3

run "$MNT" 10 1 "$BACKUP"
run "$MNT" 10 1 "$BACKUP"

assert "создано 2 разных архива" [ "$(count_archives)" -eq 2 ]
assert "c.log остался" [ -e "$MNT/c.log" ]
assert "a.log удалён" [ ! -e "$MNT/a.log" ]
assert "b.log удалён" [ ! -e "$MNT/b.log" ]

echo "Итого: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]

