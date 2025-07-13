pipeline {
    agent any

    tools {
        terraform 'terraform'    # Terraform installation configured in Jenkins
    }

    parameters {
        choice(
            name: 'action',
            choices: ['apply', 'destroy'],
            description: 'Select the action to perform (manual runs only)'
        )
    }

    triggers {
        cron('0 6 * * 1-6')     # 6:00 AM Monday to Saturday - scheduled apply
        cron('30 7 * * 1-6')    # 7:30 AM Monday to Saturday - scheduled destroy
    }

    environment {
        SLACKCHANNEL = 'D08B6M53SHH'            # Slack channel for notifications
        SLACKCREDENTIALS = credentials('slack') # Slack credentials stored in Jenkins
    }

    stages {

        stage('Determine Action') {
            steps {
                script {
                    # ----------------------------------------------
                    # Determine Scheduled Action Based on Current Time
                    # ----------------------------------------------
                    def scheduledAction = null
                    def now = new Date()

                    # Get current time details in Europe/London timezone
                    def hour = now.format('H', TimeZone.getTimeZone('Europe/London')) as Integer
                    def minute = now.format('m', TimeZone.getTimeZone('Europe/London')) as Integer
                    def dayOfWeek = now.format('u', TimeZone.getTimeZone('Europe/London')) as Integer  # 1=Mon ... 7=Sun

                    # Set scheduled action if Mon-Sat and matching times
                    if (dayOfWeek >= 1 && dayOfWeek <= 6) {
                        if (hour == 6 && minute == 0) {
                            scheduledAction = 'apply'      # Scheduled apply at 6:00 AM
                        } else if (hour == 7 && minute == 30) {
                            scheduledAction = 'destroy'    # Scheduled destroy at 7:30 AM
                        }
                    }

                    # ----------------------------------------------
                    # Determine If Triggered by Cron or Manual
                    # ----------------------------------------------
                    if (currentBuild.rawBuild.getCause(hudson.triggers.TimerTrigger.TimerTriggerCause) != null) {
                        # Triggered by cron job
                        if (scheduledAction == null) {
                            error("Build triggered by cron but no matching scheduled action found.")
                        } else {
                            env.ACTION = scheduledAction
                            echo "Cron trigger detected. Using scheduled action: ${env.ACTION}"
                        }
                    } else {
                        # Manual trigger, use user-selected action parameter
                        env.ACTION = params.action
                        echo "Manual trigger detected. Using user-selected action: ${env.ACTION}"
                    }
                }
            }
        }

        stage('IAC Scan') {
            steps {
                script {
                    # ----------------------------------------------
                    # Infrastructure as Code Security Scan using Checkov
                    # ----------------------------------------------
                    sh 'pip install pipenv'
                    sh 'pipenv run pip install checkov'

                    def checkovStatus = sh(
                        script: 'pipenv run checkov -d . -o cli --output-file checkov-results.txt --quiet',
                        returnStatus: true
                    )

                    # Publish results even if empty
                    junit allowEmptyResults: true, testResults: 'checkov-results.txt'
                }
            }
        }

        stage('Terraform Init') {
            steps {
                # ----------------------------------------------
                # Initialize Terraform workspace
                # ----------------------------------------------
                sh 'terraform init'
            }
        }

        stage('Terraform format') {
            steps {
                # ----------------------------------------------
                # Format Terraform configuration files
                # ----------------------------------------------
                sh 'terraform fmt --recursive'
            }
        }

        stage('Terraform validate') {
            steps {
                # ----------------------------------------------
                # Validate Terraform files for correctness
                # ----------------------------------------------
                sh 'terraform validate'
            }
        }

        stage('Terraform plan') {
            steps {
                # ----------------------------------------------
                # Generate Terraform execution plan
                # ----------------------------------------------
                sh "terraform plan -out=tfplan"
            }
        }

        stage('Terraform action') {
            steps {
                script {
                    # ----------------------------------------------
                    # Apply or Destroy Terraform infra based on ACTION
                    # ----------------------------------------------
                    sh "terraform ${env.ACTION} -auto-approve"
                }
            }
        }
    }

    post {
        always {
            script {
                # ----------------------------------------------
                # Send Slack notification for any build completion
                # ----------------------------------------------
                slackSend(
                    channel: SLACKCHANNEL,
                    color: currentBuild.result == 'SUCCESS' ? 'good' : 'danger',
                    message: "Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]' (${env.BUILD_URL}) completed with action ${env.ACTION}."
                )
            }
        }

        failure {
            # ----------------------------------------------
            # Send Slack notification if build fails
            # ----------------------------------------------
            slackSend(
                channel: SLACKCHANNEL,
                color: 'danger',
                message: "Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]' failed. Check console output at ${env.BUILD_URL}."
            )
        }

        success {
            # ----------------------------------------------
            # Send Slack notification if build succeeds
            # ----------------------------------------------
            slackSend(
                channel: SLACKCHANNEL,
                color: 'good',
                message: "Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]' succeeded with action ${env.ACTION}. Check console output at ${env.BUILD_URL}."
            )
        }
    }
} 