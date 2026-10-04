#!/usr/bin/env bash
set -euo pipefail
scripts=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
cat > "$fixture/az" <<'MOCK'
#!/usr/bin/env bash
for argument in "$@"; do
  [[ "$argument" != *$'\r'* ]] || { echo 'CR leaked into an Azure argument' >&2; exit 99; }
done
case "$1 $2" in
  'account show') printf '%s\r\n' "${MOCK_TENANT:-e099407c-b3b3-45aa-868e-cc901f513dc5}" ;;
  'provider register') touch "$MOCK_MARKER"; exit 37 ;;
  'webapp show') printf '10.0.0.1,10.0.0.2\r\n' ;;
  'sql server') printf '%s\n' "$*" >> "$MOCK_RULES" ;;
  'test values') printf 'first\r\nsecond\r\n' ;;
  'test failure') exit 42 ;;
  'account set') ;;
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
echo 'Azure CLI CRLF, failure propagation, tenant guard, and IP handling checks passed.'
