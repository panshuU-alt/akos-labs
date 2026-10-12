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

if [ "$limit" -gt 100 ]; then
    echo "limit must be from 0 to 100"
    exit 1
fi

if ! [[ "$m_files" =~ ^[0-9]+$ ]] || [ "$m_files" -lt 1 ]; then
    echo "files count must be integer >=1"
    exit 1
fi

echo "directory: $log_direction"
echo "limit: $limit%"

usage=$(df "$log_direction" | tail -1 | awk '{print $5}' | tr -d '%')

if [ -z "$usage" ]; then
    echo "cannot determine disk usage"
    exit 1
fi

human_size=$(du -sh "$log_direction" | cut -f1)

echo "directory size: $human_size"
echo "disk size: $(df -h "$log_direction" | tail -1 | awk '{print $2}')"
echo "usage: $usage%"

if [ "$usage" -lt "$limit" ]; then
    echo "limit not exceeded ($usage% < $limit%)"
    exit 0
fi

echo "limit exceeded ($usage% >= $limit%)"
echo "starting archiving..."

if ! mkdir -p "$backup_dir"; then
    echo "cannot create backup directory"
    exit 1
fi

list=$(mktemp)

find "$log_direction" -type f -printf '%T@ %p\n' | sort -n | head -n "$m_files" | awk '{print $2}' > "$list"

if [ ! -s "$list" ]; then
    echo "no suitable files to archive."
    rm -f "$list"
    exit 0
fi

