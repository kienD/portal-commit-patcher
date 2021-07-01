#!/bin/bash

source config

# This script takes a patch file at arg1 and updates the path with the portal_path_addition provided in the config file.

input_patch_file="${1}"

# Interate through lines in updated_lines and update the respective line in file
create_updated_patch() {
	local updated_lines="${1}"

	while read line; do
		IFS=':'

		read -a lineArray <<< "${line}"

		lineNumber=${lineArray[0]}
		lineContent=${lineArray[1]}

		current_line_string=$(sed "${lineNumber}q;d" "${input_patch_file}")

		if [[ "${current_line_string}" == *"${portal_path_addition}"* ]]; then
			echo "Skipping line ${lineNumber}: Already converted"
		else
			sed -i "${lineNumber}s%^.*$%${lineContent}%" "${input_patch_file}"

			echo "Updating line ${lineNumber}: Success"
		fi
	done <<< $updated_lines
}

# Create a file of the updated lines prepended with the line numbers
updated_lines=$(awk -f ./patch.awk -v portal_path_addition=${portal_path_addition} ${input_patch_file})

create_updated_patch "${updated_lines}"

echo "Patch complete!"
