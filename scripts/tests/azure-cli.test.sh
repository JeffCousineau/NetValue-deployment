#!/usr/bin/env bash
set -euo pipefail
scripts=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -f "$fixture/az" "$fixture/provider-called" "$fixture/firewall-rules" "$fixture/output" "$fixture/file-read"; rmdir "$fixture"' EXIT
cat > "$fixture/az" <<'MOCK'
#!/usr/bin/env bash
for argument in "$@"; do
  [[ "$argument" != *$'\r'* ]] || { echo 'CR leaked into an Azure argument' >&2; exit 99; }
done
case "$1 $2" in
  'account show') printf '%s\r\n' "${MOCK_TENANT:-e099407c-b3b3-45aa-868e-cc901f513dc5}" ;;
  'provider register') touch "$MOCK_MARKER"; [[ "${MOCK_COMPLETE:-false}" == true ]] || exit 37 ;;
  'webapp show')
    if [[ "$*" == *possibleOutboundIpAddresses* ]]; then printf '10.0.0.1,10.0.0.2,10.0.0.3\r\n'; else printf '10.0.0.1,10.0.0.2\r\n'; fi ;;
  'sql server') printf '%s\n' "$*" >> "$MOCK_RULES" ;;
  'test values') printf 'first\r\nsecond\r\n' ;;
  'test failure') exit 42 ;;
  'account set'|'group create'|'role assignment') ;;
  'storage account') printf '/subscriptions/test/resourceGroups/test/providers/Microsoft.Storage/storageAccounts/test\r\n' ;;
  'storage container') ;;
  'ad signed-in-user') printf '1112bb2c-81d0-4e08-8009-4eab2c6a9b8b\r\n' ;;
  'ad sp') [[ "$3" != show ]] || printf '00000000-0000-0000-0000-000000000002\r\n' ;;
  'ad app')
    case "$3" in
      list) printf '0\r\n' ;;
      create) printf '00000000-0000-0000-0000-000000000003\r\n' ;;
      federated-credential)
        if [[ "$4" == show ]]; then
          [[ "${MOCK_EXISTING_CREDENTIAL:-false}" == true ]] || exit 1
        else
          operation=$4
          while [[ "$1" != --parameters ]]; do shift; done
          file_path=${2#@}
          case "${OSTYPE:-}" in
            msys*|cygwin*)
              [[ "$file_path" != /* ]] || { echo 'Windows Azure CLI cannot resolve a POSIX @file path' >&2; exit 97; }
              file_path=$(cygpath -u "$file_path") ;;
          esac
          [[ -r "$file_path" ]]
          grep -q 'repo:JeffCousineau@8643172/NetValue-deployment@1403790853:environment:production' "$file_path"
          [[ "${MSYS_NO_PATHCONV:-}" == 1 && "${MSYS2_ARG_CONV_EXCL:-}" == '*' ]]
          printf '%s\n' "$operation" >> "$MOCK_FILE_READ"
        fi ;;
    esac ;;
  *) echo "Unexpected mock command: $*" >&2; exit 98 ;;
esac
MOCK
chmod +x "$fixture/az"
export PATH="$fixture:$PATH"
export MOCK_MARKER="$fixture/provider-called"
export MOCK_RULES="$fixture/firewall-rules"
source "$scripts/azure-cli.sh"
[[ $(az test values) == $'first\nsecond' ]]
status=0
az test failure || status=$?
[[ "$status" == 42 ]] || { echo 'Azure exit status lost'; exit 1; }
status=0
bash "$scripts/bootstrap-azure.sh" > "$fixture/output" 2>&1 || status=$?
[[ "$status" == 37 && -f "$MOCK_MARKER" ]] || { cat "$fixture/output"; echo 'Matching CRLF tenant was rejected'; exit 1; }
rm "$MOCK_MARKER"
export MOCK_TENANT='00000000-0000-0000-0000-000000000001'
status=0
bash "$scripts/bootstrap-azure.sh" > "$fixture/output" 2>&1 || status=$?
[[ "$status" == 1 && ! -f "$MOCK_MARKER" ]]
grep -q "Expected: e099407c-b3b3-45aa-868e-cc901f513dc5; actual: $MOCK_TENANT" "$fixture/output"
bash "$scripts/allow-app-sql.sh" test-app test-server
[[ $(wc -l < "$MOCK_RULES") == 3 ]]
grep -q 'start-ip-address 10.0.0.3 --end-ip-address 10.0.0.3' "$MOCK_RULES"
unset MOCK_TENANT
export MOCK_COMPLETE=true
export MOCK_FILE_READ="$fixture/file-read"
bash "$scripts/bootstrap-azure.sh" > "$fixture/output" 2>&1 || { cat "$fixture/output"; exit 1; }
[[ $(cat "$MOCK_FILE_READ") == create ]]
export MOCK_EXISTING_CREDENTIAL=true
bash "$scripts/bootstrap-azure.sh" > "$fixture/output" 2>&1 || { cat "$fixture/output"; exit 1; }
[[ $(tail -n 1 "$MOCK_FILE_READ") == update ]]
grep -q 'GitHub production environment variables:' "$fixture/output"
echo 'Azure CLI CRLF, native JSON paths, failure propagation, tenant guard, and IP handling checks passed.'
