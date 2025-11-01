#!/bin/bash
# check_cert_and_request_approval.sh
# Run daily via systemd timer. Uses awscli (SES) to send approval email when cert near expiry.
set -euo pipefail

DOMAIN="ssl-automation.duckdns.org"
THRESHOLD_DAYS=90
SENDER_EMAIL="sreejayaksaji@gmail.com"      # SES-verified sender
OWNER_EMAIL="sreelakshmiksaji492@gmail.com"   # recipient (must be SES-verified if in sandbox)
APPROVAL_BASE_URL="https://ssl-automation.duckdns.org/approve"  # Nginx will proxy /approve to the approval handler
DATA_DIR="$(dirname "$0")/data"
DB_FILE="$DATA_DIR/approvals.json"

# APPROVAL SERVER DB (where approval_server.py reads tokens)
APP_DB="/opt/ssl-cert-renewal-automation/approvals.db"

mkdir -p "$DATA_DIR"

# ----- prerequisites check -----
for cmd in jq uuidgen aws sqlite3 openssl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "$(date): Error: required command '$cmd' not found. Please install and retry." >&2
    exit 2
  fi
done

# ----- helper: init approval server DB/table if missing -----
_init_app_db() {
  if [ ! -f "$APP_DB" ]; then
    echo "$(date): Approval DB not found at $APP_DB — creating."
    sqlite3 "$APP_DB" "CREATE TABLE IF NOT EXISTS approvals (token TEXT PRIMARY KEY, domain TEXT, owner TEXT, created INTEGER, expires_at INTEGER, status TEXT);"
    # keep file owned by ec2-user (service runs as ec2-user)
    sudo chown ec2-user:ec2-user "$APP_DB" 2>/dev/null || true
  else
    # ensure table exists
    sqlite3 "$APP_DB" "CREATE TABLE IF NOT EXISTS approvals (token TEXT PRIMARY KEY, domain TEXT, owner TEXT, created INTEGER, expires_at INTEGER, status TEXT);" >/dev/null 2>&1 || true
  fi
}

# ----- read current cert expiry -----
expiry_str=$(openssl s_client -connect "${DOMAIN}:443" -servername "${DOMAIN}" </dev/null 2>/dev/null \
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

  # build the JSON line and append to history file
  jq -n --arg t "$token" --arg d "$DOMAIN" --arg owner "$OWNER_EMAIL" \
     --argjson created "$created" --argjson expires_at "$expire_token" \
     '{token:$t,domain:$d,owner:$owner,created:$created,expires_at:$expires_at,status:"PENDING"}' \
     >> "$DB_FILE"

  approval_link="${APPROVAL_BASE_URL}?token=${token}"
  subject="[ACTION REQUIRED] Approve SSL renewal for ${DOMAIN}"
  body_html="<html><body><p>Automated SSL renewal for <b>${DOMAIN}</b> requires approval.</p><p><a href='${approval_link}'>Click to approve</a> (valid 48 hours)</p></body></html>"

  # create safe SES message JSON
  MSGFILE=$(mktemp /tmp/sesmsg.XXXXXX.json)
  jq -n --arg subj "$subject" --arg html "$body_html" \
     '{Subject: {Data: $subj, Charset: "utf-8"}, Body: {Html: {Data: $html, Charset: "utf-8"}}}' \
     > "$MSGFILE"
  trap 'rm -f "${MSGFILE}"' EXIT

  # ensure app DB and insert token so approval server can find it immediately
  _init_app_db
  if ! sqlite3 "$APP_DB" "INSERT OR REPLACE INTO approvals (token,domain,owner,created,expires_at,status) VALUES ('$token','$DOMAIN','$OWNER_EMAIL',$created,$expire_token,'PENDING');" >/dev/null 2>&1; then
    echo "$(date): Warning: failed to write token to $APP_DB (continuing; token is in $DB_FILE)" >&2
  else
    echo "$(date): Inserted token into approval DB: $APP_DB (token $token)"
  fi

  # Send the email and report result. Use file:// to avoid quoting/parsing issues.
  if aws ses send-email \
       --region us-east-1 \
       --from "$SENDER_EMAIL" \
       --destination "ToAddresses=${OWNER_EMAIL}" \
       --message file://"$MSGFILE"; then
    echo "$(date): Sent approval email to $OWNER_EMAIL for $DOMAIN (token $token)"
  else
    echo "$(date): Failed to send approval email for $DOMAIN (token $token)" >&2
    # keep the record in $DB_FILE so you can inspect later
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

exit 0

