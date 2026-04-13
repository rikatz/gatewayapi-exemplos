#!/usr/bin/env bash
#
set -x

BACKEND="${1:-kgateway}"
EXTRA_CONFIG="${EXTRA_CONFIG:-}"
CLUSTER_NAME="${CLUSTER_NAME:-kind}"
GATEWAYAPI_VERSION="${GATEWAYAPI_VERSION:-v1.5.1}"

create_kind() {
  kind create cluster --name=${CLUSTER_NAME} ${EXTRA_CONFIG}
}

deploy_crds() {
  kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAYAPI_VERSION}/standard-install.yaml
}

deploy_metallb() {
  kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.15.2/config/manifests/metallb-native.yaml
  kubectl wait --timeout=5m deploy -n metallb-system controller --for=condition=Available
  kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  namespace: metallb-system
  name: kube-services
spec:
  addresses:
  - 172.18.200.100-172.18.200.150
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: kube-services
  namespace: metallb-system
spec:
  ipAddressPools:
  - kube-services
EOF
}


case $BACKEND in
  "cilium")
	EXTRA_CONFIG="--config=kind-cilium.yaml"
	create_kind
	deploy_crds
	helm install cilium --namespace kube-system --version 1.19.1 \
	  --set image.pullPolicy=IfNotPresent --set ipam.mode=kubernetes \
	  --set gatewayAPI.enabled=true --set nodePort.enabled=true \
	  --set kubeProxyReplacement=true \
	  --set k8sServiceHost=kind-control-plane \
	  --set k8sServicePort=6443 \
	  --set operator.replicas=1 \
	  --set serviceAccounts.cilium.name=cilium \
	  --set serviceAccounts.operator.name=cilium-operator \
	  cilium --repo https://helm.cilium.io
    	kubectl wait --timeout=5m -n kube-system deployment/cilium-operator --for=condition=Available
    	kubectl wait --timeout=5m -n kube-system deployment/coredns --for=condition=Available
	deploy_metallb
	;;

   "istio")
	create_kind
	deploy_crds
	deploy_metallb
  	TAG=$(curl https://storage.googleapis.com/istio-build/dev/latest)
  	wget -c https://storage.googleapis.com/istio-build/dev/$TAG/istioctl-$TAG-linux-amd64.tar.gz
  	tar -xvf istioctl-$TAG-linux-amd64.tar.gz
	./istioctl install --set values.pilot.env.PILOT_ENABLE_ALPHA_GATEWAY_API=${EXPERIMENTAL} --set values.pilot.env.ENABLE_GATEWAY_API_INFERENCE_EXTENSION=true --set profile=minimal --skip-confirmation
	;;

    "kgateway")
	create_kind
	deploy_metallb
	deploy_crds
	helm upgrade -i --create-namespace --namespace kgateway-system --version v2.3.0-main \
    	  kgateway-crds oci://cr.kgateway.dev/kgateway-dev/charts/kgateway-crds \
          --set controller.image.pullPolicy=Always
  	helm upgrade -i --namespace kgateway-system --version v2.3.0-main \
    	  kgateway oci://cr.kgateway.dev/kgateway-dev/charts/kgateway \
          --set controller.image.pullPolicy=Always
	;;
    *)
    	echo "Invalid backend"
	exit 1
	;;
esac

kubectl apply -f infrastructure/00-namespaces.yaml

# Generate certs just for demo
openssl req -x509 -newkey rsa:4096 -sha256 -days 365 -nodes \
  -keyout keys/tls.key -out keys/tls.crt -subj "/CN=*.example.com" \
  -addext "subjectAltName=DNS:example.com,DNS:*.example.com"

kubectl create secret tls -n gateway-ns certificate --cert keys/tls.crt --key keys/tls.key

# Generate the certificate on user namespace
openssl req -x509 -newkey rsa:4096 -sha256 -days 365 -nodes \
  -keyout keys/user01-tls.key -out keys/user01-tls.crt -subj "/CN=*.user01.com" \
  -addext "subjectAltName=DNS:user01.com,DNS:*.user01.com"

kubectl create secret tls -n user01 certificate --cert keys/user01-tls.crt --key keys/user01-tls.key

# Generate the certificate for TLSRoute
openssl req -x509 -newkey rsa:4096 -sha256 -days 365 -nodes \
  -keyout keys/user02-tls.key -out keys/user02-tls.crt -subj "/CN=tls.user02.com" \
  -addext "subjectAltName=DNS:tls.user02.com"

kubectl create secret tls -n user02 cert-tlspassthrough --cert keys/user02-tls.crt --key keys/user02-tls.key

kubectl apply -f infrastructure/