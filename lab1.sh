#!/bin/bash
if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
    echo "no arguments"
    echo "usage: $0 <log_dir> <limit_percent> <files_count> [backup_dir]"
    exit 1
fi

log_direction="$1"

limit="$2"

m_files="$3"
backup_dir="${4:-/backup}"

if [ ! -d "$log_direction" ]; then
    echo "directory not found"
    exit 1
fi

if ! [[ "$limit" =~ ^[0-9]+$ ]]; then
    echo "limit must be an integer!"
    exit 1
fi

if [ "$limit"  -gt 100 ]; then
   echo "limit must be from 0 to 100"
   exit 1
fi

if ! [[ "$m_files" =~ ^[0-9]+$ ]] || [ "$m_files" -lt 1 ]; then
    echo "files count must be integer >=1"
    exit 1
fi

echo "Directory: $log_direction"
echo "Limit: $limit%"

usage=$(df --output=pcent "$log_direction" | tail -1 | tr -dc '0-9')

if [ -z "$usage" ]; then
   echo "cannot determine disk usage"
   exit 1
fi

human_size=$(du -sh "$log_direction" | cut -f1)


echo "Directory size: $human_size"

echo "Disk size: $(df -h "$log_direction" | tail -1 | awk '{print $2}')"

echo "Usage: $usage%"

if [ "$usage" -ge "$limit" ]; then
    echo "limit exceeded ($usage% >= $limit%)"
else

    echo "limit not exceeded ($usage% < $limit%)"
    echo "Archiving not required."
    exit 0
fi


mkdir -p "$backup_dir" || { echo "cannot create backup directory"; exit 1; }

list=$(mktemp)
trap 'rm -f "$list"' EXIT       # при любом выходе из скрипта — удалить временный файл

LC_ALL=C find "$log_direction" -maxdepth 1 -type f ! -name '*.gz' ! -name '*.tar' -printf '%T@ %P\0' \
    | LC_ALL=C sort -z -n \
    | head -z -n "$m_files" \
    | cut -z -d' ' -f2- > "$list"

if [ ! -s "$list" ]; then
    echo "No suitable files to archive."
    exit 0
fi
