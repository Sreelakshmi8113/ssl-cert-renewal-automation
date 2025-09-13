pipeline {
    agent any

    stages {
        stage('Check SSL Expiry') {
            steps {
                sh 'python3 ssl_checker.py'
            }
        }
        stage('Deploy Certificate') {
            steps {
                sh '/home/ec2-user/.local/bin/ansible-playbook deploy_cert.yml'
            }
        }
    }
}

