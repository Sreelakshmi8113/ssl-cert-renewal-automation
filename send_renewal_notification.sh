#!/bin/bash
set -euo pipefail
SENDER="sreejayaksaji@gmail.com"
OWNER="sreelakshmiksaji492@gmail.com"
REGION="us-east-1"
DOMAIN="ssl-automation.duckdns.org"
SUBJECT="[INFO] SSL renewed for ${DOMAIN}"
BODY_HTML="<html><body><p>The SSL certificate for <b>${DOMAIN}</b> has been renewed and deployed.</p></body></html>"
MSGFILE=$(mktemp /tmp/renew_msg.XXXXXX.json)
jq -n --arg subj "$SUBJECT" --arg html "$BODY_HTML" \
  '{Subject:{Data:$subj,Charset:"utf-8"},Body:{Html:{Data:$html,Charset:"utf-8"}}}' > "$MSGFILE"
aws ses send-email --region "$REGION" --from "$SENDER" --destination "ToAddresses=${OWNER}" --message file://"$MSGFILE"
rm -f "$MSGFILE"
