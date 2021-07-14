#!/bin/bash

set -e

source config

# Need to install jq tool

# TODO Update this to always read files from this DIR for accessing patch.awk

# This script takes the pull request id at arg1, fetches the patch for the PR and then updates the paths in the patch with the portal_path_addition provided in the config file.

ORIGIN_PULL_ID="${1}"

# Add ci:foward & link comment to origin PR
add_origin_pr_comment() {
	local pr_body="${1}"

	local response=$(curl -X POST -H "Authorization: token ${TOKEN}" -d  "{\"body\": \"${pr_body}\"}" "https://api.github.com/repos/${GITHUB_ORIGIN_USER}/${GITHUB_ORIGIN_REPO}/issues/${ORIGIN_PULL_ID}/comments")

	echo $(echo "${response}" | jq '.body')
}

# Update PR origin state
update_origin_pr_state() {
	local state="${1}"

	curl -X PATCH -H "Authorization: token ${TOKEN}" -d  "{\"state\": \"${state}\"}" "https://api.github.com/repos/${GITHUB_ORIGIN_USER}/${GITHUB_ORIGIN_REPO}/issues/${ORIGIN_PULL_ID}"
}

# Close original PR with comment linking to new PR
add_destination_pr_comment() {
	local pr_number="${1}"

	local pr_body="ci:forward"

	curl -X POST -H "Authorization: token ${TOKEN}" -d  "{\"body\": \"${pr_body}\"}" "https://api.github.com/repos/${GITHUB_DESTINATION_USER}/${GITHUB_DESTINATION_REPO}/issues/${pr_number}/comments"
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

# Delete local branch
delete_local_branch() {
	local file_name=$(basename "${patch_file_path}" .patch)

	git checkout "7.1.x"

	git branch -D "${file_name}"
}

# Push pull request to origin and send a pull request to origin against BASE_BRANCH
send_pull_request() {
	local file_name=$(basename "${patch_file_path}" .patch)

	# Update to use liferay-ac-ci user instead of my account.  Also should use github api vs hub
	# local destination_pr_response=$(curl -X POST -H "Authorization: token ${TOKEN}" -d  "{\"title\": \"${file_name}\", \"body\": \"ci:forward\", \"head\": \"${file_name}\", \"base\": \"7.1.x\"}" "https://api.github.com/repos/${GITHUB_DESTINATION_USER}/${GITHUB_DESTINATION_REPO}/pulls")

	# For testing purposes
	local destination_pr_response=$(curl -X GET -H "Authorization: token ${TOKEN}" "https://api.github.com/repos/${GITHUB_DESTINATION_USER}/${GITHUB_DESTINATION_REPO}/pulls/23")

	local destination_changes=$(echo "${destination_pr_response}" | jq --raw-output '{additions: .additions, changed_files: .changed_files, deletions: .deletions} | to_entries | map("[\(.key)]=\(.value)") | reduce .[] as $item ("destination_changes_dict=("; . + ($item) + " ") + ")"')


	# Creates destination_changes_dict
	local -A "${destination_changes}"

	local origin_pr_response=$(curl -X GET -H "Authorization: token ${TOKEN}" "https://api.github.com/repos/${GITHUB_ORIGIN_USER}/${GITHUB_ORIGIN_REPO}/pulls/${ORIGIN_PULL_ID}")

	local origin_changes=$(echo "${origin_pr_response}" | jq --raw-output '{additions: .additions, changed_files: .changed_files, deletions: .deletions} | to_entries | map("[\(.key)]=\(.value)") | reduce .[] as $item ("origin_changes_dict=("; . + ($item) + " ") + ")"')

	# Creates origin_changes_dict
	local -A "${origin_changes}"

	local change_errors


	for key in "${!destination_changes_dict[@]}"; do
		if [[ "${destination_changes_dict[${key}]}" != "${origin_changes_dict[${key}]}" ]]; then
			change_errors="${change_errors}**${key}** count does not match\n"
		fi
	done


	if [[ -n "${change_errors}" ]]; then
		# Send change errors as comment to original PR
		add_origin_pr_comment "### Patching Failed:\n${change_errors}"

		exit 1
	fi

	echo "${destination_pr_response}"
}

update_origin_base_branch() {
	current_branch=$(git branch --show-current)

	if [[ $current_branch != "${BASE_BRANCH}" ]]; then
		git checkout "${BASE_BRANCH}"
	fi

	git pull --rebase upstream "${BASE_BRANCH}"

	git push origin "${BASE_BRANCH}"
}

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

		if [[ "${current_line_string}" == *"${DESTINATION_PATH_ADDITION}"* ]]; then
			echo "Skipping line ${lineNumber}: Already converted"
		else
			sed -i "${lineNumber}s~^.*$~${lineContent}~" "${file_path}"

			echo "Updating line ${lineNumber}: Success"
		fi
	done <<< $updated_lines

	echo "Patch file updated"
}

fetch_patch() {
	curl -H "Authorization: token ${TOKEN}" -H "Accept: application/vnd.github.v3.patch" "https://api.github.com/repos/${GITHUB_ORIGIN_USER}/${GITHUB_ORIGIN_REPO}/pulls/${ORIGIN_PULL_ID}" > "${PATCH_FILE_SAVE_LOCATION}/pull-${ORIGIN_PULL_ID}.patch"

	echo "${PATCH_FILE_SAVE_LOCATION}/pull-${ORIGIN_PULL_ID}.patch"
}

main() {
	if [[ -z "${ORIGIN_PULL_ID}" ]]; then
		echo "A ORIGIN_PULL_ID is required: ${0} ORIGIN_PULL_ID"

		exit 1
	fi

	patch_file_path=$(fetch_patch)

	# Create a file of the updated lines prepended with the line numbers
	local updated_lines=$(awk -f ./patch.awk -v portal_path_addition="${DESTINATION_PATH_ADDITION}" "${patch_file_path}")

	create_updated_patch	"${patch_file_path}" "${updated_lines}"

	cd "${PATCH_DESTINATION_PATH}"

	update_origin_base_branch

	apply_patch "${patch_file_path}"

	local file_name=$(basename "${patch_file_path}" .patch)

	git push origin "${file_name}"

	local pr_response=$(send_pull_request)

	local pr_number=$(echo "${pr_response}" | jq '.number')
	local pr_url=$(echo "${pr_response}" | jq '.html_url')

	local origin_comment_body=$(add_origin_pr_comment "PR forwarded to [here](${pr_url})")

	if [[ -n  "${origin_comment_body}" ]]; then
		update_origin_pr_state "closed"
	else
		echo "Failed to add origin pr comment"
	fi

	echo "${pr_number}"
	add_destination_pr_comment "${pr_number}"

	delete_local_branch

	echo "Patch complete!"
}

main
