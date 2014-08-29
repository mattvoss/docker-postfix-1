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
service postfix start
tail -f /var/log/mail.log
EOF
chmod +x /opt/postfix.sh
postconf -e myhostname=$maildomain
postconf -F '*/*/chroot = n'

############
# SASL SUPPORT FOR CLIENTS
# The following options set parameters needed by Postfix to enable
# Cyrus-SASL support for authentication of mail clients.
############
# /etc/postfix/main.cf
postconf -e smtpd_sasl_auth_enable=yes
postconf -e broken_sasl_auth_clients=yes
postconf -e smtpd_recipient_restrictions=permit_sasl_authenticated,reject_unauth_destination
# smtpd.conf
if [[ -n "$smtp_user" ]]; then
  cat >> /etc/postfix/sasl/smtpd.conf <<EOF
pwcheck_method: auxprop
auxprop_plugin: sasldb
mech_list: PLAIN LOGIN CRAM-MD5 DIGEST-MD5 NTLM
EOF

  # sasldb2
  echo $smtp_user | tr , \\n > /tmp/passwd
  while IFS=':' read -r _user _pwd; do
    echo $_pwd | saslpasswd2 -p -c -u $maildomain $_user
  done < /tmp/passwd
  chown postfix.sasl /etc/sasldb2

elif [[ -n "$LDAP_HOST" && -n "$LDAP_BASE" ]]; then

  cat >> /etc/postfix/sasl/smtpd.conf <<EOF
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
  postconf -P "submission/inet/smtpd_recipient_restrictions=permit_sasl_authenticated,reject_unauth_destination"
fi

############
# LDAP
############

if [[ -n "$LDAP_HOST" && -n "$LDAP_BASE" ]]; then
  cat >> /etc/postfix/ldap-aliases.cf <<EOF
server_host = $LDAP_HOST
search_base = $LDAP_BASE
version = 3
EOF

  if [[ -n "$LDAP_MAIL_FILTER" ]]; then
    echo "query_filter = $LDAP_MAIL_FILTER" >> /etc/postfix/ldap-aliases.cf
  fi

  if [[ -n "$LDAP_RESULT_ATTRIBUTE" ]]; then
    echo "result_attribute = $LDAP_RESULT_ATTRIBUTE" >> /etc/postfix/ldap-aliases.cf
  fi

  if [[ -n "$LDAP_SPECIAL_RESULT_ATTRIBUTE" ]]; then
    echo "special_result_attribute = $LDAP_SPECIAL_RESULT_ATTRIBUTE" >> /etc/postfix/ldap-aliases.cf
  fi

  if [[ -n "$LDAP_TERMINAL_RESULT_ATTRIBUTE" ]]; then
    echo "terminal_result_attribute = $LDAP_TERMINAL_RESULT_ATTRIBUTE" >> /etc/postfix/ldap-aliases.cf
  fi

  if [[ -n "$LDAP_LEAF_RESULT_ATTRIBUTE" ]]; then
    echo "leaf_result_attribute = $LDAP_LEAF_RESULT_ATTRIBUTE" >> /etc/postfix/ldap-aliases.cf
  fi

  if [[ -n "$LDAP_BIND_DN" && -n "$LDAP_BIND_PW" ]]; then
    echo "bind = yes" >> /etc/postfix/ldap-aliases.cf
    echo "bind_dn = $LDAP_BIND_DN" >> /etc/postfix/ldap-aliases.cf
    echo "bind_pw = $LDAP_BIND_PW" >> /etc/postfix/ldap-aliases.cf
  fi

  postconf -e alias_maps=ldap:/etc/postfix/ldap-aliases.cf
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
mail._domainkey.$maildomain $maildomain:mail:$(find /etc/opendkim/domainkeys -iname *.private)
EOF
cat >> /etc/opendkim/SigningTable <<EOF
*@$maildomain mail._domainkey.$maildomain
EOF
chown opendkim:opendkim $(find /etc/opendkim/domainkeys -iname *.private)
chmod 400 $(find /etc/opendkim/domainkeys -iname *.private)
