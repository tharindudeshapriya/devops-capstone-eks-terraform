# Phase 2: Continuous Integration (CI) Pipeline

The Continuous Integration (CI) pipeline is fully automated via Jenkins and is triggered dynamically by GitHub Webhooks upon code commits. This ensures that every code change is rigorously tested, scanned for vulnerabilities, and packaged before it ever reaches the deployment phase.

## Pipeline Stages & Architecture

![Jenkins CI/CD Jobs](./images/jenkins%20ci%20cd%20jobs.png)

Here is a detailed breakdown of the enterprise-grade CI workflow implemented in this project:

### 1. Source Code Checkout
Retrieves the latest Java Spring Boot application code from the source repository. This guarantees that the pipeline is always building the absolute latest commit triggered by the developer.

**Pipeline Snippet:**
```groovy
stage('Git Checkout') {
    steps {
        git branch: 'main', url: 'https://github.com/tharindudeshapriya/devops-capstone-app.git'
    }
}
```

### 2. Compilation and Testing (Maven)
Compiles the source code (`mvn compile`) and executes the developer's unit tests (`mvn test`). Pipeline execution is strictly halted upon test failure to prevent the propagation of erroneous or broken code into later stages of the pipeline.

**Pipeline Snippet:**
```groovy
stage('Compile') {
    steps {
        sh 'mvn compile'
    }
}

stage('Test') {
    steps {
        sh 'mvn test'
    }
}
```

### 3. Static Configuration Analysis (Trivy FS)
Scans the repository file system using Aqua Security's Trivy. This stage identifies hardcoded secrets, leaked API keys, and structural misconfigurations in the codebase before any artifacts are built.

**Pipeline Snippet:**
```groovy
stage('Trivy FS Scan') {
    steps {
        sh 'trivy fs --format table -o fs-report.html .'
    }
}
```

### 4. Static Application Security Testing (SonarQube)
Analyzes code quality, technical debt, and security flaws. The pipeline enforces a strict Quality Gate, pausing the build to wait for SonarQube's webhook response. It requires zero critical vulnerabilities to proceed to the build phase.

**Pipeline Snippet:**
```groovy
stage('Code Quality Analysis') {
    steps {
        withSonarQubeEnv('sonar') {
            // This MUST remain on a single line to prevent bash trailing space errors!
            sh ''' $SCANNER_HOME/bin/sonar-scanner -Dsonar-projectName=GCBank -Dsonar.projectKey=GCBank -Dsonar.java.binaries=target '''
        }
    }
}

![SonarQube Analysis Report](./images/Sonarqube%20report.png)

stage('Quality Gate Check') {
    steps {
        timeout(time: 1, unit: 'HOURS') {
            waitForQualityGate abortPipeline: false, credentialsId: 'sonar-token'
        }
    }
}
```

### 5. Artifact Build and Publication
Packages the application into a deployable `.jar` artifact (`mvn package`) and securely publishes it (`mvn deploy`) to the Sonatype Nexus artifact repository for immutable version control.

**Pipeline Snippet:**
```groovy
stage('Build') {
    steps {
        sh 'mvn package'
    }
}

stage('Publish Artifacts') {
    steps {
        // Ensure your Jenkins Managed File ID is exactly 'tharindu'
        withMaven(globalMavenSettingsConfig: 'tharindu', maven: 'maven3', mavenSettingsConfig: '', traceability: true) {
            sh 'mvn deploy'    
        }
    }
}
```

![Nexus Artifact Repository](./images/nexus%20artifacts.png)

### 6. Containerization (Docker)
Builds the application's Docker container image using the newly compiled `.jar` file and the Dockerfile. It then pushes the tagged image to DockerHub (`tmdeshapriya/bankapp`). The image tag is dynamically generated using the Jenkins `BUILD_NUMBER` (e.g., `v15`).

**Pipeline Snippet:**
```groovy
stage('Build and Tag Docker Images') {
    steps {
        sh "docker build -t tmdeshapriya/bankapp:${IMAGE_TAG} ."
    }
}

stage('Push Docker Images') {
    steps {
        script {
            withDockerRegistry(credentialsId: 'docker-cred') {
                sh "docker push tmdeshapriya/bankapp:$IMAGE_TAG"
            }
        }
    }
}
```

![Docker Hub Images](./images/docker%20hub%20images.png)

### 7. Container Vulnerability Scanning (Trivy)
Scans the generated Docker image for Common Vulnerabilities and Exposures (CVEs) found in the base operating system layers and aggregates a comprehensive HTML security report.

**Pipeline Snippet:**
```groovy
stage('Trivy Image Scan') {
    steps {
        sh 'trivy image --format table -o image-report.html tmdeshapriya/bankapp:$IMAGE_TAG'
    }
}
```

