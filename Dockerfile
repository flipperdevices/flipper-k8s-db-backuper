FROM ubuntu:jammy

RUN DEBIAN_FRONTEND=noninteractive apt update && DEBIAN_FRONTEND=noninteractive apt -y install sudo lsb-release gnupg2 wget vim bash-completion awscli curl mysql-client python3 python3-pip

RUN echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
RUN echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-6.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/6.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-6.0.list

RUN wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
RUN curl -fsSL https://pgp.mongodb.com/server-6.0.asc | sudo gpg -o /usr/share/keyrings/mongodb-server-6.0.gpg --dearmor

RUN DEBIAN_FRONTEND=noninteractive apt update && DEBIAN_FRONTEND=noninteractive apt -y install mongodb-org-tools mongodb-mongosh

ADD psql-backup.sh /backup/
ADD mysql-backup.sh /backup/
ADD mongo-backup.sh /backup/
ADD cloudflare-backup.py /backup/

ADD requirements.txt /backup/
RUN python3 -m pip install -r /backup/requirements.txt

WORKDIR /backup
