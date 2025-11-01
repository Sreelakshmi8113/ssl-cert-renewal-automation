#!/bin/bash
# check_cert_and_request_approval.sh
# Run daily via cron. Uses awscli (SES) to send approval email when cert near expiry.
set -euo pipefail

DOMAIN="ssl-automation.duckdns.org"
THRESHOLD_DAYS=90
SENDER_EMAIL="sreejayaksaji@gmail.com"      # SES-verified sender
OWNER_EMAIL="sreelakshmiksaji492@gmail.com"   # recipient (must be SES-verified if in sandbox)
APPROVAL_BASE_URL="https://ssl-automation.duckdns.org/approve"  # Nginx will proxy /approve to the approval handler
DATA_DIR="$(dirname "$0")/data"
DB_FILE="$DATA_DIR/approvals.json"

mkdir -p "$DATA_DIR"

# make sure jq exists
if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required but not installed. Install jq (sudo dnf install -y jq) and retry." >&2
  exit 2
fi

expiry_str=$(openssl s_client -connect ${DOMAIN}:443 -servername ${DOMAIN} </dev/null 2>/dev/null \
  | openssl x509 -noout -enddate 2>/dev/null | sed 's/notAfter=//')
if [ -z "$expiry_str" ]; then
  echo "$(date): Unable to read cert expiry for $DOMAIN" >&2
  exit 2
fi

expiry_epoch=$(date -d "$expiry_str" +%s)
now=$(date +%s)
days_left=$(( (expiry_epoch - now) / 86400 ))

if [ "$days_left" -le "$THRESHOLD_DAYS" ]; then
  token=$(uuidgen)
  created=$(date +%s)
  expire_token=$((created + 48*3600))
  # save token record (append JSON line)
  jq -n --arg t "$token" --arg d "$DOMAIN" --arg owner "$OWNER_EMAIL" \
     --argjson created "$created" --argjson expires_at "$expire_token" \
     '{token:$t,domain:$d,owner:$owner,created:$created,expires_at:$expires_at,status:"PENDING"}' \
     >> "$DB_FILE"
  approval_link="${APPROVAL_BASE_URL}?token=${token}"
  subject="[ACTION REQUIRED] Approve SSL renewal for ${DOMAIN}"
  body_html="<html><body><p>Automated SSL renewal for <b>${DOMAIN}</b> requires approval.</p><p><a href='${approval_link}'>Click to approve</a> (valid 48 hours)</p></body></html>"

  # build a temp JSON message file using jq (safe quoting)
  MSGFILE=$(mktemp /tmp/sesmsg.XXXXXX.json)
  jq -n --arg subj "$subject" --arg html "$body_html" \
     '{Subject: {Data: $subj, Charset: "utf-8"}, Body: {Html: {Data: $html, Charset: "utf-8"}}}' \
     > "$MSGFILE"
  trap 'rm -f "${MSGFILE}"' EXIT

  # Send the email and report result
  if aws ses send-email \
       --region us-east-1 \
       --from "$SENDER_EMAIL" \
       --destination "ToAddresses=${OWNER_EMAIL}" \
       --message file://"$MSGFILE"; then
    echo "$(date): Sent approval email to $OWNER_EMAIL for $DOMAIN (token $token)"
  else
    echo "$(date): Failed to send approval email for $DOMAIN (token $token)" >&2
    # keep the record so you can inspect, do not delete DB line
    rm -f "$MSGFILE"
    trap - EXIT
    exit 1
  fi

  # cleanup temp file and clear trap
  rm -f "$MSGFILE"
  trap - EXIT
else
  echo "$(date): Certificate OK (${days_left} days left)."
fi

