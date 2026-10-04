#!/usr/bin/env bash
set -euo pipefail
# Exact App Service outbound IPv4 addresses only. No AllowAzureServices rule.
app_name=${1:?Supply web app name}
server_name=${2:?Supply SQL server name}
ips=$(az webapp show -g rg-netvalue-free -n "$app_name" --query outboundIpAddresses -o tsv)
[[ -n "$ips" ]] || { echo 'No outbound IP addresses returned'; exit 1; }
IFS=',' read -ra addresses <<< "$ips"
index=0
for ip in "${addresses[@]}"; do
  az sql server firewall-rule create -g rg-netvalue-free -s "$server_name" -n "netvalue-app-${index}" --start-ip-address "$ip" --end-ip-address "$ip" --output none
  index=$((index+1))
done
