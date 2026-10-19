#!/bin/bash

export LC_ALL=C

if [ $# -lt 3 ]; then
    echo "no arguments"
    echo "usage: $0 <log_dir> <limit_percent> <files_count> [backup_dir]"
    exit 1
fi

dir="$1"
limit="$2"
m="$3"
backup="${4:-/backup}"

if [ ! -d "$dir" ]; then
    echo "directory not found"
    exit 1
fi

dir=$(realpath "$dir")

if [ "$dir" = "/" ] || [ "$dir" = "/etc" ] || [ "$dir" = "/bin" ] || [ "$dir" = "/boot" ] || [ "$dir" = "/usr" ]; then
    echo "refusing to work with system directory: $dir"
    exit 1
fi

if ! [[ "$limit" =~ ^[0-9]+$ ]]; then
    echo "limit must be an integer!"
    exit 1
fi

if [ "$limit" -gt 100 ]; then
    echo "limit must be from 0 to 100"
    exit 1
fi

if ! [[ "$m" =~ ^[0-9]+$ ]] || [ "$m" -lt 1 ]; then
    echo "files count must be integer >=1"
    exit 1
fi

logger -t lab1 "run by ${SUDO_USER:-$USER}: dir=$dir limit=$limit files=$m"

usage=$(df -P "$dir" | tail -1 | awk '{print $5}' | tr -d '%')

echo "directory: $dir"
echo "limit: $limit%"
echo "directory size: $(du -sh "$dir" | cut -f1)"
echo "disk size: $(df -Ph "$dir" | tail -1 | awk '{print $2}')"
echo "usage: $usage%"

if [ "$usage" -lt "$limit" ]; then
    echo "limit not exceeded ($usage% < $limit%)"
    exit 0
fi

echo "limit exceeded ($usage% >= $limit%)"

if ! mkdir -p "$backup"; then
    echo "cannot create backup directory"
    exit 1
fi

files=$(ls -tr "$dir" | while read -r name; do
    if [ -f "$dir/$name" ] && [[ "$name" != *.gz ]] && [[ "$name" != *.tar ]]; then
        echo "$name"
    fi
done | head -n "$m")

if [ -z "$files" ]; then
    echo "no suitable files to archive."
    exit 0
fi

archive="$backup/log_backup_$(date +%Y%m%d_%H%M%S)_$$.tar.gz"

if echo "$files" | tar -czf "$archive" -C "$dir" -T -; then
    echo "$files" | while read -r f; do
        rm -f "$dir/$f"
    done
    count=$(echo "$files" | wc -l)
    echo "Archived $count file(s) to $archive"
    echo "Usage after archiving: $(df -P "$dir" | tail -1 | awk '{print $5}')"
else
    echo "tar failed"
    rm -f "$archive"
    exit 2
fi

exit 0
