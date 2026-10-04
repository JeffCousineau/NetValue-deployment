# Windows Azure CLI emits CRLF even when invoked from Git Bash. Normalize only
# line endings so command substitutions contain clean IDs, counts, and IPs.
# The caller enables pipefail so Azure CLI failures retain their exit status.
az() {
  MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' command az "$@" | sed 's/\r$//'
}

# @file arguments are not reliably translated by Git Bash for native Windows az.
# Convert file paths explicitly while leaving ARM /subscriptions/... IDs intact.
azure_cli_path() {
  case "${OSTYPE:-}" in
    msys*|cygwin*) cygpath -w "$1" ;;
    *) printf '%s\n' "$1" ;;
  esac
}
