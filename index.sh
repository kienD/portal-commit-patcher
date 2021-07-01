#!/bin/bash

source config

# TODO Update this to always read files from this DIR for accessing patch.awk

# This script takes the pull request id at arg1, fetches the patch for the PR and then updates the paths in the patch with the portal_path_addition provided in the config file.

PULL_ID="${1}"

# Interate through lines in updated_lines and update the respective line in file
create_updated_patch() {
	local file_path="${1}"
	local updated_lines="${2}"

	while read line; do
		IFS=':'

		read -a lineArray <<< "${line}"

		lineNumber=${lineArray[0]}
		lineContent=${lineArray[1]}

		current_line_string=$(sed "${lineNumber}q;d" "${file_path}")

		if [[ "${current_line_string}" == *"${PORTAL_PATH_ADDITION}"* ]]; then
			echo "Skipping line ${lineNumber}: Already converted"
		else
			sed -i "${lineNumber}s~^.*$~${lineContent}~" "${file_path}"

			echo "Updating line ${lineNumber}: Success"
		fi
	done <<< $updated_lines

	echo "Patch file updated"
}

fetch_patch() {
	curl -H "Authorization: token ${TOKEN}" -H "Accept: application/vnd.github.v3.patch" "https://api.github.com/repos/${GITHUB_USER}/${GITHUB_REPO}/pulls/${PULL_ID}" > "${PATCH_FILE_SAVE_LOCATION}/pull-${PULL_ID}.patch"

	echo "${PATCH_FILE_SAVE_LOCATION}/pull-${PULL_ID}.patch"
}

# Apply patch to repo at patch_destination_path
apply_patch() {
	# TODO: Should check for current branch before doing this.  maybe create a new branch and then reset it to upstream
	local file_path="${1}"
	local file_name=$(basename "${patch_file_path}" .patch)

	echo "Patching git repo at ${PATCH_DESTINATION_PATH}"

	cd "${PATCH_DESTINATION_PATH}"

	git checkout -b  "${file_name}"

	cat "${file_path}" | git am

	echo "Patch Success (Maybe)"
}

# Create a file of the updated lines prepended with the line numbers
patch_file_path=$(fetch_patch)

updated_lines=$(awk -f ./patch.awk -v portal_path_addition=${PORTAL_PATH_ADDITION} ${patch_file_path})

create_updated_patch  "${patch_file_path}" "${updated_lines}"

apply_patch "${patch_file_path}"

echo "Patch complete!"
