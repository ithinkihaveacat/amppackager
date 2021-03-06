# This script deploys 3 instances of amppackagers into a gcloud kubernetes
# cluster. 1 instance (renewer) will be responsible for automatically renewing
# certificates using the ACME protocol. The remaining 2 instances (consumer) will be made
# accessible to a web-server that can be configured to forward signed exchange
# requests to them for processing.

# git clone https://github.com/ampproject/amppackager.git
# cd amppackager/deploy/gcloud
# To start: ./gcloud_up.sh
# To shutdown: ./gcloud_down.sh
# To clean out all of the autogenerated files in this directory: ./clean.sh

export CURRENT_DIR=$(dirname $0)
export GENFILES_DIR="$CURRENT_DIR/generated"

if [ ! -d "$GENFILES_DIR" ]; then
  echo "Creating generated/ directory"
  mkdir -p $GENFILES_DIR
fi

# All user/project specific information will be setup in ./setup.sh.
source $CURRENT_DIR/setup.sh

# Note that PRIVATE KEY, SAN Config and CSR are optional steps. If you have
# these files generated already, you can copy them into this directory, using
# the naming convention you specifed in setup.sh.
# IMPORTANT: the private key, SAN, CSR and the certificate all go together,
# you cannot mix and match a new private key with an existing certificate and
# so on.

# *** PRIVATE KEY
# Generate prime256v1 ecdsa private key. If you already have a key,
# copy it to amppkg.privkey.
if [ -f "$GENFILES_DIR/$AMP_PACKAGER_PRIV_KEY_FILENAME" ]; then
  echo "$GENFILES_DIR/$AMP_PACKAGER_PRIV_KEY_FILENAME exists. Skipping generation."
else
  echo "Generating key ..."
  openssl ecparam -out "$GENFILES_DIR/$AMP_PACKAGER_PRIV_KEY_FILENAME" -name prime256v1 -genkey
fi

# *** SAN Config
# Generate the SAN file needed for CSR generation with the project specific values.
# See: https://ethitter.com/2016/05/generating-a-csr-with-san-at-the-command-line/
if [ -f "$GENFILES_DIR/san.cnf" ]; then
  echo "$GENFILES_DIR/san.cnf exists. Skipping generation."
else
  echo "Generating SAN file ..."
  cat san_template.cnf \
    | sed 's/$(AMP_PACKAGER_COUNTRY)/'"$AMP_PACKAGER_COUNTRY"'/g' \
    | sed 's/$(AMP_PACKAGER_STATE)/'"$AMP_PACKAGER_STATE"'/g' \
    | sed 's/$(AMP_PACKAGER_LOCALITY)/'"$AMP_PACKAGER_LOCALITY"'/g' \
    | sed 's/$(AMP_PACKAGER_ORGANIZATION)/'"$AMP_PACKAGER_ORGANIZATION"'/g' \
    | sed 's/$(AMP_PACKAGER_DOMAIN)/'"$AMP_PACKAGER_DOMAIN"'/g' \
    > $GENFILES_DIR/san.cnf
fi

# *** CSR
# Create a certificate signing request for the private key using the SAN config
# generated above. Copy the CSR to a safe place. If you already have a CSR,
# copy into amppkg.csr (or whatever you named it in setup.sh).
# To print 'openssl req -text -noout -verify -in amppkg.csr'
if [ -f "$GENFILES_DIR/$AMP_PACKAGER_CSR_FILENAME" ]; then
  echo "$GENFILES_DIR/$AMP_PACKAGER_CSR_FILENAME exists. Skipping generation."
else
  echo "Generating CSR ..."
  openssl req -new -sha256 -key "$GENFILES_DIR/$AMP_PACKAGER_PRIV_KEY_FILENAME" \
    -subj "/C=$AMP_PACKAGER_COUNTRY/ST=$AMP_PACKAGER_STATE/O=$AMP_PACKAGER_ORGANIZATION/CN=$AMP_PACKAGER_DOMAIN" \
    -nodes -out "$GENFILES_DIR/$AMP_PACKAGER_CSR_FILENAME" -outform pem -config $GENFILES_DIR/san.cnf
fi

# Generate the TOML files with the project specific values.
if [ -f "$GENFILES_DIR/amppkg_consumer.toml" ]; then
  echo "$GENFILES_DIR/amppkg_consumer.toml exists. Skipping generation."
