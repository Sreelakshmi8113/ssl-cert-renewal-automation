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
                ansiblePlaybook credentialsId: 'your-ansible-cred-id', playbook: 'deploy_cert.yml'
            }
        }
    }
}

