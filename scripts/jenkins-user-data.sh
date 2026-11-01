#!/usr/bin/env bash
set -Eeuo pipefail

# AWS EC2 user-data for an Ubuntu 24.04 Jenkins controller.
# The instance role must be allowed to read SECRET_NAME from Secrets Manager.

exec > >(tee -a /var/log/user-data.log | logger -t user-data -s 2>/dev/null) 2>&1

readonly AWS_REGION="${AWS_REGION:-__AWS_REGION__}"
readonly SECRET_NAME="${JENKINS_SECRET_NAME:-__JENKINS_SECRET_NAME__}"
readonly JENKINS_REPOSITORY="https://pkg.jenkins.io/debian-stable"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

[[ "${EUID}" -eq 0 ]] || fail "EC2 user-data must run as root."
[[ -r /etc/os-release ]] || fail "Cannot identify the operating system."

# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID:-}" == "ubuntu" && "${VERSION_ID:-}" == "24.04" ]] || \
  fail "This user-data script supports Ubuntu 24.04 only; found ${PRETTY_NAME:-unknown}."

export DEBIAN_FRONTEND=noninteractive

echo "Installing base packages..."
apt-get update
apt-get install -y ca-certificates curl fontconfig gnupg openjdk-21-jre unzip

echo "Installing AWS CLI v2..."
if ! command -v aws >/dev/null 2>&1; then
  rm -rf /tmp/aws
  mkdir -p /tmp/aws
  curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/awscliv2.zip
  unzip -q /tmp/awscliv2.zip -d /tmp
  /tmp/aws/install --update
  rm -rf /tmp/aws /tmp/awscliv2.zip
fi

echo "Configuring Jenkins repository..."
install -d -m 0755 /etc/apt/keyrings
curl -fsSL "${JENKINS_REPOSITORY}/jenkins.io-2026.key" \
  -o /etc/apt/keyrings/jenkins-keyring.asc
chmod a+r /etc/apt/keyrings/jenkins-keyring.asc
cat > /etc/apt/sources.list.d/jenkins.list <<EOF
deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] ${JENKINS_REPOSITORY} binary/
EOF

apt-get update
apt-get install -y jenkins

systemctl enable jenkins

echo "Retrieving Jenkins administrator password from Secrets Manager..."
ADMIN_PASSWORD="$(aws secretsmanager get-secret-value \
  --secret-id "${SECRET_NAME}" \
  --region "${AWS_REGION}" \
  --query SecretString \
  --output text)"
[[ -n "${ADMIN_PASSWORD}" && "${ADMIN_PASSWORD}" != "None" ]] || \
  fail "Secrets Manager returned no value for ${SECRET_NAME} in ${AWS_REGION}."

install -d -o jenkins -g jenkins -m 0750 /var/lib/jenkins/init.groovy.d

# Pass the secret through a Jenkins-readable temporary file, then remove it
# after Jenkins has consumed the initialization hook.
install -o jenkins -g jenkins -m 0600 /dev/null /run/jenkins-admin-password
printf '%s' "${ADMIN_PASSWORD}" > /run/jenkins-admin-password
unset ADMIN_PASSWORD

cat > /var/lib/jenkins/init.groovy.d/01-basic-security.groovy <<'EOF'
import hudson.security.FullControlOnceLoggedInAuthorizationStrategy
import hudson.security.HudsonPrivateSecurityRealm
import jenkins.model.Jenkins

def instance = Jenkins.get()
def passwordFile = new File('/run/jenkins-admin-password')

def realm = new HudsonPrivateSecurityRealm(false)
if (!realm.getUser('admin')) {
    if (!passwordFile.isFile()) {
        throw new IllegalStateException('Jenkins administrator password file is missing')
    }
    realm.createAccount('admin', passwordFile.text.trim())
}
instance.setSecurityRealm(realm)

def authorization = new FullControlOnceLoggedInAuthorizationStrategy()
authorization.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(authorization)
System.setProperty('jenkins.install.runSetupWizard', 'false')
instance.save()
EOF

cat > /var/lib/jenkins/init.groovy.d/02-install-plugins.groovy <<'EOF'
import java.util.logging.Logger
import jenkins.model.Jenkins

def logger = Logger.getLogger('init.groovy.d.plugins')
def instance = Jenkins.get()
def updateCenter = instance.getUpdateCenter()
updateCenter.updateAllSites()

def plugins = [
    'cloudbees-folder',
    'antisamy-markup-formatter',
    'build-timeout',
    'credentials-binding',
    'timestamper',
    'ws-cleanup',
    'ant',
    'gradle',
    'workflow-aggregator',
    'github-branch-source',
    'pipeline-github-lib',
    'pipeline-stage-view',
    'git',
    'ssh-slaves',
    'matrix-auth',
    'pam-auth',
    'ldap',
    'email-ext',
    'mailer'
]

plugins.each { pluginName ->
    if (!instance.pluginManager.getPlugin(pluginName)) {
        def plugin = updateCenter.getPlugin(pluginName)
        if (plugin) {
            logger.info("Installing Jenkins plugin: ${pluginName}")
            plugin.deploy(true)
        } else {
            throw new IllegalStateException("Jenkins plugin is unavailable: ${pluginName}")
        }
    }
}
instance.save()
EOF

if [[ -f /etc/default/jenkins ]]; then
  if grep -q '^JAVA_ARGS=' /etc/default/jenkins; then
    sed -i 's|^JAVA_ARGS=.*|JAVA_ARGS="-Djenkins.install.runSetupWizard=false"|' /etc/default/jenkins
  else
    printf '\nJAVA_ARGS="-Djenkins.install.runSetupWizard=false"\n' >> /etc/default/jenkins
  fi
else
  printf 'JAVA_ARGS="-Djenkins.install.runSetupWizard=false"\n' > /etc/default/jenkins
fi
chown -R jenkins:jenkins /var/lib/jenkins/init.groovy.d
chmod 0640 /var/lib/jenkins/init.groovy.d/*.groovy

systemctl daemon-reload
systemctl restart jenkins

echo "Waiting for Jenkins to start..."
for attempt in $(seq 1 60); do
  if systemctl is-active --quiet jenkins; then
    break
  fi
  sleep 2
done
systemctl is-active --quiet jenkins || fail "Jenkins did not start successfully."

for attempt in $(seq 1 60); do
  if curl --silent --show-error --fail --max-time 3 http://127.0.0.1:8080/login >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
curl --silent --show-error --fail --max-time 3 http://127.0.0.1:8080/login >/dev/null || \
  fail "Jenkins did not become ready on port 8080."

rm -f /run/jenkins-admin-password

echo "Verifying Jenkins..."
java -version

echo "Jenkins EC2 user-data setup completed successfully."
