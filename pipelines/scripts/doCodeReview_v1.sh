#!/bin/bash

# Define the directory where you want to search for .zip files
directory=$1

# Define the path to the code_review_reports folder, two levels above the current folder
output_directory="$(dirname "$(dirname "$directory")")/code_review_reports"

# Check if the directory exists
if [ ! -d "$directory" ]; then
  echo "Directory $directory does not exist."
  exit 1
fi

# Create the 'code_review_reports' directory if it doesn't exist
mkdir -p "$output_directory"

# Loop over all .zip files in the directory and process them
for zip_file in "$directory"/*.zip; do
  if [ -f "$zip_file" ]; then
    # Create a folder for the zip file extraction inside 'code_review_reports'
    folder_name="$output_directory/$(basename "$zip_file" .zip)"
    
    # Extract the main .zip file into the folder
    echo "Extracting: $zip_file"
    mkdir -p "$folder_name" # Ensure the folder exists
    unzip -q "$zip_file" -d "$folder_name"

    # Now go into the extracted folder
    cd "$folder_name" || exit

    # Look for a .zip file starting with "pkg" in the extracted folder
    pkg_zip_file=$(find . -maxdepth 1 -type f -name "pkg*.zip")
    
    if [ -f "$pkg_zip_file" ]; then
      # Extract the found "pkg*.zip" file
      echo "Found pkg zip: $pkg_zip_file. Extracting..."
      unzip -q "$pkg_zip_file" -d "$folder_name/$(basename "$pkg_zip_file" .zip)"
    else
      echo "No pkg zip file found in $folder_name"
    fi

    # Clean up files that are not inside the "pkg" directory
    for item in "$folder_name"/*; do
      if [ -d "$item" ] && [[ "$(basename "$item")" != pkg* ]]; then
        # If it's a directory that doesn't start with "pkg", delete all files inside it
        echo "Deleting files inside: $item"
        rm -rf "$item"/*
      elif [ -f "$item" ]; then
        # If it's a file that is not inside a "pkg" directory, delete it
        echo "Deleting file: $item"
        rm -f "$item"
      fi
    done
    
    # Create the 'current_review_reports' subfolder inside the output directory
    current_review_reports="$output_directory/current_review_reports"
    mkdir -p "$current_review_reports"  # Create the 'current_review_reports' folder if it doesn't exist

    # Loop over each child folder 
    for child_folder in "$folder_name"/pkg*/; do
      if [ -d "$child_folder" ]; then
        # create the command with dynamic values
        last_folder_name=$(basename "$child_folder")
        flow_service_name=$(basename "$folder_name")
        mkdir -p $current_review_reports/$flow_service_name
        echo "Running the command for folder: $folder_name and pkg: $last_folder_name. Will put reports in folder : $current_review_reports"
        
        # Run the code review command with  parameters. This code review tool is part of the build server like jenkins. It will go in SCM later when optimized.
       command="/opt/GCS_IS_ContinuousCodeReview_v2024.05.01.0/CodeReview.sh -Dcode.review.directory=$folder_name -Dcode.review.pkgname=$last_folder_name -Dcode.review.pkgprefix=pkg_ -Dcode.review.folder-prefix=fld -Dcode.review.output.directory=$current_review_reports/$flow_service_name"
        echo "Executing command: $command"
        eval "$command"
      fi
    done

    # Return to the original directory
    cd "$directory" || exit
  fi
done
