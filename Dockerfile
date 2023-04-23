FROM ubuntu:latest

RUN DEBIAN_FRONTEND=noninteractive apt update \
    && DEBIAN_FRONTEND=noninteractive apt -y install sudo lsb-release gnupg2 wget vim bash-completion awscli curl

RUN wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -

ADD psql-backup.sh /backup/
WORKDIR /backup
