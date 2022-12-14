# F5 BIG-IP and Kubernetes LB Service Integration

This project lists steps to tightly integrate F5 with an on-prem kubernetes cluster to provision services of type LoadBalancer 

## Requirements
1. Pre-configured F5 BIG-IP cluster 
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
Here are the steps to be performed for a kubernetes cluster that is to be integrated with F5 Big-IP to provision services of type LoadBalancer. There are two options based on whether F5 CIS & FIC Controllers are to be directly deployed to the target cluster or deployed via ClusterResourceSets for a CAPI provisioned cluster either at cluter creation time or after the cluster has been deployed.

<br/>

### Option 1: Directly deploy F5 CIS & FIC Controllers to a Kubernetes Cluster
<br/>

#### Step 1: Deploy F5 BIG-IP Container Ingress Services (CIS)

<br/>

##### - Add helm repo
```
helm repo add f5-stable https://f5networks.github.io/charts/stable
```

##### - Create values yaml

```
export BIG_IP_URL=https://big-ip-host
export BIG_IP_PARTITION=big-ip-partition
export CLUSTER_NAME=dkp-demo

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
export RANGE='{"ingress":"144.217.53.168-144.217.53.169"}' 
#Note the name of the range label here as the service must be annotated with the same to bind the service with a defined range. e.g. `cis.f5.com/ipamLabel: ingress`. There can be multiple ranges defined, identified by their label.
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
mkdir $CLUSTER_NAME && cd $CLUSTER_NAME
```

Clone this repository into that directory

```
git clone https://github.com/arbhoj/f5-k8s-lb-svc.git
```

If not already done generate CAPI cluster manifest.
>Hint: Use [DKP](https://docs.d2iq.com/dkp/latest/infrastructure-quick-start-guides) to easily generate one  

#### Step 1: Deploy F5 BIG-IP Container Ingress Services (CIS)

<br/>

>Note: Ensure that KUBECONFIG is pointing to the bootstrap/management cluster that is managing the lifecycle of the target cluster to which the F5 CIS & FIC Controllers are being deployed

```
export CLUSTER_NAME=cluster-name
export BIG_IP_URL=https://big-ip-host
export BIG_IP_PARTITION=big-ip-partition
export F5_USER=f5-user
export F5_PASSWD=f5-password

# Run script to generate ClusterResourceSet manifest to deploy F5 CIS
. f5-k8s-lb-svc/capi-package-f5-controller.sh

```
>The above will generate `f5-cluster-resoureset-${CLUSTER_NAME}.yaml`

### Step 2: Deploy F5 IPAM Controller (FIC)
```
export CLUSTER_NAME=cluster-name
export RANGE='{"ingress":"144.217.53.168-144.217.53.169"}'
#Note the name of the range label here as the service must be annotated with the same to bind the service with a defined range. e.g. `cis.f5.com/ipamLabel: ingress`. There can be multiple ranges defined, identified by their label.

# Run script to generate ClusterResourceSet manifest to deploy F5 FIC
. f5-k8s-lb-svc/capi-package-f5-ipam-controller.sh
```

>The above will generate `f5-ipam-cluster-resoureset-${CLUSTER_NAME}.yaml`

Now deploy the `f5-cluster-resoureset-${CLUSTER_NAME}.yaml` and ``f5-ipam-cluster-resoureset-${CLUSTER_NAME}`.yaml` manifest created above to the CAPI bootstrap/management cluster using `kubectl create -f` command along with the new cluster specs (i.e. the specs created using the `dkp create cluster` command).

e.g.
```
kubectl create -f .
```
This will deploy the cluster along with the F5 CIS & FIC Controllers fully configured

<br/>
<br/>

## Test

Once the cluster is deployed successfully test by deploying an nginx service

Set KUBECONFIG to point to the target managed cluster where the F5 CIS & FIC Controllers where deployed.
> If using [DKP](https://docs.d2iq.com/dkp/latest/dkp-get-kubeconfig) the kubeconfig of the cluster can be retrieved by using the following command

```
dkp get kubeconfig -c ${CLUSTER_NAME} > ${CLUSTER_NAME}.conf

#Set KUBECONFIG
export KUBECONFIG=$(pwd)/${CLUSTER_NAME}.conf
```

Now deploy the test service

```
kubectl create deploy nginx --image nginx:alpine
kubectl create service loadbalancer nginx --tcp=80:80 --dry-run=client -o json | kubectl patch -f - --local -p '{"metadata": {"annotations": {"cis.f5.com/ipamLabel": "ingress", "cis.f5.com/health": "{\"interval\": 10, \"timeout\": 31}"}}}' --dry-run=client -o yaml | kubectl apply -f -
```

- Verify

```
kubectl get svc nginx

```

Sample Output

```
k get svc
NAME         TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)        AGE
kubernetes   ClusterIP      10.96.0.1       <none>           443/TCP        6d21h
nginx        LoadBalancer   10.104.32.108   144.217.53.169   80:31444/TCP   34s
```

Now login to F5 portal and verify
![F5 Portal](./F5-Auto.png)

Test Service via Loadbalancer VIP (i.e. using the value of the `EXTERNAL-IP` field)
```
curl http://144.217.53.169 #This should respond with the nginx default page
```

> For a service of type LoadBalancer to bind to a given IPAM range, annotate that service as shown below. Where `ingress` is the name of the label associated with the range to pick the IP from. This must match one of the ranges defined when deploying the F5 IPAM controller.
> ```
> cis.f5.com/ipamLabel: ingress
> cis.f5.com/health: '{"interval": 10, "timeout": 31}'
> ```
