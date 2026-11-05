#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this script as root (for example, with sudo)." >&2
  exit 1
fi

if [[ ! -r /etc/os-release ]]; then
  echo "Cannot determine the operating system: /etc/os-release is unavailable." >&2
  exit 1
fi

. /etc/os-release
if [[ "${ID:-}" != "ubuntu" ]]; then
  echo "This installer supports Ubuntu; detected '${ID:-unknown}'." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl fontconfig openjdk-21-jre

install -d -m 0755 /etc/apt/keyrings
key_tmp="$(mktemp)"
trap 'rm -f "$key_tmp"' EXIT
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key -o "$key_tmp"
install -m 0644 "$key_tmp" /etc/apt/keyrings/jenkins-keyring.asc

printf '%s\n' \
  'deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/' \
  > /etc/apt/sources.list.d/jenkins.list

apt-get update
apt-get install -y jenkins

# ==============================================================================
# AUTOMATED PLUGIN INSTALLATION CONFIGURATION
# ==============================================================================

# 1. Skip the Setup Wizard UI screen
JENKINS_ARGS_DIR="/etc/systemd/system/jenkins.service.d"
mkdir -p "$JENKINS_ARGS_DIR"
cat << 'EOF' > "$JENKINS_ARGS_DIR/override.conf"
[Service]
Environment="JAVA_OPTS=-Djenkins.install.runSetupWizard=false"
EOF

systemctl daemon-reload

# 2. Grab the official plug-in installation CLI tool
PLUGIN_CLI_VERSION="2.13.2"
curl -fsSL "https://github.com{PLUGIN_CLI_VERSION}/jenkins-plugin-manager-${PLUGIN_CLI_VERSION}.jar" \
  -o /opt/jenkins-plugin-manager.jar

# 3. Define all standard wizard plugins + SonarQube & Slack dependencies
PLUGINS=(
  git
  github-branch-source
  workflow-aggregator
  pipeline-stage-view
  ws-cleanup
  timestamper
  credentials-binding
  matrix-auth
  pam-auth
  ldap
  ssh-slaves
  mailer
  ant
  gradle
  maven-plugin
  sonar
  slack
)

echo "Pre-downloading Jenkins plugins and matching dependencies..."
java -jar /opt/jenkins-plugin-manager.jar \
  --war /usr/share/java/jenkins.war \
  --plugin-download-directory /var/lib/jenkins/plugins \
  --plugins "${PLUGINS[@]}"

# Fix folder ownership permissions for the downloaded components
chown -R jenkins:jenkins /var/lib/jenkins/plugins

# ==============================================================================

systemctl enable --now jenkins

if ! systemctl is-active --quiet jenkins; then
  echo "Jenkins was installed but its service is not active." >&2
  exit 1
fi

echo "Jenkins is installed and running."
 