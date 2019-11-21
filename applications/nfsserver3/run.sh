#!/bin/bash
set -e
 
export_base="/nfsshare/"
chown nobody:nogroup $export_base
chmod 755 $export_base

### Handle `docker stop` for graceful shutdown
function shutdown {
    echo "- Shutting down nfs-server.."
    service nfs-kernel-server stop
    echo "- Nfs server is down"
    exit 0
}

trap "shutdown" SIGTERM
####

echo "Export points:"
# TODO: check on security for exports; we're root squashing (good), 
# and local kube dns won't resolve outside of namespace (good), but
# it may still be possible to address by nfssvc.namespace.svc.cluster.local - 
# this is probably ok (even preferred) if allowed within project, but not between projects. 
echo "$export_base *(rw,sync,insecure,fsid=0,no_subtree_check)" | tee /etc/exports


echo -e "\n- Initializing nfs server.."
rpcbind
service nfs-kernel-server start


echo "- Nfs server is up and running.."

## Run forever
sleep infinity
