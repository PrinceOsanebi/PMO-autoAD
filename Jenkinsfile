pipeline {
    agent any
    tools {
        terraform 'terraform'
    }
    parameters {
        choice(name: 'action', choices: ['apply', 'destroy'], description: 'Select the action to perform')
    }
    triggers {
        pollSCM('* * * * *') // Runs every minute
    }
    environment {
        SLACKCHANNEL = 'D08B6M53SHH'
        SLACKCREDENTIALS = credentials('slack')
    }
    
    stages {
        stage('IAC Scan') {
            steps {
                script {
                    sh 'pip install pipenv'
                    sh 'pipenv run pip install checkov'
                    def checkovStatus = sh(script: 'pipenv run checkov -d . -o cli --output-file checkov-results.txt --quiet', returnStatus: true)
                    junit allowEmptyResults: true, testResults: 'checkov-results.txt' 
                    // if (checkovStatus != 0) {
                    //     error 'Checkov found some issues'
                    // }
                }
            }
        }
        stage('Terraform Init') {  // Fixed spelling
            steps {
                sh 'terraform init'
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
                sh 'terraform plan'
            }
        }
        stage('Terraform action') {
            steps {
                script {
                    sh "terraform ${action} -auto-approve"
                }
            }
        }
    }
    post {
        always {
            script {
                slackSend(
                    channel: SLACKCHANNEL,
                    color: currentBuild.result == 'SUCCESS' ? 'good' : 'danger',
                    message: "Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]' (${env.BUILD_URL}) has been completed."
                )
            }
        }
        failure {
            slackSend(
                channel: SLACKCHANNEL,
                color: 'danger',
                message: "Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]' has failed. Check console output at ${env.BUILD_URL}."
            )
        }
        success {
            slackSend(
                channel: SLACKCHANNEL,
                color: 'good',
                message: "Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]' completed successfully. Check console output at ${env.BUILD_URL}."
            )
        }
    }
}




// pipeline {
//     agent any

//     tools {
//         terraform 'terraform'
//     }

//     parameters {
//         choice(
//             name: 'action',
//             choices: ['apply', 'destroy'],
//             description: 'Select the action to perform (manual runs only)'
//         )
//     }

//     triggers {
//         // Runs at 6:00 AM and 7:30 PM Monday to Saturday (Europe/Dublin timezone)
//         cron('0 6 * * 1-6\n30 19 * * 1-6')
//     }

//     environment {
//         SLACKCHANNEL = 'D08B6M53SHH'
//         SLACKCREDENTIALS = credentials('slack')
//     }

//     stages {

//         stage('Determine Action') {
//             steps {
//                 script {
//                     def scheduledAction = null
//                     def now = new Date()
//                     def tz = TimeZone.getTimeZone('Europe/Dublin')
//                     def hour = now.format('H', tz) as Integer
//                     def minute = now.format('m', tz) as Integer
//                     def dayOfWeek = now.format('u', tz) as Integer // 1=Monday ... 7=Sunday

//                     if (dayOfWeek >= 1 && dayOfWeek <= 6) {  // Monday to Saturday
//                         if (hour == 6 && minute == 0) {
//                             scheduledAction = 'apply'
//                         } else if (hour == 19 && minute == 30) {  // 7:30 PM
//                             scheduledAction = 'destroy'
//                         }
//                     }

//                     if (currentBuild.rawBuild.getCause(hudson.triggers.TimerTrigger.TimerTriggerCause) != null) {
//                         if (scheduledAction == null) {
//                             error("Build triggered by cron but no matching scheduled action found.")
//                         } else {
//                             env.ACTION = scheduledAction
//                             echo "Cron trigger detected. Using scheduled action: ${env.ACTION}"
//                         }
//                     } else {
//                         env.ACTION = params.action
//                         echo "Manual trigger detected. Using user-selected action: ${env.ACTION}"
//                     }
//                 }
//             }
//         }

//         stage('IAC Scan') {
//             steps {
//                 script {
//                     sh 'pip install pipenv'
//                     sh 'pipenv run pip install checkov'
//                     def checkovStatus = sh(
//                         script: 'pipenv run checkov -d . -o cli --output-file checkov-results.txt --quiet',
//                         returnStatus: true
//                     )
//                     junit allowEmptyResults: true, testResults: 'checkov-results.txt'
//                 }
//             }
//         }

//         stage('Terraform Init') {
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
//                 sh "terraform plan -out=tfplan"
//             }
//         }

//         stage('Terraform action') {
//             steps {
//                 script {
//                     sh "terraform ${env.ACTION} -auto-approve"
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
//                     message: "Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]' (${env.BUILD_URL}) completed with action ${env.ACTION}."
//                 )
//             }
//         }

//         failure {
//             slackSend(
//                 channel: SLACKCHANNEL,
//                 color: 'danger',
//                 message: "Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]' failed. Check console output at ${env.BUILD_URL}."
//             )
//         }

//         success {
//             slackSend(
//                 channel: SLACKCHANNEL,
//                 color: 'good',
//                 message: "Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]' succeeded with action ${env.ACTION}. Check console output at ${env.BUILD_URL}."
//             )
//         }
//     }
// }
