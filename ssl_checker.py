import ssl
import socket
import boto3
from datetime import datetime, timezone

# ---------- Configuration ----------
hostname = "github.com"
port = 443
sender_email = "sreejayaksaji@gmail.com"  # ✅ must be verified in SES
recipient_emails = ["sreelakshmiksaji492@gmail.com"]  # add recipients here
region = "us-east-1"  # ✅ Oregon (your SES region)
# -----------------------------------

def check_ssl_expiry(hostname, port=443):
    context = ssl.create_default_context()
    with socket.create_connection((hostname, port)) as sock:
        with context.wrap_socket(sock, server_hostname=hostname) as ssock:
            cert = ssock.getpeercert()
            expiry_date = datetime.strptime(cert['notAfter'], '%b %d %H:%M:%S %Y %Z')
            days_left = (expiry_date - datetime.now(timezone.utc)).days

            print(f"✅ SSL Certificate for {hostname} expires on {expiry_date} ({days_left} days left)")
            if days_left < 30:
                print("⚠️ Certificate expiring soon! Sending email alert...")
                send_email_alert(hostname, expiry_date, days_left)
            else:
                print("✅ Certificate is valid for more than 30 days. No email alert sent")

def send_email_alert(hostname, expiry_date, days_left):
    ses_client = boto3.client("ses", region_name=region)

    subject = f"⚠️ SSL Certificate Expiry Alert for {hostname}"
    body = (f"The SSL certificate for {hostname} is expiring soon!\n\n"
            f"📅 Expiry Date: {expiry_date}\n"
            f"⏳ Days Remaining: {days_left}\n\n"
            "Please plan downtime and renew the certificate before expiration.")

    for recipient in recipient_emails:
        response = ses_client.send_email(
            Source=sender_email,
            Destination={"ToAddresses": [recipient]},
            Message={
                "Subject": {"Data": subject},
                "Body": {"Text": {"Data": body}}
            }
        )
        print(f"📨 Email sent to {recipient}: Message ID {response['MessageId']}")

if __name__ == "__main__":
    check_ssl_expiry(hostname, port)