### 8. GitOps Manifest Update
Instead of Jenkins deploying directly to Kubernetes, it practices GitOps. The pipeline clones the Continuous Deployment (CD) repository (`devops-capstone-k8s-manifests`), uses `sed` to update the Kubernetes deployment manifests with the newly built Docker image tag, and automatically commits and pushes the changes back to GitHub.

**Pipeline Snippet:**
```groovy
stage('Update manifests file in CD repo') {
    steps {
        script {
            cleanWs()
            sh '''
            # Clone your specific CD repository
            git clone https://github.com/tharindudeshapriya/devops-capstone-k8s-manifests.git
            
            cd devops-capstone-k8s-manifests
            
            # Search for the old tag and replace it with the new build tag
            sed -i "s|tmdeshapriya/bankapp:.*|tmdeshapriya/bankapp:${IMAGE_TAG}|" k8s/Manifest.yaml

            echo "image tag updated"
            cat k8s/Manifest.yaml

            # commit and push the changes
            git config user.name "tharindudeshapriya"
            git config user.email "tmdeshapriya@gmail.com"
            git add k8s/Manifest.yaml
            git commit -m "image tag updated to ${IMAGE_TAG}"
            '''

            withCredentials([usernamePassword(credentialsId: 'github-cred', usernameVariable: 'GIT_USER', passwordVariable: 'GIT_PASS')]) {
            sh '''
            cd devops-capstone-k8s-manifests
            git remote set-url origin https://$GIT_USER:$GIT_PASS@github.com/tharindudeshapriya/devops-capstone-k8s-manifests.git
            git push origin main
            '''
            }
        }
    }
}
```

### 9. Status Notification
Dispatches an automated email to the engineering team detailing the pipeline execution status (Success/Failure), and attaches the Trivy vulnerability scan HTML report to keep the DevSecOps team informed.

**Pipeline Snippet:**
```groovy
post {
    always {
        script {
            def jobName = env.JOB_NAME
            def buildNumber = env.BUILD_NUMBER
            def pipelineStatus = currentBuild.result ?: 'UNKNOWN'
            def bannerColor = pipelineStatus.toUpperCase() == 'SUCCESS' ? 'green' : 'red'

            def body = """
                <html>
                    <body>
                        <div style="border: 4px solid ${bannerColor}; padding: 10px;">
                            <h2>${jobName} - Build #${buildNumber}</h2>
                            <div style="background-color: ${bannerColor}; padding: 10px;">
                                <h3 style="color: white;">Pipeline Status: ${pipelineStatus.toUpperCase()}</h3>
                            </div>
                            <p>Check the <a href="${env.BUILD_URL}">Console Output</a> for more details.</p>
                        </div>
                    </body>
                </html>
            """

            emailext(
                subject: "${jobName} - Build #${buildNumber} - ${pipelineStatus.toUpperCase()}",
                body: body,
                to: 'tmdeshapriya@gmail.com',
                from: 'tmdeshapriya@gmail.com',
                replyTo: 'tmdeshapriya@gmail.com',
                mimeType: 'text/html',
                attachmentsPattern: 'fs-report.html'
            )
        }
    }
}
```

## Step 1: Jenkins Server Preparation

### A. Configure Docker Permissions

Since Jenkins will need to build Docker images inside our pipeline, we must ensure Docker is installed on the Jenkins host VM and that the `jenkins` user has the correct permissions.

