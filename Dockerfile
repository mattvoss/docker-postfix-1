From ubuntu:trusty
MAINTAINER Elliott Ye

# Set noninteractive mode for apt-get
ENV DEBIAN_FRONTEND noninteractive

# Update
RUN apt-get update

# Start editing
# Install packages
RUN apt-get -y install supervisor postfix postfix-ldap sasl2-bin libsasl2-modules-ldap opendkim opendkim-tools
RUN apt-get -y install amavisd-new spamassassin clamav-daemon libnet-dns-perl libmail-spf-perl pyzor razor
RUN apt-get -y install apt-get install arj bzip2 cabextract cpio file gzip nomarch pax unzip zip zoo
RUN adduser clamav amavis
RUN adduser amavis clamav

# Add files
ADD assets/install.sh /opt/install.sh

# Run
CMD /opt/install.sh;/usr/bin/supervisord -c /etc/supervisor/supervisord.conf
