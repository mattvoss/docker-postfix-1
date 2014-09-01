#!/bin/bash

#judgement
if [[ -a /etc/supervisor/conf.d/supervisord.conf ]]; then
  exit 0
fi

#supervisor
cat > /etc/supervisor/conf.d/supervisord.conf <<EOF
[supervisord]
nodaemon=true

[program:postfix]
command=/opt/postfix.sh

[program:rsyslog]
command=/usr/sbin/rsyslogd -n -c3
EOF

############
#  postfix
############
cat >> /opt/postfix.sh <<EOF
#!/bin/bash
service saslauthd start
service postfix start
tail -f /var/log/mail.log
EOF
chmod +x /opt/postfix.sh
if [[ -n "$MAIL_HOSTNAME" ]]; then
  postconf -e myhostname=$MAIL_HOSTNAME
fi
if [[ -n "$MAIL_DOMAIN" ]]; then
  postconf -e mydomain=$MAIL_DOMAIN
fi
postconf -F '*/*/chroot = n'

# No Open Proxy / No Spam

postconf -e smtpd_sender_restrictions=permit_sasl_authenticated,permit_mynetworks,reject_unknown_sender_domain,permit
postconf -e smtpd_helo_restrictions=permit_mynetworks,reject_invalid_hostname,permit
postconf -e smtpd_relay_restrictions=permit_sasl_authenticated,permit_mynetworks,reject_unauth_destination
postconf -e "smtpd_recipient_restrictions=permit_mynetworks,permit_inet_interfaces,permit_sasl_authenticated,reject_invalid_hostname,reject_non_fqdn_hostname,reject_non_fqdn_sender,reject_non_fqdn_recipient,reject_rbl_client zen.spamhaus.org,permit"

############
# SASL SUPPORT FOR CLIENTS
# The following options set parameters needed by Postfix to enable
# Cyrus-SASL support for authentication of mail clients.
############
# /etc/postfix/main.cf
postconf -e smtpd_sasl_auth_enable=yes
postconf -e broken_sasl_auth_clients=yes

# smtpd.conf
if [[ -n "$smtp_user" ]]; then

  postconf -e "mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain"
  cat >> /etc/postfix/sasl/smtpd.conf <<EOF
pwcheck_method: auxprop
auxprop_plugin: sasldb
mech_list: PLAIN LOGIN CRAM-MD5 DIGEST-MD5 NTLM
EOF

  # sasldb2
  echo $smtp_user | tr , \\n > /tmp/passwd
  while IFS=':' read -r _user _pwd; do
    echo $_pwd | saslpasswd2 -p -c -u $MAIL_HOSTNAME $_user
  done < /tmp/passwd
  chown postfix.sasl /etc/sasldb2

elif [[ -n "$LDAP_HOST" && -n "$LDAP_BASE" ]]; then

  postconf -e "mydestination = localhost.\$mydomain, localhost"

  cat > /etc/postfix/sasl/smtpd.conf <<EOF
START=yes
DESC="SASL Authentication Daemon"
NAME="saslauthd"
MECHANISMS="ldap"
OPTIONS="-c -m /var/run/saslauthd"
EOF

  cat > /etc/postfix/sasl/smtpd.conf <<EOF
pwcheck_method: saslauthd
EOF

  cat > /etc/saslauthd.conf <<EOF
ldap_servers: ldap://$LDAP_HOST
ldap_search_base: $LDAP_BASE
ldap_version: 3
EOF

  if [[ -n "$LDAP_USER_FILTER" ]]; then
    echo "ldap_filter: $LDAP_USER_FILTER" >> /etc/postfix/sasl/smtpd.conf
  fi

  if [[ -n "$LDAP_BIND_DN" && -n "$LDAP_BIND_PW" ]]; then
    echo "ldap_bind_dn: $LDAP_BIND_DN" >> /etc/postfix/sasl/smtpd.conf
    echo "ldap_bind_pw: $LDAP_BIND_PW" >> /etc/postfix/sasl/smtpd.conf
  fi

fi

############
# Enable TLS
############
if [[ -n "$(find /etc/postfix/certs -iname *.crt)" && -n "$(find /etc/postfix/certs -iname *.key)" ]]; then
  # /etc/postfix/main.cf
  postconf -e smtpd_tls_cert_file=$(find /etc/postfix/certs -iname *.crt)
  postconf -e smtpd_tls_key_file=$(find /etc/postfix/certs -iname *.key)
  postconf -e smtpd_tls_CAfile=/etc/postfix/certs/certs/cacert.pem
  chmod 400 $(find /etc/postfix/certs -iname *.crt) $(find /etc/postfix/certs -iname *.key) /etc/postfix/certs/certs/cacert.pem
  # /etc/postfix/master.cf
  postconf -M submission/inet="submission   inet   n   -   n   -   -   smtpd"
  postconf -P "submission/inet/syslog_name=postfix/submission"
  postconf -P "submission/inet/smtpd_tls_security_level=encrypt"
  postconf -P "submission/inet/smtpd_sasl_auth_enable=yes"
  postconf -P "submission/inet/milter_macro_daemon_name=ORIGINATING"
fi

############
# LDAP
############

if [[ -n "$LDAP_HOST" && -n "$LDAP_BASE" ]]; then
  groupadd -g 1200 vmail
  useradd -u 1200 -g 1200 -s /sbin/nologin vmail
  chown vmail:vmail /var/mail

  cat >> /etc/postfix/ldap-aliases.cf <<EOF