else
  echo "Generating TOML files ..."
  cat amppkg_consumer_template.toml \
    | sed 's/$(AMP_PACKAGER_CERT_FILENAME)/'"$AMP_PACKAGER_CERT_FILENAME"'/g' \
    | sed 's/$(AMP_PACKAGER_CSR_FILENAME)/'"$AMP_PACKAGER_CSR_FILENAME"'/g' \
    | sed 's/$(AMP_PACKAGER_PRIV_KEY_FILENAME)/'"$AMP_PACKAGER_PRIV_KEY_FILENAME"'/g' \
    | sed 's/$(AMP_PACKAGER_DOMAIN)/'"$AMP_PACKAGER_DOMAIN"'/g' \
    > $GENFILES_DIR/amppkg_consumer.toml
fi

if [ -f "$GENFILES_DIR/amppkg_renewer.toml" ]; then
  echo "$GENFILES_DIR/amppkg_renewer.toml exists. Skipping generation."
else
  cat amppkg_renewer_template.toml \
    | sed 's/$(AMP_PACKAGER_CERT_FILENAME)/'"$AMP_PACKAGER_CERT_FILENAME"'/g' \
    | sed 's/$(AMP_PACKAGER_CSR_FILENAME)/'"$AMP_PACKAGER_CSR_FILENAME"'/g' \
    | sed 's/$(AMP_PACKAGER_PRIV_KEY_FILENAME)/'"$AMP_PACKAGER_PRIV_KEY_FILENAME"'/g' \
    | sed 's/$(AMP_PACKAGER_DOMAIN)/'"$AMP_PACKAGER_DOMAIN"'/g' \
    | sed 's/$(ACME_EMAIL_ADDRESS)/'"$ACME_EMAIL_ADDRESS"'/g' \
    | sed 's,$(ACME_DIRECTORY_URL),'"$ACME_DIRECTORY_URL"',g' \
    > $GENFILES_DIR/amppkg_renewer.toml
fi

# Generate the yaml files that have the project id and docker image version tag with proper values.
if [ -f "$GENFILES_DIR/amppackager_cert_renewer.yaml" ]; then
  echo "$GENFILES_DIR/amppackager_cert_renewer.toml exists. Skipping generation."
else
  echo "Generating renewer YAML file ..."
  cat amppackager_cert_renewer_template.yaml \
    | sed 's/$(PROJECT_ID)/'$PROJECT_ID'/g' \
    | sed 's/$(AMP_PACKAGER_VERSION_TAG)/'$AMP_PACKAGER_VERSION_TAG'/g' \
    > $GENFILES_DIR/amppackager_cert_renewer.yaml
fi

if [ -f "$GENFILES_DIR/amppackager_cert_consumer.yaml" ]; then
  echo "$GENFILES_DIR/amppackager_cert_consumer.toml exists. Skipping generation."
else
  echo "Generating consumer YAML file ..."
  cat amppackager_cert_consumer_template.yaml \
    | sed 's/$(PROJECT_ID)/'$PROJECT_ID'/g' \
    | sed 's/$(AMP_PACKAGER_NUM_REPLICAS)/'$AMP_PACKAGER_NUM_REPLICAS'/g' \
    | sed 's/$(AMP_PACKAGER_VERSION_TAG)/'$AMP_PACKAGER_VERSION_TAG'/g' \
    > $GENFILES_DIR/amppackager_cert_consumer.yaml
fi

# Build docker images for the Amppackager renewer and consumer, if necessary.
# Renewer and consumer are the same binaries, passed different command line
# arguments. If you don't want to rebuild the binaries, you can comment out the
# next 2 lines as well as the docker images and push commands below.
docker build -f Dockerfile.consumer -t gcr.io/${PROJECT_ID}/amppackager:${AMP_PACKAGER_VERSION_TAG} .
docker build -f Dockerfile.renewer -t gcr.io/${PROJECT_ID}/amppackager_renewer:${AMP_PACKAGER_VERSION_TAG} .

# To check that it succeeded, list the images that got built.
docker images
echo "Does the above look correct? If so, hit enter; else Ctrl-C."
read

# https://cloud.google.com/container-registry/docs/advanced-authentication#gcloud-helper
gcloud auth configure-docker

# Push the docker image into the cloud container registry.
# See: https://cloud.google.com/container-registry/docs/overview
# See: https://cloud.google.com/container-registry/docs/pushing-and-pulling
docker push gcr.io/${PROJECT_ID}/amppackager:${AMP_PACKAGER_VERSION_TAG}
docker push gcr.io/${PROJECT_ID}/amppackager_renewer:${AMP_PACKAGER_VERSION_TAG}

