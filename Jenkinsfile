pipeline {
    agent any  // Use any available Jenkins agent

    tools {
        terraform 'terraform'  // Use pre-installed Terraform tool named 'terraform'
    }

    parameters {
        choice(name: 'action', choices: ['apply', 'destroy'], description: 'Select the action to perform')  // User selects Terraform action
    }

    triggers {
        pollSCM('* * * * *')  // Poll source control every minute for changes
    }

    environment {
        SLACKCHANNEL      = 'D08B6M53SHH'                    // Slack channel ID to send notifications
        SLACKCREDENTIALS  = credentials('slack')             // Slack credentials from Jenkins
        VAULT_TOKEN       = credentials('VAULT_TOKEN')       // Vault token pulled securely from Jenkins credentials
        VAULT_ADDR        = 'https://vault.pmolabs.space'    // Vault server URL
    }

    stages {
        stage('IAC Scan') {  // Scan Terraform code for security issues using Checkov
            steps {
                script {
                    sh 'pip install pipenv'  // Install pipenv
                    sh 'pipenv run pip install checkov'  // Install Checkov in pipenv environment

                    // Run Checkov and capture exit status
                    def checkovStatus = sh(
                        script: 'pipenv run checkov -d . -o cli --output-file checkov-results.txt --quiet',
                        returnStatus: true
                    )

                    junit allowEmptyResults: true, testResults: 'checkov-results.txt'  // Archive results (format may not be JUnit-compatible)

                    // Uncomment below to fail build if Checkov detects issues
                    // if (checkovStatus != 0) {
                    //     error 'Checkov found issues.'
                    // }
                }
            }
        }

        stage('Terraform Init') {  // Initialize Terraform backend and providers
            steps {
                sh 'terraform init'
            }
        }

        stage('Terraform Format') {  // Format Terraform code according to standard
            steps {
                sh 'terraform fmt --recursive'
            }
        }

        stage('Terraform Validate') {  // Validate Terraform configuration syntax
            steps {
                sh 'terraform validate'
            }
        }

        stage('Terraform Plan') {  // Generate and show execution plan
            steps {
                withEnv(["TF_VAR_vault_token=${env.VAULT_TOKEN}"]) {  // Pass Vault token as Terraform variable
                    sh 'terraform plan'
                }
            }
        }

        stage('Terraform Action') {  // Apply or destroy infrastructure based on user selection
            steps {
                withEnv(["TF_VAR_vault_token=${env.VAULT_TOKEN}"]) {  // Pass Vault token as Terraform variable
                    sh "terraform ${params.action} -auto-approve"
                }
            }
        }
    }

    post {
        always {
            script {
                // Send notification to Slack after job completion (any result)
                slackSend(
                    channel: SLACKCHANNEL,
                    color: currentBuild.result == 'SUCCESS' ? 'good' : 'danger',
                    message: "Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]' (${env.BUILD_URL}) has been completed."
                )
            }
        }

        failure {
            // Send Slack alert if job failed
            slackSend(
                channel: SLACKCHANNEL,
                color: 'danger',
                message: "Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]' has failed. Check console output at ${env.BUILD_URL}."
            )
        }

        success {
            // Send Slack message on success
            slackSend(
                channel: SLACKCHANNEL,
                color: 'good',
                message: "Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]' completed successfully. Check console output at ${env.BUILD_URL}."
            )
        }
    }
}
