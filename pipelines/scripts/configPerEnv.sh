#!/bin/bash
# Reusable per-environment replication helper

function configPerEnv(){
  local dir="$1"
  local envTypes="$2"
  local configType="$3"
  local sourceFile="$4"
  local key="$5"

  IFS=, read -ra values <<< "$envTypes"
  for v in "${values[@]}"; do
    v=$(echo "$v" | xargs | tr -d '"' | tr -d "'")
    [ -z "$v" ] && continue
    if [ "${configType}" == "referenceData" ]; then
       cp "${dir}/${sourceFile}" "${dir}/${v}.csv"
    else
       if [[ "$configType" == "project_parameter" || "$configType" == "connection" || "$configType" == "scheduler" || "$configType" == "certificate" || "$configType" == "project_variable" ]]; then
           cp "${dir}/${sourceFile}" "${dir}/${key}-${v}.json"
       fi
    fi
  done
}
