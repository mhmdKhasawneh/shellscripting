#!/bin/bash

# Function to display help information
display_help() {
  echo "Usage: ./script.sh [directory_path] [extensions] [options]"
  echo "This script searches the provided directory and its subdirectories for files with specific extensions."
  echo "Options:"
  echo "  -p <permissions>          Filter files by permissions (octal format)"
  echo "  -d <date>                 Filter files by last modified date (YYYY-MM-DD)"
  echo "  -s <size>                 Filter files by size greater than or equal the size provided (in bytes)"
  echo 'Example usage: ./script.sh ~/Documents "mp4 pdf" -s 3000000 -d "2023-01-01" -p 432'
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
extensions="$2"
filter_permissions=""
filter_date_modified=""
filter_size=""
total_files_size=0
total_owners=0
total_files_count=0
report="file_analysis.txt"
summary="summary.txt"
declare -A file_groups


while [ $# -gt 2 ]; do
    case "$3" in
      -p)
        if [ -z "$4" ]; then
          echo "Error: Missing value for the permissions filter."
          display_help
          exit 1
        fi
        
        if ! [[ $4 =~ ^[0-7]{3}$ ]]; then
          echo "Error: Invalid permissions format. Permissions must be in octal format."
          display_help
          exit 1
        fi
        
        filter_permissions="$4"
        shift 2
        ;;
      -d)
        if [ -z "$4" ]; then
          echo "Error: Missing value for the date filter."
          display_help
          exit 1
        fi
          
        if ! [[ $4 =~ ^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|1[0-9]|2[0-9]|30)$ ]]; then
           echo "Error: Invalid date format or invalid day: $4. Expected format: yyyy-mm-dd"
           display_help
           exit 1
        fi
        
        current_date=$(date +%Y-%m-%d)
        if [[ "$4" > "$current_date" ]]; then
          echo "Error: Future date provided."
          display_help
          exit 1
        fi
        
        filter_date_modified="$4"
        shift 2
        ;;
      -s)
        if [ -z "$4" ]; then
          echo "Error: Missing value for the size filter."
          display_help
          exit 1
        fi
        
        if ! [[ $4 =~ ^[0-9]+$ ]]; then
          echo "Error: Not a number or the number is below zero"
          display_help
          exit 1
        fi
        
        filter_size="$4"
        shift 2
        ;;
      *)
        echo "Error: Invalid option: $3"
        display_help
        exit 1
        ;;
    esac
  done

    # An optimization: used mapfile instead of while-read loop. This prevents subshell creation for each file, hence improving performance.
    # Additional feature: Allow simultanous search for more than one extension.
    query_string=""
    mapfile -t extensions < <(echo "$extensions" | tr ' ' '\n')

    for extension in "${extensions[@]}"; do
      extension="${extension#"."}"
      query_string+=" -name '*.$extension' -o"
    done
    
    query_string=${query_string% -o}
    
    mapfile -t files < <(eval "find '$directory' -type f $query_string")
 

for file in "${files[@]}"; do
    filename=$(basename "$file")
    # An optimization: used a single stat call instead of multiple calls.
    file_info=$(stat -c "$filename|%s|%U|%a|%y" "$file")
    
    IFS='|' read -r _ file_size owner file_permissions file_last_modified <<< "$file_info"
    
    # Additional feature: Filter files based on permissions, date modified, and size
    if [ -n "$filter_permissions" ]; then
      if [ "$file_permissions" != "$filter_permissions" ]; then
        continue
      fi
    fi

    if [ -n "$filter_date_modified" ]; then
      file_date=$(date -d "$file_last_modified" +%Y-%m-%d)
      if [ "$file_date" != "$filter_date_modified" ]; then
        continue
      fi
    fi

    if [ -n "$filter_size" ]; then
      if [ "$file_size" -lt "$filter_size" ]; then
        continue
      fi
    fi
     
    total_files_count=$((total_files_count + 1 ))
    
    if [ -z "${file_groups[$owner]}" ]; then
      file_groups[$owner]="$file_info"
    else
      file_groups[$owner]+=$'\n'"$file_info"
    fi
   
done
  
  for owner in "${!file_groups[@]}"; do
    total_size=0
    total_owners=$((total_owners + 1))
    while IFS="|" read -r _ size _ _ _; do
      total_size=$((total_size + size))
      total_files_size=$((total_files_size + size))
    # An optimization: here-string ( <<< ) creates a subshell, affecting performance. Used process substitution instead ( < <() ) 
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
  
   > "$summary"
   
  echo -e "Total size of matching files: $total_files_size bytes\nNumber of owners: $total_owners\nTotal number of matching files: $total_files_count" >> "$summary"
  echo -e "Report has been generated. Cat $report to access.\nSummary report has been generated. Cat $summary to access"
  echo >> "$summary"
  
