#!/bin/bash
set -e

#############################
# These you'll want to set
#############################
APPNAME=ex2
HOMEDRIVE_SIZE=4Gi
ADMIN_USERS="oneils, smithj"

MEM_GUARANTEE=0.5G
MEM_LIMIT=1G
CPU_GUARANTEE=0.1
CPU_LIMIT=1

# can be native, lti, or dummy
AUTH_TYPE=native
NUM_PLACEHOLDERS=0

#########################
# these less so
#########################
HOSTNAME=devb.datasci.oregonstate.edu
BASE_URL="/$APPNAME/"
HOMEDRIVE_APPNAME="homedrive-$APPNAME"
HUB_APPNAME="hub-$APPNAME"
NAMESPACE=$APPNAME

SCRIPT_DIR=$(dirname $0)
DRIVE_CHART=$SCRIPT_DIR/../../charts/drive/latest
HUB_CHART=$SCRIPT_DIR/../../charts/ds-jupyterlab/latest


##########################
# dirty work happens below
##########################

source ../colors.sh

cat <<EOF > 1-drive.yaml
size: $HOMEDRIVE_SIZE
EOF

cat <<EOF > 2-hub.yaml
jupyterhub:
  hub:
    extraEnv:
      AUTH_TYPE: $AUTH_TYPE                               # native, lti, or dummy
      LTI_CLIENT_KEY: $(openssl rand -hex 32)         # used if using LTI auth
      LTI_CLIENT_SECRET: $(openssl rand -hex 32)
      ADMIN_USERS: "$ADMIN_USERS"
    baseUrl: "$BASE_URL"   # must start and end with a /

  scheduling:
    userPlaceholder:
      enabled: true
      replicas: $NUM_PLACEHOLDERS

  cull:
    enabled: true
    timeout: 3600        # cull inactive servers after this long
    maxAge: 28800        # cull servers this old, even if active (0 disables)

  proxy:
    secretToken: $(openssl rand -hex 32)

  singleuser:
    # looks like these should be set null to delete the key (including those defaulted in the jupyterhub chart) for the c.Spawner limits below to be used
    memory:
      limit: "$MEM_LIMIT"
      guarantee: "$MEM_GUARANTEE"
    cpu:
      limit: $CPU_LIMIT
      guarantee: $CPU_GUARANTEE
    image:
      name: oneilsh/ktesting-datascience-notebook
      tag: "1d47a65a" 
    defaultUrl: "/lab"

    extraEnv:
      NFS_SVC_HOME: $HOMEDRIVE_APPNAME   # same as above

    uid: 0
    fsGid: 0

  ingress:
    hosts:
    - $HOSTNAME
    tls:
    - hosts:
      - $HOSTNAME
EOF



cat <<EOF > 1-create-drive.sh
#!/bin/bash
helm upgrade $HOMEDRIVE_APPNAME $DRIVE_CHART --namespace $NAMESPACE --atomic --cleanup-on-fail --install --values 1-drive.yaml
EOF

chmod u+x 1-create-drive.sh



cat <<EOF > 2-create-hub.sh
#!/bin/bash
helm upgrade $HUB_APPNAME $HUB_CHART --namespace $NAMESPACE --atomic --cleanup-on-fail --install --values 2-hub.yaml
EOF

chmod u+x 2-create-hub.sh

cat <<EOF > status.sh
#!/bin/bash
black="\$(tput setaf 0)"
red="\$(tput setaf 1)"
green="\$(tput setaf 2)"
yellow="\$(tput setaf 3)"
blue="\$(tput setaf 4)"
magenta="\$(tput setaf 5)"
cyan="\$(tput setaf 6)"
white="\$(tput setaf 7)"

echo "\$green Helm release list: \$white"
helm list --namespace $NAMESPACE
echo ""

echo "\$green Kubernetes resources:\$white"
kubectl get all --namespace $NAMESPACE
echo ""

