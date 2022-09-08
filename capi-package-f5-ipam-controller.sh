# Create values yaml
cat <<EOF > f5-ipam-${CLUSTER_NAME}-values.yaml
rbac:
  create: true
serviceAccount:
  create: true
namespace: kube-system
args:
  orchestration: "kubernetes"
  provider: "f5-ip-provider"
  ip_range: '$RANGE'
image:
  # Use the tag to target a specific version of the Controller
  user: f5networks
  repo: f5-ipam-controller
  pullPolicy: Always
  version: 0.1.5
volume:
  mountPath: /app/ipamdb
  mountName: fic-volume-mount
  pvc: fic-volume-claim
EOF


# Create ClusterResourceSet Manifest for F5 IPAM
cat <<EOF > f5-ipam-cluster-resoureset-${CLUSTER_NAME}.yaml
apiVersion: addons.cluster.x-k8s.io/v1beta1
kind: ClusterResourceSet
metadata:
  labels:
    konvoy.d2iq.io/cluster-name: ${CLUSTER_NAME}
  name: f5-ipam-installation-${CLUSTER_NAME}
  namespace: default
spec:
  clusterSelector:
    matchLabels:
      konvoy.d2iq.io/cluster-name: ${CLUSTER_NAME}
      konvoy.d2iq.io/provider: vsphere
  resources:
  - kind: ConfigMap
    name: f5-ipam-config-${CLUSTER_NAME}
  strategy: ApplyAlways
---
EOF

# Get IPAM CRD
curl -s https://raw.githubusercontent.com/F5Networks/f5-ipam-controller/main/docs/_static/schemas/ipam_schema.yaml > f5-ipam-cm.yaml && \

# Generate manifests from helm chart
helm template -f f5-ipam-${CLUSTER_NAME}-values.yaml f5-ipam f5-ipam-stable/f5-ipam-controller --version 0.0.1 | sed -e '/# Source/d' | sed 's/[[:blank:]]*$//' >> f5-ipam-cm.yaml 

# Create manifest for pvc
cat <<EOF >> f5-ipam-cm.yaml 
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: fic-volume-claim
  namespace: kube-system
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 0.1Gi
EOF

#Convert to a configmap and include in the ClusterResourceSet
kubectl create cm f5-ipam-config-${CLUSTER_NAME} --from-file=custom-resources.yaml=f5-ipam-cm.yaml --dry-run=client -o yaml >>f5-ipam-cluster-resoureset-${CLUSTER_NAME}.yaml 
rm -f f5-ipam-cm.yaml 
