import ssl, socket, datetime

hostname = 'yourdomain.com'  # Replace with your actual domain

context = ssl.create_default_context()
with socket.create_connection((hostname, 443)) as sock:
    with context.wrap_socket(sock, server_hostname=hostname) as ssock:
        cert = ssock.getpeercert()
        expiry = datetime.datetime.strptime(cert['notAfter'], '%b %d %H:%M:%S %Y %Z')
        print(f"SSL Certificate for {hostname} expires on {expiry}")

