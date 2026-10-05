if [ -z "$1" ] || [ -z "$2" ]; then
    echo "no arguments"
    exit 1
fi

log_direction="$1"

limit="$2"

if [ ! -d "$log_direction" ]; then
    echo "directory not found"
    exit 1
fi

if ! [[ "$limit" =~ ^[0-9]+$ ]]; then
    echo "limit must be an integer!"
    exit 1
fi

echo "Directory: $log_direction"
echo "Limit: $limit%"

direction_size=$(du -sb "$log_direction" | cut -f1)

disk_size=$(df -B1 "$log_direction" | tail -1 | awk '{print $2}')

percentage=$(awk "BEGIN {printf \"%.2f\", ($direction_size / $disk_size) * 100}")

int_percentage=$((direction_size * 100 / disk_size))

human_size=$(du -sh "$log_direction" | cut -f1)

#размер директории в человекочитаемом и байтовом формате
echo "Directory size: $human_size ($direction_size bytes)"

#размер диска в человекочитаемом формате
echo "Disk size: $(df -h "$log_direction" | tail -1 | awk '{print $2}')"

echo "Usage: $percentage%"

if [ "$int_percentage" -ge "$limit" ]; then
    echo "limit exceeded ($percentage% >= $limit%)"
else

    echo "limit not exceeded ($percentage% < $limit%)"
fi

exit 0
