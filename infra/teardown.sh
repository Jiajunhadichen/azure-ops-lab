#!/usr/bin/env bash
# Delete every lab resource in the resource group, keep the group, the deploy identity and the
# free alerting baseline (infra/monitoring.bicep),
# then check the whole subscription for billable leftovers (disks, public IPs, snapshots).
#
# Usage: infra/teardown.sh          # dry run: list what would be deleted
#        infra/teardown.sh --yes    # delete, then check for leftovers
#        infra/teardown.sh --check  # only the leftover check (read-only)
# Exit code 1 if anything billable is left afterwards.
set -euo pipefail

RG="${RG:-rg-azopslab-swc}"
# Kept on teardown (free). Matched case-insensitively: az returns resource types in mixed case.
KEEP_RE="microsoft.managedidentity/userassignedidentities|microsoft.insights/actiongroups|microsoft.insights/activitylogalerts"
not_kept() { # stdin: lines starting with a resource type; prints the lines that are not kept
  grep -viE "^(${KEEP_RE})([[:space:]]|$)" || true
}
APPLY=false
CHECK_ONLY=false
[[ "${1:-}" == "--yes" ]] && APPLY=true
[[ "${1:-}" == "--check" ]] && CHECK_ONLY=true

ids_of() { # $1 = resource type
  az resource list -g "$RG" --resource-type "$1" --query "[].id" -o tsv
}

# Delete in dependency order: VMs first (their OS disks and NICs go with them), then networking.
ORDER=(
  Microsoft.Compute/virtualMachines
  Microsoft.Network/networkInterfaces
  Microsoft.Compute/disks
  Microsoft.Network/publicIPAddresses
  Microsoft.Network/natGateways
  Microsoft.Network/virtualNetworks
  Microsoft.Network/networkSecurityGroups
  Microsoft.Network/applicationSecurityGroups
)

if ! $CHECK_ONLY; then
echo "Resource group: $RG ($( $APPLY && echo delete || echo dry run ))"
for type in "${ORDER[@]}"; do
  ids=$(ids_of "$type") # one ID per line (no mapfile: macOS ships bash 3.2)
  [[ -z "$ids" ]] && continue
  printf '  %s: %d\n' "${type##*/}" "$(wc -l <<<"$ids" | tr -d ' ')"
  if $APPLY; then
    # shellcheck disable=SC2086 # IDs contain no spaces; split on newlines on purpose
    az resource delete --ids $ids --only-show-errors >/dev/null
  fi
done

# Anything else in the group that is not kept. A dry run deletes nothing, so it also hides the
# types in ORDER; after --yes, anything still listed failed to delete or is not in ORDER.
all=$(az resource list -g "$RG" --query "[].[type, name]" -o tsv)
others=$(printf '%s' "$all" | not_kept)
if ! $APPLY; then
  ORDER_RE=$(IFS='|'; echo "${ORDER[*]}")
  others=$(printf '%s' "$others" | { grep -viE "^(${ORDER_RE})([[:space:]]|$)" || true; })
fi
if [[ -n "$others" ]]; then
  echo "Not in the delete order (handle by hand):"
  echo "$others" | sed 's/^/  /'
fi

$APPLY || { echo "Dry run only. Re-run with --yes to delete."; exit 0; }
fi

echo "Leftover check (whole subscription):"
left=0
check() { # $1 = label, $2 = az query returning a count
  local n
  n=$(eval "$2")
  printf '  %-36s %s\n' "$1" "$n"
  [[ "$n" == "0" ]] || left=1
}
rg_types=$(az resource list -g "$RG" --query "[].type" -o tsv)
check "resources in $RG (not kept)" "printf '%s' \"\$rg_types\" | not_kept | grep -c . || true"
# az disk list needs -g in current CLI versions, so ask the API for the whole subscription.
check "unattached managed disks" "az rest --method get --url '/subscriptions/{subscriptionId}/providers/Microsoft.Compute/disks?api-version=2024-03-02' --query \"length(value[?properties.diskState=='Unattached'])\" -o tsv"
check "unassociated public IPs" "az network public-ip list --query 'length([?ipConfiguration==null && natGateway==null])' -o tsv"
check "snapshots" "az snapshot list --query 'length(@)' -o tsv"

if [[ $left -eq 0 ]]; then
  echo "Clean: nothing billable left."
else
  echo "Leftovers found: check them before closing the lab." >&2
  exit 1
fi
