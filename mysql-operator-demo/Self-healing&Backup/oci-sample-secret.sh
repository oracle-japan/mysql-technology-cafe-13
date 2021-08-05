kubectl create secret generic oci-credentials -n mysql-cluster \
        --from-literal=user=<user> \
        --from-literal=fingerprint=<fingerprint> \
        --from-literal=tenancy=<tenancy> \
        --from-literal=region=us-ashburn-1 \
        --from-literal=passphrase=<passphrase> \
        --from-file=privatekey=/path/to/oci_api_key.pem
