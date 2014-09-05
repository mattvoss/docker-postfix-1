From ubuntu:trusty
MAINTAINER Elliott Ye

# Set noninteractive mode for apt-get
ENV DEBIAN_FRONTEND noninteractive

# Update
RUN apt-get update

# Start editing
# Install packages
RUN apt-get -y install supervisor postfix postfix-ldap postfix-mysql mysql-client sasl2-bin libsasl2-modules-ldap opendkim opendkim-tools
RUN apt-get -y install amavisd-new spamassassin clamav-daemon libnet-dns-perl libmail-spf-perl pyzor razor mailutils libpam-mysql openssl
RUN apt-get -y install arj bzip2 cabextract cpio file gzip nomarch pax unzip zip zoo vim
RUN apt-get -y install dovecot-common dovecot-imapd dovecot-lmtpd dovecot-mysql
RUN adduser clamav amavis
RUN adduser amavis clamav

# Add files
ADD assets/install.sh /opt/install.sh
ADD assets/dovecot/dovecot.conf /opt/dovecot.conf
ADD assets/dovecot/10-mail.conf /opt/10-mail.conf
ADD assets/dovecot/10-auth.conf /opt/10-auth.conf
ADD assets/dovecot/dovecot-sql.conf.ext /opt/dovecot-sql.conf.ext
ADD assets/dovecot/10-master.conf /opt/10-master.conf
ADD assets/dovecot/10-ssl.conf /opt/10-ssl.conf

VOLUME /etc/postfix
VOLUME /etc/opendkim
VOLUME /var/mail

EXPOSE 25
EXPOSE 465
EXPOSE 143
EXPOSE 993

EXPOSE 587
EXPOSE 110
EXPOSE 995

# Run
CMD /opt/install.sh