1. SSH into the Jenkins VM.
2. Grant Docker permissions to the `jenkins` user by adding it to the `docker` group:
   ```bash
   sudo usermod -aG docker jenkins
   ```
   *(The `-aG` flag means append to group so we don't remove existing groups).*
3. Restart the Jenkins service to apply the group changes:
   ```bash
   sudo systemctl restart jenkins
   ```

> **Pro Tip:** If the Jenkins user’s group change isn’t applied immediately, it’s because Jenkins runs as a service, and the session needs a restart to pick up the new Docker daemon socket permissions.

### B. Install Trivy (Security Scanner)

Trivy must be installed natively on the Ubuntu server so the Jenkins pipeline can execute `trivy fs` and `trivy image` commands. Run these commands sequentially on the Jenkins VM:

```bash
# 1. Install prerequisites
sudo apt-get install wget apt-transport-https gnupg lsb-release -y

# 2. Add the Trivy repository GPG key
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -

# 3. Add the official Trivy repository to your sources list
echo deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main | sudo tee -a /etc/apt/sources.list.d/trivy.list

# 4. Update package lists and install Trivy
sudo apt-get update
sudo apt-get install trivy -y

# 5. Verify the installation
trivy --version
```

## Step 2: Install Jenkins Plugins

Log into the Jenkins Dashboard, navigate to **Manage Jenkins → Plugins → Available Plugins**, and install the following essential plugins:

* **SonarQube Scanner** (Integrates SonarQube analysis into Jenkins)
* **Config File Provider** (Manages external configuration files like Maven `settings.xml`)
* **Maven Integration** (Essential for Maven builds)
* **Docker Pipeline** (Allows running Docker commands inside the Jenkinsfile)
* **Kubernetes Suite** (Install Kubernetes, Kubernetes CLI, Kubernetes Credentials, Kubernetes Pipeline, and Kubernetes Client API)
* **Generic Webhook Trigger** (For triggering the pipeline automatically via GitHub)
* **Email Extension** (For sending advanced HTML emails)

## Step 3: Global Tools & System Configuration

### 1. Configuring Tools (Manage Jenkins → Tools)
* **Maven:** Click Add Maven. Name it exactly `maven3` (this matches our Jenkinsfile) and select a stable version to install automatically.
* **SonarQube Scanner:** Click Add SonarQube Scanner. Name it exactly `sonar-scanner` and select the latest stable version.

### 2. SonarQube Server Configuration (Manage Jenkins → System)
* First, generate a token from your SonarQube UI: **Admin → Security → Users → Generate Token**.
* In Jenkins, go to **Manage Jenkins → Credentials** and add this token as a `Secret Text` credential with the ID `sonar-token`.
* Go to **Manage Jenkins → System**, scroll to SonarQube servers, click Add SonarQube, name it `sonar`, enter your Server URL (`http://<SonarQube-IP>:9000`), and attach the `sonar-token` credential.

### 3. Nexus Credentials (Manage Jenkins → Managed Files)
* Add a Global Maven `settings.xml` configuration.
* Set the ID to `tharindu`.
* Add the `<server>` block containing your Nexus admin username and password so Maven can authenticate when running `mvn deploy`.

### 4. Global Credentials Setup
Add the remaining required credentials under **Manage Jenkins → Credentials → Global**:
* `docker-cred`: Username with password (Your DockerHub credentials).
* `github-cred`: Username with password (Your GitHub username and Personal Access Token for the GitOps commit).

![Jenkins Global Credentials](./images/Jenkins%20credentials.png)

## Step 4: Automate Trigger using GitHub Webhook

**Goal:** Trigger the Jenkins pipeline automatically on a `main` branch push.

**Jenkins Configuration:**
1. In your Pipeline Job configuration, check the box for **Generic Webhook Trigger**.
2. Under Token, enter: `DevOps` (This authenticates GitHub with Jenkins).
3. Under Post content parameters, add a new variable:
   * **Variable:** `ref`
   * **Expression:** `$.ref`
4. Under Optional filter:
   * **Expression:** `^refs/heads/main$`
   * **Text:** `$ref`

**GitHub Configuration:**
1. Go to your GitHub repository **Settings → Webhooks → Add webhook**.
2. Set the Payload URL to: `http://<YOUR_JENKINS_IP>:8080/generic-webhook-trigger/invoke?token=DevOps`
3. Content type: `application/json`.
4. Select *Just the push event* and save.

## Step 5: Email Notification Setup (SMTP)

We configure Jenkins to send an email notification with the attached Trivy report upon completion.

### 1. Generate an App Password (Gmail)
1. Go to your Google Account → `https://myaccount.google.com/apppasswords`
2. Enable 2-Step Verification if not done.
3. Generate an App Password. This is highly secure and scoped to Jenkins only.

### 2. Configure Jenkins for SMTP
1. Go to **Manage Jenkins → System**.
2. Scroll down to **Extended E-mail Notification**.
3. **SMTP server:** `smtp.gmail.com`
4. **SMTP Port:** `465`
5. Click Advanced, check Use SMTP Authentication.
6. Add a new Credential with your Gmail address and the App Password you just generated.
7. Check Use SSL.

![Email Notification Configuration](./images/Email%20notification.png)

## Step 6: Create the Jenkins Pipeline Job

1. Go to **Jenkins Dashboard → New Item**.
2. Give it a name (e.g., `CI-Pipeline`), select **Pipeline**, and click **OK**.
3. Under **General**, check **Discard old builds** and set **Max # of builds to keep** to `3` (this saves disk space).
4. Scroll to the **Pipeline** section, set the **Definition** to **Pipeline script**, and paste the complete CI Pipeline Code below.

```groovy
pipeline {
    agent any

    tools {
        maven 'maven3'
    }
    
    environment {
        SCANNER_HOME = tool 'sonar-scanner'
        IMAGE_TAG = "v${BUILD_NUMBER}"
    }

    stages {
        stage('Git Checkout') {
            steps {
                git branch: 'main', url: 'https://github.com/tharindudeshapriya/devops-capstone-app.git'
            }
        }
        
        stage('Compile') {
            steps {
                sh 'mvn compile'
            }
        }
        
        stage('Test') {
            steps {
                sh 'mvn test'
            }
        }
        
        stage('Trivy FS Scan') {
            steps {
                sh 'trivy fs --format table -o fs-report.html .'
            }
        }
        
        stage('Code Quality Analysis') {
            steps {
                withSonarQubeEnv('sonar') {
                    // This MUST remain on a single line to prevent bash trailing space errors!
                    sh ''' $SCANNER_HOME/bin/sonar-scanner -Dsonar-projectName=GCBank -Dsonar.projectKey=GCBank -Dsonar.java.binaries=target '''
                }
            }
        }
        
        stage('Quality Gate Check') {
            steps {
                timeout(time: 1, unit: 'HOURS') {
                    waitForQualityGate abortPipeline: false, credentialsId: 'sonar-token'
                }
            }
        }
        
        stage('Build') {
            steps {
                sh 'mvn package'
            }
        }
        
        stage('Publish Artifacts') {
            steps {
                // Ensure your Jenkins Managed File ID is exactly 'tharindu'
                withMaven(globalMavenSettingsConfig: 'tharindu', maven: 'maven3', mavenSettingsConfig: '', traceability: true) {
                    sh 'mvn deploy'    
                }
            }
        }
        
        stage('Build and Tag Docker Images') {
            steps {
                sh "docker build -t tmdeshapriya/bankapp:${IMAGE_TAG} ."
            }
        }
        
        stage('Trivy Image Scan') {
            steps {
                sh 'trivy image --format table -o image-report.html tmdeshapriya/bankapp:$IMAGE_TAG'
            }
        }
        
        stage('Push Docker Images') {
            steps {
                script {
                    withDockerRegistry(credentialsId: 'docker-cred') {
                        sh "docker push tmdeshapriya/bankapp:$IMAGE_TAG"
                    }
                }
            }
        }
        
        stage('Update manifests file in CD repo') {
            steps {
                script {
                    cleanWs()
                    sh '''
                    # Clone your specific CD repository
                    git clone https://github.com/tharindudeshapriya/devops-capstone-k8s-manifests.git
                    
                    cd devops-capstone-k8s-manifests
                    
                    # Search for the old tag and replace it with the new build tag
                    sed -i "s|tmdeshapriya/bankapp:.*|tmdeshapriya/bankapp:${IMAGE_TAG}|" k8s/Manifest.yaml

                    echo "image tag updated"
                    cat k8s/Manifest.yaml

                    # commit and push the changes
                    git config user.name "tharindudeshapriya"
                    git config user.email "tmdeshapriya@gmail.com"
                    git add k8s/Manifest.yaml
                    git commit -m "image tag updated to ${IMAGE_TAG}"
                    '''

                    withCredentials([usernamePassword(credentialsId: 'github-cred', usernameVariable: 'GIT_USER', passwordVariable: 'GIT_PASS')]) {
                    sh '''
                    cd devops-capstone-k8s-manifests
                    git remote set-url origin https://$GIT_USER:$GIT_PASS@github.com/tharindudeshapriya/devops-capstone-k8s-manifests.git
                    git push origin main
                    '''
                    }
                }
            }
        }
    }
    
    post {
        always {
            script {
                def jobName = env.JOB_NAME
                def buildNumber = env.BUILD_NUMBER
                def pipelineStatus = currentBuild.result ?: 'UNKNOWN'
                def bannerColor = pipelineStatus.toUpperCase() == 'SUCCESS' ? 'green' : 'red'

                def body = """
                    <html>
                        <body>
                            <div style="border: 4px solid ${bannerColor}; padding: 10px;">
                                <h2>${jobName} - Build #${buildNumber}</h2>
                                <div style="background-color: ${bannerColor}; padding: 10px;">
                                    <h3 style="color: white;">Pipeline Status: ${pipelineStatus.toUpperCase()}</h3>
                                </div>
                                <p>Check the <a href="${env.BUILD_URL}">Console Output</a> for more details.</p>
                            </div>
                        </body>
                    </html>
                """

                emailext(
                    subject: "${jobName} - Build #${buildNumber} - ${pipelineStatus.toUpperCase()}",
                    body: body,
                    to: 'tmdeshapriya@gmail.com',
                    from: 'tmdeshapriya@gmail.com',
                    replyTo: 'tmdeshapriya@gmail.com',
                    mimeType: 'text/html',
                    attachmentsPattern: 'fs-report.html'
                )
            }
        }
    }
}
```