server_host = $LDAP_HOST
search_base = $LDAP_BASE
version = 3
EOF

  if [[ -n "$LDAP_ALIAS_FILTER" ]]; then
    echo "query_filter = $LDAP_ALIAS_FILTER" >> /etc/postfix/ldap-aliases.cf
  fi

  if [[ -n "$LDAP_ALIAS_RESULT_ATTRIBUTE" ]]; then
    echo "result_attribute = $LDAP_ALIAS_RESULT_ATTRIBUTE" >> /etc/postfix/ldap-aliases.cf
  fi

  if [[ -n "$LDAP_ALIAS_SPECIAL_RESULT_ATTRIBUTE" ]]; then
    echo "special_result_attribute = $LDAP_ALIAS_SPECIAL_RESULT_ATTRIBUTE" >> /etc/postfix/ldap-aliases.cf
  fi

  if [[ -n "$LDAP_ALIAS_TERMINAL_RESULT_ATTRIBUTE" ]]; then
    echo "terminal_result_attribute = $LDAP_ALIAS_TERMINAL_RESULT_ATTRIBUTE" >> /etc/postfix/ldap-aliases.cf
  fi

  if [[ -n "$LDAP_ALIAS_LEAF_RESULT_ATTRIBUTE" ]]; then
    echo "leaf_result_attribute = $LDAP_ALIAS_LEAF_RESULT_ATTRIBUTE" >> /etc/postfix/ldap-aliases.cf
  fi

  if [[ -n "$LDAP_BIND_DN" && -n "$LDAP_BIND_PW" ]]; then
    echo "bind = yes" >> /etc/postfix/ldap-aliases.cf
    echo "bind_dn = $LDAP_BIND_DN" >> /etc/postfix/ldap-aliases.cf
    echo "bind_pw = $LDAP_BIND_PW" >> /etc/postfix/ldap-aliases.cf
  fi

  cat >> /etc/postfix/ldap-mailboxes.cf <<EOF
server_host = $LDAP_HOST
search_base = $LDAP_BASE
version = 3
EOF

  if [[ -n "$LDAP_MAILBOX_FILTER" ]]; then
    echo "query_filter = $LDAP_MAILBOX_FILTER" >> /etc/postfix/ldap-mailboxes.cf
  fi

  if [[ -n "$LDAP_MAILBOX_RESULT_ATTRIBUTE" ]]; then
    echo "result_attribute = $LDAP_MAILBOX_RESULT_ATTRIBUTE" >> /etc/postfix/ldap-mailboxes.cf
  fi

  if [[ -n "$LDAP_MAILBOX_RESULT_FORMAT" ]]; then
    echo "result_format = $LDAP_MAILBOX_RESULT_FORMAT" >> /etc/postfix/ldap-mailboxes.cf
  fi

  postconf -e "virtual_mailbox_domains = \$myhostname, \$mydomain"
  postconf -e virtual_mailbox_base=/var/mail
  postconf -e virtual_alias_maps=ldap:/etc/postfix/ldap-aliases.cf
  postconf -e virtual_mailbox_maps=ldap:/etc/postfix/ldap-mailboxes.cf
  postconf -e virtual_uid_maps=static:1200
  postconf -e virtual_gid_maps=static:1200

fi

#############
#  opendkim
#############

if [[ -z "$(find /etc/opendkim/domainkeys -iname *.private)" ]]; then
  exit 0
fi
cat >> /etc/supervisor/conf.d/supervisord.conf <<EOF

[program:opendkim]
command=/usr/sbin/opendkim -f
EOF
# /etc/postfix/main.cf
postconf -e milter_protocol=2
postconf -e milter_default_action=accept
postconf -e smtpd_milters=inet:localhost:12301
postconf -e non_smtpd_milters=inet:localhost:12301

cat >> /etc/opendkim.conf <<EOF
AutoRestart             Yes
AutoRestartRate         10/1h
UMask                   002
Syslog                  yes
SyslogSuccess           Yes
LogWhy                  Yes

Canonicalization        relaxed/simple

ExternalIgnoreList      refile:/etc/opendkim/TrustedHosts
InternalHosts           refile:/etc/opendkim/TrustedHosts
KeyTable                refile:/etc/opendkim/KeyTable
SigningTable            refile:/etc/opendkim/SigningTable

Mode                    sv
PidFile                 /var/run/opendkim/opendkim.pid
SignatureAlgorithm      rsa-sha256

UserID                  opendkim:opendkim

Socket                  inet:12301@localhost
EOF
cat >> /etc/default/opendkim <<EOF
SOCKET="inet:12301@localhost"
EOF

cat >> /etc/opendkim/TrustedHosts <<EOF
127.0.0.1
localhost
192.168.0.1/24

*.$maildomain
EOF
cat >> /etc/opendkim/KeyTable <<EOF
mail._domainkey.$MAIL_HOSTNAME $MAIL_HOSTNAME:mail:$(find /etc/opendkim/domainkeys -iname *.private)
EOF
cat >> /etc/opendkim/SigningTable <<EOF
*@$MAIL_HOSTNAME mail._domainkey.$MAIL_HOSTNAME
EOF
chown opendkim:opendkim $(find /etc/opendkim/domainkeys -iname *.private)
chmod 400 $(find /etc/opendkim/domainkeys -iname *.private)
