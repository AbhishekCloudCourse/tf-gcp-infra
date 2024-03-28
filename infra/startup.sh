#!/bin/bash

DB_HOST=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/db-host" -H "Metadata-Flavor: Google")
DB_USERNAME=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/db-username" -H "Metadata-Flavor: Google")
DB_PASSWORD=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/db-password" -H "Metadata-Flavor: Google")
DB_NAME=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/db-name" -H "Metadata-Flavor: Google")
TOPIC_NAME=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/topic-name" -H "Metadata-Flavor: Google")

sudo bash -c "echo 'DB_HOST=$DB_HOST' > /etc/csye6225/var_file"
sudo bash -c "echo 'DB_USERNAME=$DB_USERNAME' >> /etc/csye6225/var_file"
sudo bash -c "echo 'DB_PASSWORD=$DB_PASSWORD' >> /etc/csye6225/var_file"
sudo bash -c "echo 'DB_NAME=$DB_NAME' >> /etc/csye6225/var_file"
sudo bash -c "echo 'TOPIC_NAME=$TOPIC_NAME' >> /etc/csye6225/var_file"

chown -R csye6225:csye6225 /home/csye6225

sudo systemctl daemon-reload
sudo systemctl enable node-server.service
sudo systemctl start node-server