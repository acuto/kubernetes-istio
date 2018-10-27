#!/bin/sh

export INGRESS_HOST=$(minikube ip)
export INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')

while : ; do \
    export GREP_COLOR='1;33'; \
    curl -s $INGRESS_HOST:$INGRESS_PORT | grep --color=always "v1"; \
    export GREP_COLOR='1;36'; \
    curl -s $INGRESS_HOST:$INGRESS_PORT | grep --color=always "v2"; \
    sleep 1; \
done
