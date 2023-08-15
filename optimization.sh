#!/bin/bash

# Function to display help information
display_help() {
  echo "Usage: ./script.sh [directory_path] [extension]"
  echo "This script searches the provided directory and its subdirectories for files with a specific extension."
  echo "Example usage: ./script.sh ~/Documents txt"
}


if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
  display_help
  exit 0
fi

if [ -z "$1" ]; then
  echo "Error: Directory path argument is missing."
  display_help
  exit 1
fi

if [ ! -d "$1" ]; then
  echo "Error: Directory does not exist."
  exit 1
fi

if [ -z "$2" ]; then
  echo "Error: Extension argument is missing."
  display_help
  exit 1
fi

directory="$1"
extension="${2#*.}"
report="file_analysis.txt"
declare -A file_groups

  # An optimization: used mapfile instead of while-read loop. This prevents subshell creation for each file, hence improving performance.
  mapfile -t files < <(find "$directory" -type f -name "*.$extension")

  for file in "${files[@]}"; do
    filename=$(basename "$file")
    # An optimization: used a single stat call instead of multiple calls.
    file_info=$(stat -c "$filename|%s|%U|%a|%y" "$file")
    
    IFS='|' read -r _ _ owner _ _ <<< "$file_info"

    if [ -z "${file_groups[$owner]}" ]; then
      file_groups[$owner]="$file_info"
    else
      file_groups[$owner]+=$'\n'"$file_info"
    fi
  done
  
  for owner in "${!file_groups[@]}"; do
    total_size=0
    while IFS="|" read -r _ size _ _ _; do
      total_size=$((total_size + size))
    # An optimization: here-string ( <<< ) makes I/O disk operations. Process substituion does not.
    done < <(echo "${file_groups["$owner"]}")
    sorted_groups+=("$owner|$total_size")
  done

  # Again, process substitution here
  IFS=$'\n' sorted_groups=($(sort -t '|' -k2,2n < <(echo "${sorted_groups[*]}")))


  > "$report"
  
  for group in "${sorted_groups[@]}"; do
    IFS='|' read -r owner total_size <<< "$group"
    echo "Owner $owner has the following files with total size $total_size bytes" >> "$report"
    
    while IFS=$'\n' read -r file_info; do
      IFS="|" read -r filename size _ permissions last_modified <<< "$file_info"
      echo "Name: $filename, Size: $size bytes, Permissions: $permissions, Last Modified: $last_modified" >> "$report"
    # Process substitution here as well.
    done < <(echo "${file_groups["$owner"]}")
    
    echo >> "$report"
  done

  echo "Report has been generated. Cat $report to access."
