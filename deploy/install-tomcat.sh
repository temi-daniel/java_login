#!/bin/bash
# Installs Java 11 + Tomcat 9 on Amazon Linux 2023 / Amazon Linux 2 / Ubuntu and deploys the WAR.
# Usage (as root):  ./install-tomcat.sh /path/to/dptweb-1.0.war
# Can also be pasted into EC2 "user data" / a launch template (fetch the WAR from S3 first).
set -euo pipefail

WAR="${1:?Usage: $0 /path/to/dptweb-1.0.war}"
TOMCAT_VERSION="${TOMCAT_VERSION:-9.0.98}"
HERE="$(cd "$(dirname "$0")" && pwd)"

# 1. Java 11
if command -v dnf >/dev/null; then
  dnf install -y java-11-amazon-corretto-headless || dnf install -y java-11-openjdk-headless
  JAVA_HOME_DIR="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")"
elif command -v yum >/dev/null; then
  yum install -y java-11-amazon-corretto-headless
  JAVA_HOME_DIR="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")"
else
  apt-get update && apt-get install -y openjdk-11-jre-headless curl
  JAVA_HOME_DIR="/usr/lib/jvm/java-11-openjdk-amd64"
fi

# 2. Tomcat user + install
id tomcat >/dev/null 2>&1 || useradd -r -m -U -d /opt/tomcat -s /sbin/nologin tomcat
if [ ! -x /opt/tomcat/bin/catalina.sh ]; then
  curl -fsSL "https://archive.apache.org/dist/tomcat/tomcat-9/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz" -o /tmp/tomcat.tgz
  tar -xzf /tmp/tomcat.tgz -C /opt/tomcat --strip-components=1
fi
echo "export JAVA_HOME=${JAVA_HOME_DIR}" > /opt/tomcat/bin/setenv.sh
chmod +x /opt/tomcat/bin/*.sh

# 3. Deploy the WAR as the root application (served at /)
rm -rf /opt/tomcat/webapps/ROOT /opt/tomcat/webapps/ROOT.war
cp "$WAR" /opt/tomcat/webapps/ROOT.war
chown -R tomcat:tomcat /opt/tomcat

# 4. DB settings + service
if [ ! -f /etc/tomcat.env ]; then
  cp "$HERE/tomcat.env.example" /etc/tomcat.env
  echo ">>> Edit /etc/tomcat.env with your real DB values, then: systemctl restart tomcat"
fi
chmod 600 /etc/tomcat.env
cp "$HERE/tomcat.service" /etc/systemd/system/tomcat.service
systemctl daemon-reload
systemctl enable --now tomcat

echo "Done. Tomcat listens on :8080 — try http://localhost:8080/login"
