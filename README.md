# F5 Big IP and Kubernetes LB Service Integration

This project lists steps to tightly integrate F5 with an on-prem kubernetes cluster to provision services of type LoadBalancer 

## Requirements
1. Pre-configured F5 BIG cluster 
2. F5 Partition that will be managed by this automation along with credentials for a service account that has admin permissions for the given partition
3. AS3 3.39 or newer installed on the F5 cluster
4. IP's availble to be used as VIPs
5. Working Kubernetes cluster with PV Storage configured
6. If using the CAPI steps then a CAPI bootstrap/management cluster and configurations to deploy a cluster. Refer [DKP](https://docs.d2iq.com/dkp/latest/infrastructure-quick-start-guides) documentation for more details.
7. This uses `docker.io/f5networks/f5-ipam-controller:0.1.5` & `docker.io/f5networks/k8s-bigip-ctlr:2.9.1` images. Download, retag and push the images to a local registry and change the deployment spec to point to a local image registry for airgapped environments.

>Versions used to test:
>- BIG-IP: 16.1.3.1 Build 0.0.11 Point Release 1
>- AS3: v3.39.0
>- BIG-IP-CTLR: 2.9.1


## Steps
Here are the steps to be performed for a kubernetes cluster that is to be integrated with F5 Big IP to provision services of type LoadBalancer. There are two options based on whether F5 controllers are to be directly deployed to the target cluster or deployed via ClusterResourceSets for a CAPI provisioned cluster either at cluter creation time or after the cluster has been deployed.

<br/>

### Option 1: Directly deploy F5 Controllers to a Kubernetes Cluster
<br/>

#### Step 1: Deploy F5 Big IP Container Ingress Services (CIS)

<br/>

##### - Add helm repo
```
helm repo add f5-stable https://f5networks.github.io/charts/stable
```

##### - Create values yaml

```
export BIG_IP_URL=https://big-ip-host
export BIG_IP_PARTITION=big-ip-partition
export CLUSTER_NAME=cluster-name

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
```

##### - Install

```
export F5_USER=f5-user
export F5_PASSWD=f5-password
export KUBECONFIG=kubeconfig-file-path

kubectl create secret generic f5-bigip-ctlr-login -n kube-system --from-literal=username=${F5_USER} --from-literal=password=${F5_PASSWD} 

helm install -f f5-${CLUSTER_NAME}-values.yaml f5ctlr f5-stable/f5-bigip-ctlr --version 0.0.21
```
<br/>

### Step 2: Deploy F5 IPAM Controller (FIC)

##### - Add helm repo
```
helm repo add f5-ipam-stable https://f5networks.github.io/f5-ipam-controller/helm-charts/stable
```

##### - Create values yaml

```
export RANGE='{"ingress":"172.16.1.1-172.16.1.5"}'
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
```
>The RANGE variable contains key/value pairs for labels and the IP ranges to be served by the IPAM controller. The range used here should be a valid reserved IP range.

##### - Install

```
export KUBECONFIG=kubeconfig-file-path

# Create PVC
kubectl apply -f - <<EOF
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

# Install
kubectl create -f https://raw.githubusercontent.com/F5Networks/f5-ipam-controller/main/docs/_static/schemas/ipam_schema.yaml

helm install -f f5-ipam-${CLUSTER_NAME}-values.yaml f5-ipam  f5-ipam-stable/f5-ipam-controller --version 0.0.1
```
<br/>
<br/>

### Option 2: Deploy Automatically via CAPI 
>Note: If deploying to a CAPI provisioned Kubernetes Cluster like [DKP](https://docs.d2iq.com/dkp/latest/infrastructure-quick-start-guides) instead of running the install command manually, the above can be packaged into a CAPI ClusterResourceSet by doing the following and incorporated into the cluster deployment process.

<br/>

#### Pre-step
Create a directory with the name of the cluster and move to that directory so that all the artifacts are generated there

```
export CLUSTER_NAME=cluster-name
mkdir $CLUSTER_NAME && cd CLUSTER_NAME
```

If not already done generate CAPI cluster manifest.
>Hint: Use [DKP](https://docs.d2iq.com/dkp/latest/infrastructure-quick-start-guides) to easily generate one  

#### Step 1: Deploy F5 Big IP Container Ingress Services (CIS)

<br/>

```
export CLUSTER_NAME=cluster-name
export BIG_IP_URL=https://big-ip-host
export BIG_IP_PARTITION=big-ip-partition
export F5_USER=f5-user
export F5_PASSWD=f5-password

# Run script to generate ClusterResourceSet manifest to deploy F5 CIS
. ./capi-package-f5-controller.sh

```
>The above will generate `f5-cluster-resoureset-${CLUSTER_NAME}.yaml`

### Step 2: Deploy F5 IPAM Controller (FIC)
```
export CLUSTER_NAME=cluster-name
export RANGE='{"ingress":"172.16.1.1-172.16.1.5"}'

# Run script to generate ClusterResourceSet manifest to deploy F5 FIC
. ./capi-package-f5-ipam-controller.sh
```

>The above will generate `f5-ipam-cluster-resoureset-${CLUSTER_NAME}.yaml`

Now deploy the `f5-cluster-resoureset-${CLUSTER_NAME}.yaml` and ``f5-ipam-cluster-resoureset-${CLUSTER_NAME}`.yaml` manifest created above to the CAPI bootstrap/management cluster using `kubectl create -f` command along with the new cluster specs (i.e. the specs created using the `dkp create cluster` command).

e.g.
```
kubectl create -f *
```
