#!/usr/bin/env bash

# Checks whether the requested Cloudflare allowlist still receives origin certificates.
set -u

domains=(
  "cloudflareportal.com"
  "cloudflareok.com"
  "cloudflarecp.com"
  "api.devices.cloudflare.com"
  "engage.cloudflareclient.com"
  "connectivity.cloudflareclient.com"
  "2a77532a52bd0b24bb61053431078b78.cloudflare-gateway.com"
)

if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl is required." >&2
  exit 2
fi

failures=0

for domain in "${domains[@]}"; do
  # curl supplies SNI and bounds each probe so an unreachable office path cannot hang.
  certificate=$(curl -kIsS --connect-timeout 5 --max-time 10 \
    -o /dev/null -w '%{certs}' "https://${domain}/" 2>/dev/null | awk '
      /^Subject:/ || /^Issuer:/ || /^Expire date:/ { print }
      /^Expire date:/ { exit }
    ')

  if [[ -z "$certificate" ]]; then
    printf 'ERROR  %s — no certificate received\n' "$domain"
    failures=$((failures + 1))
    continue
  fi

  issuer=$(printf '%s\n' "$certificate" | awk '/^Issuer:/{sub(/^Issuer:/, ""); print}')

  if printf '%s\n' "$issuer" | grep -qi 'zscaler'; then
    status="INTERCEPTED"
    failures=$((failures + 1))
  else
    status="BYPASSED"
  fi

  printf '%s  %s\n' "$status" "$domain"
  printf '  %s\n' "$certificate"
done

exit "$failures"