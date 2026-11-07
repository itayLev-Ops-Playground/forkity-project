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
apt-get install -y ca-certificates curl fontconfig openjdk-21-jre openssl

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

admin_password_file=/var/lib/jenkins/secrets/bootstrap-admin-password
admin_configured_marker=/var/lib/jenkins/secrets/bootstrap-admin-configured
if [[ ! -f "$admin_configured_marker" ]]; then
  install -d -o jenkins -g jenkins -m 0700 /var/lib/jenkins/secrets
  install -d -o jenkins -g jenkins -m 0755 /var/lib/jenkins/init.groovy.d

  if [[ ! -f "$admin_password_file" ]]; then
    (
      umask 077
      openssl rand -hex 32 > "$admin_password_file"
    )
  fi
  chown jenkins:jenkins "$admin_password_file"
  chmod 0600 "$admin_password_file"

  cat > /var/lib/jenkins/init.groovy.d/10-bootstrap-admin.groovy <<'EOF'
import hudson.security.GlobalMatrixAuthorizationStrategy
import hudson.security.HudsonPrivateSecurityRealm
import jenkins.model.Jenkins

def jenkins = Jenkins.get()
def passwordFile = new File('/var/lib/jenkins/secrets/bootstrap-admin-password')
if (!passwordFile.isFile()) {
    throw new IllegalStateException('Jenkins bootstrap admin password file is missing')
}

def realm = new HudsonPrivateSecurityRealm(false)
realm.createAccount('jenkins', passwordFile.text.trim())
jenkins.setSecurityRealm(realm)

def authorization = new GlobalMatrixAuthorizationStrategy()
authorization.add(Jenkins.ADMINISTER, 'jenkins')
jenkins.setAuthorizationStrategy(authorization)
jenkins.save()

new File('/var/lib/jenkins/secrets/bootstrap-admin-configured').text = 'configured\n'
new File('/var/lib/jenkins/init.groovy.d/10-bootstrap-admin.groovy').delete()
EOF
  chown jenkins:jenkins /var/lib/jenkins/init.groovy.d/10-bootstrap-admin.groovy
  chmod 0644 /var/lib/jenkins/init.groovy.d/10-bootstrap-admin.groovy
fi

# Fix folder ownership permissions for the downloaded components
chown -R jenkins:jenkins /var/lib/jenkins/plugins

# ==============================================================================

systemctl enable --now jenkins

if ! systemctl is-active --quiet jenkins; then
  echo "Jenkins was installed but its service is not active." >&2
  exit 1
fi

for attempt in {1..120}; do
  [[ -f "$admin_configured_marker" ]] && break
  if ! systemctl is-active --quiet jenkins; then
    echo "Jenkins stopped before the bootstrap admin user was configured." >&2
    exit 1
  fi
  sleep 5
done

if [[ ! -f "$admin_configured_marker" ]]; then
  echo "Jenkins started, but the bootstrap admin user was not configured." >&2
  exit 1
fi

echo "Jenkins is installed and running."
echo "Bootstrap admin username: jenkins"
echo "Retrieve its password with: sudo cat /var/lib/jenkins/secrets/bootstrap-admin-password"
 