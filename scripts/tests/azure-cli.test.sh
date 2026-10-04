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
  'webapp show') printf '10.0.0.1,10.0.0.2\r\n' ;;
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
        if [[ "$4" == list ]]; then printf '0\r\n'; else
          while [[ "$1" != --parameters ]]; do shift; done
          file_path=${2#@}
          case "${OSTYPE:-}" in
            msys*|cygwin*)
              [[ "$file_path" != /* ]] || { echo 'Windows Azure CLI cannot resolve a POSIX @file path' >&2; exit 97; }
              file_path=$(cygpath -u "$file_path") ;;
          esac
          [[ -r "$file_path" ]]
          grep -q 'repo:JeffCousineau/NetValue-deployment:environment:production' "$file_path"
          [[ "${MSYS_NO_PATHCONV:-}" == 1 && "${MSYS2_ARG_CONV_EXCL:-}" == '*' ]]
          touch "$MOCK_FILE_READ"
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
[[ $(wc -l < "$MOCK_RULES") == 2 ]]
unset MOCK_TENANT
export MOCK_COMPLETE=true
export MOCK_FILE_READ="$fixture/file-read"
bash "$scripts/bootstrap-azure.sh" > "$fixture/output" 2>&1 || { cat "$fixture/output"; exit 1; }
[[ -f "$MOCK_FILE_READ" ]]
grep -q 'GitHub production environment variables:' "$fixture/output"
echo 'Azure CLI CRLF, native JSON paths, failure propagation, tenant guard, and IP handling checks passed.'