echo "\$green Kubernetes PVCs:\$white"
kubectl get pvc --namespace $NAMESPACE
echo ""

echo "\$green Kubernetes PVs:\$white"
kubectl get pv | grep -E "[[:blank:]]$NAMESPACE\/"
echo ""

EOF

chmod u+x status.sh


cat <<EOF > teardown.sh
#!/bin/bash

black="\$(tput setaf 0)"
red="\$(tput setaf 1)"
green="\$(tput setaf 2)"
yellow="\$(tput setaf 3)"
blue="\$(tput setaf 4)"
magenta="\$(tput setaf 5)"
cyan="\$(tput setaf 6)"
white="\$(tput setaf 7)"

if kubectl get pods --selector=component=singleuser-server --namespace $NAMESPACE 2> /dev/null | grep -q jupyter; then
  echo "\${red}Warning: This will kill the following user containers and delete all data for $APPNAME: \${white}"
  kubectl get pods --selector=component=singleuser-server --namespace $NAMESPACE
else 
  echo "\${red}Warning: This will delete all data for $APPNAME. \${white}"
fi

echo -n "\${yellow}Type the APPNAME ($APPNAME) to continue: \${white}"
read CHECKNAME
if [ \${CHECKNAME} != $APPNAME ]; then
  echo "No match, exiting."
  exit 1
fi

echo -n "Ok, removing in ";
for i in \$(seq 5 1); do
  echo -n "\$i... "
  sleep 1
done
echo ""
echo ""

if kubectl get pods --selector=component=singleuser-server --namespace $NAMESPACE 2> /dev/null | grep -q jupyter; then
  echo "\${yellow}Deleting user containers... \$white"
  echo "\${magenta}kubectl delete pods --selector=component=singleuser-server --namespace $NAMESPACE \${white}"
  kubectl delete pods --selector=component=singleuser-server --namespace $NAMESPACE
  echo ""
fi

echo "\${yellow}Deleting hub resources... \${white}"
echo "\${magenta}helm delete $HUB_APPNAME --namespace $NAMESPACE \${white}"
helm delete $HUB_APPNAME --namespace $NAMESPACE
echo ""

echo "\${yellow}Deleting drive containers... \${white}"
echo "\${magenta}helm delete $HOMEDRIVE_APPNAME --namespace $NAMESPACE \${white}"
helm delete $HOMEDRIVE_APPNAME --namespace $NAMESPACE
echo ""

PVCNAME=\$(kubectl get pvc --namespace $NAMESPACE | grep $HOMEDRIVE_APPNAME | awk '{print \$1}')
PVNAME=\$(kubectl get pvc --namespace $NAMESPACE | grep $HOMEDRIVE_APPNAME | awk '{print \$3}')

echo "\${yellow}Deleting drive PVC... \${white}"
echo "\${magenta}kubectl delete pvc \$PVCNAME --namespace $NAMESPACE \${white}"
kubectl delete pvc \$PVCNAME --namespace $NAMESPACE
echo ""

echo "\${yellow}Deleting drive PV... \${white}"
echo "\${magenta}kubectl delete pv \$PVNAME \${white}"
kubectl delete pv \$PVNAME
echo ""

echo "\${yellow}Deleting namespace... \${white}"
echo "\${magenta}kubectl delete namespace $NAMESPACE \${white}"
kubectl delete namespace $NAMESPACE
echo ""

EOF
 

chmod u+x teardown.sh

####
# do iiiiit
####


# create namespace if it doesn't exist
echo "$yellow Checking namespace: $white"
kubectl create namespace $NAMESPACE || true     # don't allow the set -e to take effect here
echo ""

echo "$yellow Running 1-create-drive.sh...$white"
#./1-create-drive.sh
echo ""

echo "$yellow Running 2-create-hub.sh...$white"
#./2-create-hub.sh
echo ""

echo "$green Finished! Your hub is at $blue https://$HOSTNAME$BASE_URL $white"
