# Windows Azure CLI emits CRLF even when invoked from Git Bash. Normalize only
# line endings so command substitutions contain clean IDs, counts, and IPs.
# The caller enables pipefail so Azure CLI failures retain their exit status.
az() {
  command az "$@" | sed 's/\r$//'
}
