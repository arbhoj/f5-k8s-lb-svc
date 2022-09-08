#!/bin/sh
#Create values yaml
cat <<EOF > f5-${CLUSTER_NAME}-values.yaml
bigip_login_secret: f5-bigip-ctlr-login
rbac:
  create: true
serviceAccount:
  create: true
namespace: kube-system
args:
  bigip_url: ${BIG_IP_URL}
  bigip_partition: ${BIG_IP_PARTITION}
  log_level: info  
  pool_member_type: nodeport
  insecure: true
  custom-resource-mode: true
  log-as3-response: true
  ipam : true
image:
  # Use the tag to target a specific version of the Controller
  user: f5networks
  repo: k8s-bigip-ctlr
  pullPolicy: Always
resources: {}
version: 2.9.1
EOF

# Create ClusterResourceSet Manifest
cat <<EOF > f5-cluster-resoureset-${CLUSTER_NAME}.yaml
apiVersion: addons.cluster.x-k8s.io/v1beta1
kind: ClusterResourceSet
metadata:
  labels:
    konvoy.d2iq.io/cluster-name: ${CLUSTER_NAME}
  name: f5-installation-${CLUSTER_NAME}
  namespace: default
spec:
  clusterSelector:
    matchLabels:
      konvoy.d2iq.io/cluster-name: ${CLUSTER_NAME}
      konvoy.d2iq.io/provider: vsphere
  resources:
  - kind: ConfigMap
    name: f5-config-${CLUSTER_NAME}
  strategy: ApplyAlways
---
EOF

# Create F5 Deployment Configmap and inject that into ClusterResourceSet manifest file
helm template -f f5-${CLUSTER_NAME}-values.yaml \
f5ctlr f5-stable/f5-bigip-ctlr --version 0.0.21| \
sed -e '/# Source/d' | \
sed 's/[[:blank:]]*$//' > f5-cm.yaml && \
echo "---" >> f5-cm.yaml && \
kubectl create secret generic f5-bigip-ctlr-login -n kube-system --from-literal=username=${F5_USER} --from-literal=password=${F5_PASSWD} --dry-run=client -o yaml >> f5-cm.yaml && \
kubectl create cm f5-config-${CLUSTER_NAME} --from-file=custom-resources.yaml=f5-cm.yaml --dry-run=client -o yaml >>f5-cluster-resoureset-${CLUSTER_NAME}.yaml  && \
rm f5-cm.yaml 
