// pipeline {
//     agent any
//     tools {
//         terraform 'terraform'
//     }
//     parameters {
//         choice(name: 'action', choices: ['apply', 'destroy'], description: 'Select the action to perform')
//     }
//     triggers {
//         pollSCM('* * * * *') // Runs every minute
//     }
//     environment {
//         SLACKCHANNEL = 'D08B6M53SHH'
//         SLACKCREDENTIALS = credentials('slack')
//     }
    
//     stages {
//         stage('IAC Scan') {
//             steps {
//                 script {
//                     sh 'pip install pipenv'
//                     sh 'pipenv run pip install checkov'
//                     def checkovStatus = sh(script: 'pipenv run checkov -d . -o cli --output-file checkov-results.txt --quiet', returnStatus: true)
//                     junit allowEmptyResults: true, testResults: 'checkov-results.txt' 
//                     // if (checkovStatus != 0) {
//                     //     error 'Checkov found some issues'
//                     // }
//                 }
//             }
//         }
//         stage('Terraform Init') {  // Fixed spelling
//             steps {
//                 sh 'terraform init'
//             }
//         }
//         stage('Terraform format') {
//             steps {
//                 sh 'terraform fmt --recursive'
//             }
//         }
//         stage('Terraform validate') {
//             steps {
//                 sh 'terraform validate'
//             }
//         }
//         stage('Terraform plan') {
//             steps {
//                 sh 'terraform plan'
//             }
//         }
//         stage('Terraform action') {
//             steps {
//                 script {
//                     sh "terraform ${action} -auto-approve"
//                 }
//             }
//         }
//     }
//     post {
//         always {
//             script {
//                 slackSend(
//                     channel: SLACKCHANNEL,
//                     color: currentBuild.result == 'SUCCESS' ? 'good' : 'danger',
//                     message: "Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]' (${env.BUILD_URL}) has been completed."
//                 )
//             }
//         }
//         failure {
//             slackSend(
//                 channel: SLACKCHANNEL,
//                 color: 'danger',
//                 message: "Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]' has failed. Check console output at ${env.BUILD_URL}."
//             )
//         }
//         success {
//             slackSend(
//                 channel: SLACKCHANNEL,
//                 color: 'good',
//                 message: "Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]' completed successfully. Check console output at ${env.BUILD_URL}."
//             )
//         }
//     }
// }






pipeline {
    agent any // Run the pipeline on any available Jenkins agent

    tools {
        terraform 'terraform' // Use the Terraform installation configured in Jenkins global tools
    }

    parameters {
        // Dropdown menu for manual runs to choose 'apply' or 'destroy'
        choice(
            name: 'action',
            choices: ['apply', 'destroy'],
            description: 'Select the action to perform (manual runs only)'
        )
    }

    triggers {
        // Schedule to run at 6:00 AM and 7:30 PM Monday–Saturday (Europe/Dublin time)
        cron('0 6 * * 1-6\n30 19 * * 1-6')
    }

    environment {
        SLACKCHANNEL = 'D08B6M53SHH' // Slack channel ID for notifications
        SLACKCREDENTIALS = credentials('slack') // Slack credentials stored securely in Jenkins
    }

    stages {

        stage('Determine Action') {
            steps {
                script {
                    def scheduledAction = null
                    def now = new Date()
                    def tz = TimeZone.getTimeZone('Europe/Dublin')
                    def hour = now.format('H', tz) as Integer
                    def minute = now.format('m', tz) as Integer
                    def dayOfWeek = now.format('u', tz) as Integer

                    // If between Monday and Saturday, check scheduled times
                    if (dayOfWeek >= 1 && dayOfWeek <= 6) {
                        if (hour == 6 && minute == 0) {
                            scheduledAction = 'apply' // Morning run → deploy/apply infrastructure
                        } else if (hour == 19 && minute == 30) {
                            scheduledAction = 'destroy' // Evening run → tear down infrastructure
                        }
                    }

                    def causes = currentBuild.getBuildCauses()
                    def isTimerTriggered = causes.any { it._class?.contains('TimerTriggerCause') }

                    if (isTimerTriggered) {
                        if (scheduledAction == null) {
                            error("Build triggered by cron but no matching scheduled action found.")
                        } else {
                            env.ACTION = scheduledAction
                            echo "Cron trigger detected. Using scheduled action: ${env.ACTION}"
                        }
                    } else {
                        env.ACTION = params.action
                        echo "Manual trigger detected. Using user-selected action: ${env.ACTION}"
                    }
                }
            }
        }

        stage('IAC Scan') {
            steps {
                script {
                    sh '''
                        # Install dependencies
                        pip install --user pipenv
                        pipenv run pip install checkov

                        # Run Checkov scan with JUnit output
                        pipenv run checkov -d . \
                            --output junitxml \
                            --output-file checkov-results.xml || true
                    '''

                    // Publish Checkov results in Jenkins
                    junit allowEmptyResults: true, testResults: 'checkov-results.xml'
                }
            }
        }

        stage('Terraform Init') {
            steps {
                sh '''
                    echo "Initializing Terraform..."
                    terraform init || exit 1
                '''
            }
        }

        stage('Terraform format') {
            steps {
                sh 'terraform fmt --recursive'
            }
        }

        stage('Terraform validate') {
            steps {
                sh 'terraform validate'
            }
        }

        stage('Terraform plan') {
            steps {
                sh 'terraform plan -out=tfplan'
            }
        }

        stage('Terraform action') {
            steps {
                script {
                    sh "terraform ${env.ACTION} -auto-approve"
                }
            }
        }
    }

    post {
        always {
            script {
                // Send notification to Slack regardless of build result
                slackSend(
                    channel: SLACKCHANNEL,
                    color: currentBuild.result == 'SUCCESS' ? 'good' : 'danger',
                    message: "Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]' (${env.BUILD_URL}) completed with action ${env.ACTION}."
                )
            }
        }

        failure {
            // Notify Slack on failure
            slackSend(
                channel: SLACKCHANNEL,
                color: 'danger',
                message: "Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]' failed. Check console output at ${env.BUILD_URL}."
            )
        }

        success {
            // Notify Slack on success
            slackSend(
                channel: SLACKCHANNEL,
                color: 'good',
                message: "Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]' succeeded with action ${env.ACTION}. Check console output at ${env.BUILD_URL}."
            )
        }
    }
}
