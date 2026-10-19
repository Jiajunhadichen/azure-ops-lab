#!/usr/bin/env bash
# Read-only checks before deploying a VM size: is the size allowed in the region,
# is there quota for its family, which disk controller does it need, and what it costs.
# Written after the B-series sizes failed on quota (2026-10-13) and the D2als_v6 checks
# had to be done by hand (2026-10-19).
#
# Usage: infra/preflight.sh [size] [count]   # defaults: Standard_D2als_v6, 2 VMs
# Exit code 1 if the size is restricted or the quota is too small.
set -euo pipefail

SIZE="${1:-Standard_D2als_v6}"
COUNT="${2:-2}"
REGION="${REGION:-swedencentral}"
IMAGE="${IMAGE:-Canonical:ubuntu-24_04-lts:server:latest}"
ok=true

echo "== $SIZE x $COUNT in $REGION"

# 1. Size: restrictions, family, vCPUs, disk controllers, Trusted Launch.
read -r restricted family vcpus controllers tl_off < <(az vm list-skus -l "$REGION" \
  --resource-type virtualMachines --size "$SIZE" \
  --query "[?name=='$SIZE'] | [0].[length(restrictions), family,
           capabilities[?name=='vCPUs'].value | [0],
           capabilities[?name=='DiskControllerTypes'].value | [0] || 'SCSI',
           capabilities[?name=='TrustedLaunchDisabled'].value | [0] || 'False']" -o tsv | tr -d ' ')
if [[ -z "${family:-}" ]]; then echo "FAIL: $SIZE is not offered in $REGION"; exit 1; fi
echo "family=$family vcpus=$vcpus disk_controllers=$controllers trusted_launch_disabled=$tl_off"
if [[ "$restricted" != "0" ]]; then echo "FAIL: $SIZE is restricted in $REGION (SkuNotAvailable)"; ok=false; fi

# 2. Quota: family and regional vCPUs. az returns limits as strings.
need=$(( vcpus * COUNT ))
for name in "$family" cores; do
  read -r used limit < <(az vm list-usage -l "$REGION" \
    --query "[?name.value=='$name'] | [0].[currentValue, limit]" -o tsv)
  free=$(( ${limit:-0} - ${used:-0} ))
  echo "quota $name: used=${used:-0} limit=${limit:-0} free=$free need=$need"
  if (( free < need )); then echo "FAIL: not enough $name quota"; ok=false; fi
done

# 3. Image: must support the size's disk controller and Trusted Launch.
az vm image show --urn "$IMAGE" -l "$REGION" \
  --query "features[?name=='DiskControllerTypes' || name=='SecurityType'].[name, value]" -o tsv

# 4. Price: Linux pay-as-you-go, SEK per hour (Azure retail prices API, no login needed).
curl -s -G "https://prices.azure.com/api/retail/prices" --data-urlencode "currencyCode=SEK" \
  --data-urlencode "\$filter=armRegionName eq '$REGION' and armSkuName eq '$SIZE' and priceType eq 'Consumption'" \
  | jq -r '.Items[] | select(.productName|test("Windows")|not) | select(.skuName|test("Spot|Low")|not)
           | "price: \(.retailPrice) SEK/\(.unitOfMeasure)"'

if $ok; then echo "OK: $SIZE can be deployed"; else exit 1; fi