# NOTE: if you have other gcloud projects, you should create/activate an amppkg
# named configuration before calling this command (also gcloud_{up/down}.sh).
# Otherwise it'll muck with your global state.
gcloud config set project $PROJECT_ID
gcloud config set compute/zone $COMPUTE_ENGINE_ZONE

# Allow 10 nodes maximum for this cluster.
echo "Creating kubernetes cluster"
gcloud container clusters create amppackager-cluster --num-nodes=10 --enable-ip-alias --metadata disable-legacy-endpoints=true

# Setup your credentials
# https://cloud.google.com/sdk/gcloud/reference/container/clusters/get-credentials
gcloud container clusters get-credentials amppackager-cluster

# Create the NFS disk for RW sharing amongst the kubernetes deployments
# cert-renewer and cert-consumer.
# https://medium.com/@Sushil_Kumar/readwritemany-persistent-volumes-in-google-kubernetes-engine-a0b93e203180
echo "Creating NFS disk"
gcloud compute disks create --size=10GB --zone=${COMPUTE_ENGINE_ZONE} amppackager-nfs-disk
kubectl apply -f nfs_renewer_pvc.yaml
kubectl apply -f nfs_consumer_pvc.yaml
kubectl apply -f nfs_clusterip_service.yaml
kubectl apply -f nfs_server_deployment.yaml
export AMPPACKAGER_NFS_SERVER=$(kubectl get pods | grep amppackager-nfs | awk '{print $1}')

# Sleep for a few minutes, waiting for NFS disk to be deployed.
sleep 4m

# This assumes current working directory is amppackager/docker/gcloud
# default is the default namespace for the gcloud project
echo "Copying files to NFS mount ..."
kubectl cp www default/"$AMPPACKAGER_NFS_SERVER":/exports/

if [ -f "$GENFILES_DIR/amppkg_consumer.toml" ]; then
  echo "Copying amppkg_consumer.toml to NFS mount"
  kubectl cp $GENFILES_DIR/amppkg_consumer.toml default/"$AMPPACKAGER_NFS_SERVER":/exports
fi

if [ -f "$GENFILES_DIR/amppkg_renewer.toml" ]; then
  echo "Copying amppkg_renewer.toml to NFS mount"
  kubectl cp $GENFILES_DIR/amppkg_renewer.toml default/"$AMPPACKAGER_NFS_SERVER":/exports
fi

if [ -f "$GENFILES_DIR/$AMP_PACKAGER_PRIV_KEY_FILENAME" ]; then
  echo "Copying $GENFILES_DIR/$AMP_PACKAGER_PRIV_KEY_FILENAME to NFS mount"
  kubectl cp "$GENFILES_DIR/$AMP_PACKAGER_PRIV_KEY_FILENAME" default/"$AMPPACKAGER_NFS_SERVER":/exports
fi

if [ -f "$GENFILES_DIR/$AMP_PACKAGER_CSR_FILENAME" ]; then
  echo "Copying $GENFILES_DIR/$AMP_PACKAGER_CSR_FILENAME to NFS mount"
  kubectl cp "$GENFILES_DIR/$AMP_PACKAGER_CSR_FILENAME" default/"$AMPPACKAGER_NFS_SERVER":/exports
fi

if [ -f "$GENFILES_DIR/$AMP_PACKAGER_CERT_FILENAME" ]; then
  echo "Copying $GENFILES_DIR/$AMP_PACKAGER_CERT_FILENAME to NFS mount"
  kubectl cp "$GENFILES_DIR/$AMP_PACKAGER_CERT_FILENAME" default/"$AMPPACKAGER_NFS_SERVER":/exports
fi

kubectl apply -f $GENFILES_DIR/amppackager_cert_renewer.yaml

# Wait until either the cert is present on disk in the NFS mount or X number
# of retries are finished. If cert is being requested via ACME, this may take
# some time.
result=1
retries=0
while true
do
  if [ $result -eq 0 ]; then
    echo "Cert is available!"
    break
  else
    sleep 60
    retries=$((retries+1))
    if [ "$retries" -ge 10 ]; then
      echo "Cert not present, giving up."
      break
    else
      echo "Waiting for cert ..."
    fi
    # TODO(banaag): need to fix hardcoded /exports/amppkg.cert after you
    # decipher kubectl set env craziness.
    kubectl exec -it $AMPPACKAGER_NFS_SERVER -- test -f /exports/amppkg.cert 2> /dev/null
    result=$?
  fi
done

kubectl apply -f $GENFILES_DIR/amppackager_cert_consumer.yaml
kubectl apply -f amppackager_service.yaml

# List the service that got started.
kubectl get service

echo "Setup complete."
