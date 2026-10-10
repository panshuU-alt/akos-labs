#!/bin/bash
if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3"]; then
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

#размер директории в человекочитаемом и байтовом формате
echo "Directory size: $human_size"

#размер диска в человекочитаемом формате
echo "Disk size: $(df -h "$log_direction" | tail -1 | awk '{print $2}')"

echo "Usage: $usage%"

if [ "$usage" -ge "$limit" ]; then
    echo "limit exceeded ($usage% >= $limit%)"
else

    echo "limit not exceeded ($usage% < $limit%)"
fi

exit 0
