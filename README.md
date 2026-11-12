# 🍔 Forkity - DevSecOps Project

A complete end-to-end DevSecOps project showcasing how to automate, secure, and monitor infrastructure and applications using modern tools — from Terraform to Kubernetes, Jenkins and everything in between [1].

Built to demonstrate real-world DevSecOps workflows for CI/CD, cloud automation, security integration, and observability — all centered around the **Forkity** food discovery application [1]. 🍿

---

## 🚀 Project Overview

This project simulates a real enterprise-grade setup where a React-based Forkity application is deployed and managed through a secure, automated DevOps pipeline [1].

---

## 🌐 Key Features

- **Infrastructure as Code with Terraform:** AWS provisioning with state management in Terraform Cloud [2].
- **CI/CD Automation:** Automated integration and delivery pipelines powered by GitHub Actions and Jenkins [2].
- **Containerization:** Application containerization using Docker [2].
- **Kubernetes Deployment:** Orchestrated application deployment on an unmanaged Kubernetes cluster [2].
- **Monitoring & Observability:** Integrated monitoring stack for Jenkins, Kubernetes, and the Forkity application [2].

---

## 🧩 Directory Structure under forkity-cicd

```text
.
├── Application-Code        # Frontend Forkity app built with React + Vite
│   ├── Dockerfile           # Docker image build instructions
│   ├── package.json         # Dependencies and scripts
│   ├── src/                 # Main source code
│   └── public/              # Static assets
│
├── Jenkins
│   └── Jenkinsfile          # CI/CD pipeline configuration (build → test → deploy)
│
├── Kubernetes
│   ├── deployment.yml       # App deployment manifest
│   └── service.yml          # K8s service exposure
│
└── Terraform
    ├── main.tf              # AWS resource definitions
    ├── backend.tf           # Terraform Cloud backend configuration
    ├── iam.tf               # IAM roles and policies
    ├── vpc.tf               # Network setup
    ├── variables.tf         # Input variables
    ├── dev.auto.tfvars      # Environment variables
    ├── gather.tf            # Data sources and dependencies
    └── scripts
        └── jenkins-install.sh # Installs Jenkins and requested plugins; skips setup wizard
```

> **Note on Jenkins Setup:** The `jenkins-install.sh` script skips the setup wizard, creates a Jenkins administrator with a generated password, and installs requested plugins [4]. Retrieve the admin password on the server with `sudo cat /var/lib/jenkins/secrets/bootstrap-admin-password` [4]. Restrict access to Jenkins and change the generated password after signing in [4].

---

## 🛠️ Tech Stack

| Category | Tools / Technologies |
| :--- | :--- |
| **Infrastructure** | Terraform, AWS EC2, Terraform Cloud [5] |
| **CI/CD** | Jenkins, GitHub Actions [5] |
| **Containerization** | Docker [5] |
| **Orchestration** | Kubernetes (Unmanaged Cluster) [5] |
| **Monitoring** | Node Exporter, Prometheus, Kube State Metrics [5] |
| **Frontend** | React, Vite, Forkity Food API [2, 5] |

---

## 🎯 Objectives

- Automate the entire infrastructure and application deployment lifecycle [5].
- Integrate security and quality checks early in the pipeline [5].
- Establish a fully observable, monitored system for reliability [5].
- Showcase an end-to-end DevSecOps workflow ideal for portfolios and interviews [6].


