#!/bin/bash

#################################################################################################################################################################
# Summary:                                                                                                                                                      #
#   Exports project configuration details from a given repository in the local development environment.                                                         #
#   The script retrieves the project configuration list via API and saves it locally in JSON files.                                                             #
#   It stores both the full export and specific sections (packages, variables, connections, certificates,                                                       #
#   schedules, alert rules, and version control accounts).                                                                                                      #
#                                                                                                                                                               #
# Usage:                                                                                                                                                        #
#   ./exportProjectConfiguration.sh <LOCAL_DEV_URL> <admin_user> <admin_password> <repoName> <HOME_DIR>                                                         #
#                                                                                                                                                               #
# Mandatory Fields:                                                                                                                                             #
#   LOCAL_DEV_URL   - Base URL of the local dev environment (e.g., http://localhost:5555)                                                                       #
#   admin_user      - Admin username for authentication                                                                                                         #
#   admin_password  - Admin password for authentication                                                                                                         #
#   repoName        - Name of the repository/project from which to export configurations                                                                        #
#   HOME_DIR        - Path to the base working directory where exported files will be stored                                                                    #
#################################################################################################################################################################


set -x
echo "Starting exportProjectConfiguration.sh"
echo "Arguments: $@"

function exportProjectConfigurationList() {
    LOCAL_DEV_URL=$1
    admin_user=$2
    admin_password=$3
    repoName=$4
    HOME_DIR=$5

    echo "Running exportProjectConfigurationList with parameters:"
    echo "LOCAL_DEV_URL=$LOCAL_DEV_URL"
    echo "admin_user=$admin_user"
    echo "repoName=$repoName"
    echo "HOME_DIR=$HOME_DIR"

    cd "${HOME_DIR}/${repoName}" || exit 1

    PROJECT_CONFIGURATION_IMPORT_LIST_URL="${LOCAL_DEV_URL}/apis/v2/rest/projects/${repoName}/configurations"

    # Call API to get Project Configuration list
    ProjectConfigurationListJson=$(curl --silent --location --request GET "${PROJECT_CONFIGURATION_IMPORT_LIST_URL}" \
        --header 'Content-Type: application/json' \
        --header 'Accept: application/json' \
        -u "${admin_user}:${admin_password}")

    # Validate response
    if [ -z "$ProjectConfigurationListJson" ] || [ "$ProjectConfigurationListJson" == "null" ]; then
        echo "❌ No Project Configurations retrieved."
        echo "$ProjectConfigurationListJson"
        return
    fi

    # Pretty print for local storage
    ProjectConfigurationListExport=$(echo "$ProjectConfigurationListJson" | jq '.')

    output_dir="./assets/projectConfigs/ProjectConfiguration"
    mkdir -p "$output_dir"

    # Save full export
    export_file="$output_dir/ProjectConfiguration_List_Full.json"
    echo "$ProjectConfigurationListExport" > "$export_file"
    echo "✅ Full project configuration list saved to: $export_file"

    # Extract specific sections into separate files
    echo "$ProjectConfigurationListExport" | jq '.configurations.packages' > "$output_dir/configurations_packages.json"
    echo "✅ Extracted configurations.packages"

    echo "$ProjectConfigurationListExport" | jq '.configurations.variables' > "$output_dir/configurations_variables.json"
    echo "✅ Extracted configurations.variables"

    echo "$ProjectConfigurationListExport" | jq '.configurations.connections' > "$output_dir/configurations_connections.json"
    echo "✅ Extracted configurations.connections"

    echo "$ProjectConfigurationListExport" | jq '.configurations.certificates' > "$output_dir/configurations_certificates.json"
    echo "✅ Extracted configurations.certificates"

    echo "$ProjectConfigurationListExport" | jq '.configurations.servicesSchedule' > "$output_dir/configurations_servicesSchedule.json"
    echo "✅ Extracted configurations.servicesSchedule"

    echo "$ProjectConfigurationListExport" | jq '.globals.alertRules' > "$output_dir/globals_alertRules.json"
    echo "✅ Extracted globals.alertRules"

    echo "$ProjectConfigurationListExport" | jq '.globals.versionControlAccounts' > "$output_dir/globals_versionControlAccounts.json"
    echo "✅ Extracted globals.versionControlAccounts"
}

exportProjectConfigurationList "$@"
