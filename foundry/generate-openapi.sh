#!/bin/bash
set -euo pipefail

workflow=${1:-}
workflow_pattern='^/subscriptions/([^/]+)/resourceGroups/[^/]+/providers/Microsoft\.Logic/workflows/[^/]+$'
if [[ $# != 1 || ! "$workflow" =~ $workflow_pattern ]]; then
  printf 'Usage: bash %s <Logic App workflow resource ID>\n' "$0" >&2
  exit 2
fi
subscription=${BASH_REMATCH[1]}

callback=$(az rest --subscription "$subscription" --method post \
  --uri "https://management.azure.com$workflow/triggers/identify/listCallbackUrl?api-version=2016-06-01" \
  --query value -o tsv --only-show-errors)
callback_pattern='^(https://[a-zA-Z0-9.-]+)(:443)?(/workflows/[a-zA-Z0-9_-]+/triggers/identify/paths/invoke)\?api-version=([a-zA-Z0-9._-]+)$'
if [[ ! "$callback" =~ $callback_pattern ]]; then
  printf '%s\n' 'Expected a Logic Apps callback URL with SAS disabled.' >&2
  exit 2
fi

jq -n --arg host "${BASH_REMATCH[1]}" --arg path "${BASH_REMATCH[3]}" \
  --arg api_version "${BASH_REMATCH[4]}" '{
  openapi:"3.0.3", info:{title:"VM Lab Identify",version:"1.0.0"},
  servers:[{url:$host}],
  paths:{($path):{post:{operationId:"identify_vm",description:"Identify the configured Linux VM.",
    parameters:[{name:"api-version",in:"query",required:true,schema:{type:"string",enum:[$api_version],default:$api_version}}],
    requestBody:{required:true,content:{"application/json":{schema:{type:"object",additionalProperties:false}}}},
    responses:{"200":{description:"Azure VM Run Command result",content:{"application/json":{schema:{type:"object"}}}},"502":{description:"The VM diagnostic did not complete."}}
  }}}
}'
