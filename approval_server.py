#!/usr/bin/env python3
# approval_server.py — Flask app for SSL approval + Jenkins trigger

import os, sqlite3, time, requests
from flask import Flask, request, render_template_string

DB_PATH = os.path.join(os.path.dirname(__file__), 'approvals.db')
JENKINS_URL = os.environ.get('JENKINS_URL', 'http://3.230.205.216:8080')
JENKINS_USER = os.environ.get('JENKINS_USER', 'sreelakshmi')
JENKINS_API_TOKEN = os.environ.get('JENKINS_API_TOKEN', '')
JENKINS_JOB = os.environ.get('JENKINS_JOB', 'ssl-automation-deploy')
JENKINS_TRIGGER_TOKEN = os.environ.get('JENKINS_TRIGGER_TOKEN', 'ssl_approval_trigger_123')

app = Flask(__name__)

def init_db():
    conn = sqlite3.connect(DB_PATH)
    conn.execute('''CREATE TABLE IF NOT EXISTS approvals
                    (token TEXT PRIMARY KEY, domain TEXT, owner TEXT,
                     created INTEGER, expires_at INTEGER, status TEXT)''')
    conn.commit()
    conn.close()

def get_record(token):
    conn = sqlite3.connect(DB_PATH)
    row = conn.execute('SELECT token, domain, owner, created, expires_at, status FROM approvals WHERE token=?', (token,)).fetchone()
    conn.close()
    return row

def set_status(token, status):
    conn = sqlite3.connect(DB_PATH)
    conn.execute('UPDATE approvals SET status=? WHERE token=?', (status, token))
    conn.commit()
    conn.close()

def trigger_jenkins():
    crumb_url = f"{JENKINS_URL.rstrip('/')}/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,\":\",//crumb)"
    r = requests.get(crumb_url, auth=(JENKINS_USER, JENKINS_API_TOKEN), timeout=10)
    if r.status_code != 200:
        return False, f"crumb error {r.status_code}"
    hdr_name, hdr_val = r.text.split(':',1)
    build_url = f"{JENKINS_URL.rstrip('/')}/job/{JENKINS_JOB}/build"
    if JENKINS_TRIGGER_TOKEN:
        build_url = f"{build_url}?token={JENKINS_TRIGGER_TOKEN}"
    r2 = requests.post(build_url, auth=(JENKINS_USER, JENKINS_API_TOKEN), headers={hdr_name: hdr_val}, timeout=15)
    return (r2.status_code in (200,201,302), r2.status_code, r2.text)

@app.route('/approve')
def approve():
    token = request.args.get('token')
    if not token:
        return "Missing token", 400
    row = get_record(token)
    if not row:
        return "Token not found", 404
    token, domain, owner, created, expires_at, status = row
    now = int(time.time())
    if now > expires_at:
        set_status(token, 'EXPIRED')
        return "Token expired", 410
    if status != 'PENDING':
        return f"Token already {status}", 409
    set_status(token, 'APPROVED')
    ok, code, text = trigger_jenkins()
    if not ok:
        set_status(token, 'TRIGGER_FAILED')
        return f"Failed to trigger Jenkins: {code}", 500
    return render_template_string("<h3>✅ Approved — Jenkins job triggered.</h3><p>Thank you.</p>")

if __name__ == '__main__':
    init_db()
    app.run(host='127.0.0.1', port=5000)
