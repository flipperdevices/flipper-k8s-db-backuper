FROM ubuntu:latest

RUN DEBIAN_FRONTEND=noninteractive apt update \
    && DEBIAN_FRONTEND=noninteractive apt -y install sudo lsb-release gnupg2 wget vim bash-completion awscli curl

RUN echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list

RUN wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -

RUN DEBIAN_FRONTEND=noninteractive apt update

ADD psql-backup.sh /backup/
WORKDIR /backup
