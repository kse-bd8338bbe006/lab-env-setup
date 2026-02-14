#!/bin/bash
echo "*** Waiting for Cloud-Init to finish ***"
cloud-init status --wait
echo "*** Kubernetes Pulling Images:"
kubeadm config images pull
echo "*** Kubernetes Initializing:"
# Get the static IP from k8snet or eth1 interface (the one with 192.168.50.x), fallback to first IP
export LOCAL_IP=$(ip -4 addr show k8snet 2>/dev/null | grep -oP '(?<=inet\s)192\.168\.50\.\d+' || ip -4 addr show eth1 2>/dev/null | grep -oP '(?<=inet\s)192\.168\.50\.\d+' || hostname -I | awk '{print $1}')
export HAPROXY_IP=$(cat /tmp/haproxy_ip)
kubeadm init \
  --upload-certs \
  --pod-network-cidr 10.244.0.0/16 \
  --apiserver-advertise-address $LOCAL_IP \
  --control-plane-endpoint $HAPROXY_IP:6443 | tee /tmp/kubeadm.log
echo "*** Setting up kubeconfig:"
mkdir -p $HOME/.kube
cp -f /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config
export KUBECONFIG=$HOME/.kube/config
echo "*** Installing Weave CNI:"
kubectl apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml
echo "*** Waiting for Kubernetes to get ready:"
STATE="NotReady"
while test "$STATE" != "Ready" ; do
STATE=$(kubectl get node | tail -1 | awk '{print $2}')
echo -n "." ; sleep 1
done
echo ""
if grep "kubeadm join" /tmp/kubeadm.log >/dev/null; then
  echo -n '{"join":"'$(kubeadm token create --ttl 0 --print-join-command)'"}' > /etc/join.json
  CERT_KEY=$(kubeadm init phase upload-certs --upload-certs 2>&1 | tail -1)
  echo -n '{"join":"'$(kubeadm token create --ttl 0 --print-join-command)' --control-plane --certificate-key '$CERT_KEY'"}' > /etc/join-master.json
fi
