
# Deep Dive: Blue/Green Deployments with Kubernetes and Istio

### A tutorial to explore how to provide Blue/Green deployments using Istio on a Kubernetes cluster

## Preconditions:

* Linux, Windows or macOS host with at least 12GB RAM
* VirtualBox - https://www.virtualbox.org
* Docker Toolbox (Windows or macOS host) - https://docs.docker.com/toolbox/overview/
* Docker CE (Linux host) - https://docs.docker.com/install/
* Minikube - https://kubernetes.io/docs/setup/minikube/
* Istio - https://github.com/istio/istio/releases
* Git for Windows (Windows host only) - https://github.com/git-for-windows/git/releases/

Istio is a service mesh designed to make communication among microservices reliable, transparent, and secure. Istio intercepts the external and internal traffic targeting the services deployed in container platforms such as Kubernetes.

Though Istio is capable of many things including secure service-to-service communication, automated logging of metrics, enforcing a policy for access controls, rate limits, and quotas, we will focus exclusively on the traffic management features.

Istio lets DevOps teams create rules to intelligently route the traffic to internal services. It is extremely simple to configure service-level properties like circuit breakers, timeouts, and retries, to set up a variety of deployment patterns including blue/green deployments and canary rollouts.

The objective of this tutorial is to help you understand how to configure Blue/Green deployments of microservices running in Kubernetes with Istio. You don't need to have any prerequisites to explore this scenario except a basic idea of deploying pods and services in Kubernetes. We will configure everything from Minikube to Istio to the sample application.

There are four steps to this tutorial – Installing and configuring Minikube, installing and verifying Istio, deploying two versions of the same app, and finally configuring the services for blue/green deployments. We will use two simple, pre-built container images that represent blue (v1) and green (v2) releases.

All commands issued in this tutorial must be typed on a Bash shell. If your host is based on Windows, you can use the Bash shell provided by Git for Windows.

## Step 1: Install and Configure Minikube

To minimize the dependencies, we will use Minikube as the testbed for our setup, and configure it to use VirtualBox as the hypervisor. Since we need a custom configuration of Minikube, start by deleting any existing setup and restarting the cluster with additional parameters:

```sh
$ minikube stop
$ minikube delete
$ cd
$ rm -Rf .kube
$ rm -Rf .minikube

$ minikube config set vm-driver virtualbox
$ minikube config set memory 8192
$ minikube config set disk-size 80G
$ minikube config set cpus 4

$ minikube config view
    
$ minikube start --kubernetes-version=v1.10.0
```

We need at least 8GB of RAM and 4 core CPU to run Istio on Minikube. Wait for the cluster to start.

![][1]

In a terminal, it is also useful to set the Minikube Docker environment:

```sh
$ eval $(minikube docker-env)
```

This way, we will be able to use Docker commands targeted to the Minikube Docker Machine, e.g.:

```sh
$ docker images
```

![][2]

## Step 2: Install Istio

With Kubernetes up and running, it's time for us to install Istio. Follow the below steps to configure it.
    
```sh
$ curl -L https://git.io/getLatestIstio | sh -
```

You will find a folder, istio-1.0.2 at the time of writing, in the same directory where you ran the above command. Add the location istio-1.0.2/bin to the PATH variable to make it easy to access Istio binaries.

If you are using Windows, you can download the binary package in your browser (see above link) and manually decompress it. Keep in mind that Istio is going to be run inside Kubernetes, and not directly in out host machine.

Since we are running Istio with Minikube, we need to make one change before going ahead with the next step – changing the Ingress Gateway service from type LoadBalancer to NodePort.

Open the file istio-1.0.2/install/kubernetes/istio-demo.yaml, search for **LoadBalancer** and replace it with **NodePort**.

![][3]

Istio comes with many Custom Resource Definitions (CRD) for Kubernetes. They help us manipulate virtual services, rules, gateways, and other Istio-specific objects from kubectl. Let's install the CRDs before deploying the actual service mesh.

From a terminal, move to the chosen Istio base directory and type:
    
```sh
$ kubectl apply -f install/kubernetes/helm/istio/templates/crds.yaml
```
    
Finally, let's install Istio within Kubernetes.
    
```sh
$ kubectl apply -f install/kubernetes/istio-demo.yaml
```

The above step results in the creation of a new namespace – **istio-system** – under which multiple objects get deployed.

```sh
$ kubectl get namespaces
```

![][4]

We will notice multiple services created within the **istio-system** namespace:

```sh
$ kubectl get services -n=istio-system -o=custom-columns=NAME:.metadata.name,IP:.spec.clusterIP
```

![][5]

After a few minutes, you will see multiple pods deployed by Istio. Verify this by running:

```sh
$ kubectl get pods -n=istio-system
```

![][6]

All the pods must be in running or complete mode, which indicates that Istio is successfully installed and configured.

Note that Minikube installs off-the-shelf the Kubernetes web dashboard, which can be accessed through command:

```sh
$ minikube dashboard
```

on the default browser:

![][7]

Now, we are ready to deploy and configure services for the Blue/Green pattern.

## Step 3: Deploying two versions of the same application

To represent two different versions of the applications, we build simple Nginx-based Docker images – myapp:v1 and myapp:v2.

```sh
$ docker build -t myapp:v1 . -f Dockerfile-blue
$ docker build -t myapp:v2 . -f Dockerfile-green
```

When deployed, they show a static page with a blue or green background. We will use these images for the tutorial.
    
```yaml
apiVersion: v1
kind: Service
metadata:
  name: myapp
  labels:
    app: myapp
spec:
  type: ClusterIP
  ports:
  - port: 80
    name: http
  selector:
    app: myapp
---
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: myapp-v1
spec:
  replicas: 1
  template:
    metadata:
      labels:
        app: myapp
        version: v1
    spec:
      containers:
      - name: myapp
        image: myapp:v1
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 80
---
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: myapp-v2
spec:
  replicas: 1
  template:
    metadata:
      labels:
        app: myapp
        version: v2
    spec:
      containers:
      - name: myapp
        image: myapp:v2
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 80
```

Let's start by creating a YAML file that defines the deployments for v1 and v2 along with a ClusterIP that exposes them. Notice the labels used for identifying the pods – app and version. While the app name remains the same the version is different between the two deployments.

This is expected by Istio to treat them as a single app but to differentiate them based on the version.

Same is the case with the ClusterIP service definition. Due the label, _app: myapp_, it is associated with the pods from both the deployments based on different versions.

Create the deployment and the service with kubectl. Note that these are simple Kubernetes objects with no knowledge of Istio. The only connection with Istio is the way we created the labels for the deployments and the service.
    
```sh
$ kubectl apply -f myapp.yaml
```

![][8]

Before configuring Istio routing, let's check out the versions of our app. We can port-forward the deployments to access the pods.

To access v1 of the app, run the below command and hit localhost:8080. Hit CTRL+C when you are done.
    
```sh
$ kubectl port-forward deployment/myapp-v1 8080:80
```

![][9]

For v2, run the below command and hit localhost:8081. Hit CTRL+C when you are done.
    
```sh
$ kubectl port-forward deployment/myapp-v2 8081:80
```

![][10]

## Step 4: Configuring Blue/Green Deployments

Our goal is to drive the traffic selectively to one of the deployments with no downtime. To achieve this, we need to tell Istio to route the traffic based on the weights.

There are three objects involved in making this happen:

### **Gateway**  
An Istio _Gateway_ describes a load balancer operating at the edge of the mesh receiving incoming or outgoing HTTP/TCP connections. The specification describes a set of ports that should be exposed, the type of protocol to use, SNI configuration for the load balancer, etc. In the below definition, we are pointing the gateway to the default Ingress Gateway created by Istio during the installation.

Let's create the gateway as a Kubernetes object.
    
```yaml
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: app-gateway
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "*"
```

### **Destination Rule**  
An Istio _DestinationRule_ defines policies that apply to traffic intended for a service after routing has occurred. Notice how the rule is declared based on the labels defined in the original Kubernetes deployment.

```yaml
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: myapp
spec:
  host: myapp
  subsets:
  - name: v1
    labels:
      version: v1
  - name: v2
    labels:
      version: v2
```

### **Virtual Service**  
A _VirtualService_ defines a set of traffic routing rules to apply when a host is addressed. Each routing rule defines matching criteria for traffic of a specific protocol. If the traffic is matched, then it is sent to a named destination service based on a version.

In the below definition, we are declaring the weights as 50 percent for both v1 and v2, which means the traffic will be evenly distributed.
    
```yaml
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: myapp
spec:
  hosts:
  - "*"
  gateways:
  - app-gateway
  http:
    - route:
      - destination:
          host: myapp
          subset: v1
        weight: 50
      - destination:
          host: myapp
          subset: v2
        weight: 50        
```

We can define all the above in one YAML file that can be used from kubectl. This YAML statements are gathered in _app-gateway.yaml_.
    
```sh
$ kubectl apply -f app-gateway.yaml 
```

![][11]

Now, let's go ahead and access the service. Since we are using Minikube with NodePort, we need to get the exact port on which the Ingress Gateway is running.

Run the below commands to access the Ingress Host (Minikube) and Ingress port.

```sh
$ export INGRESS_HOST=$(minikube ip)
    
$ export INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')
```

If you access the URI from the browser, you will see the traffic getting routed evenly between blue and green pages.

We can also see the result from a terminal window. Run the below command from the terminal window to see alternating response from v1 and v2:
    
```sh
while : ; do \
  export GREP_COLOR='1;33'; \
  curl -s $INGRESS_HOST:$INGRESS_PORT | grep --color=always "v1"; \
  export GREP_COLOR='1;36'; \
  curl -s $INGRESS_HOST:$INGRESS_PORT | grep --color=always "v2"; \
  sleep 1; \
done
```

![][12]

While the above command is running in a loop, let's go back to the app-gateway.yaml file to adjust the weights. Set the weight of v1 to 0 and v2 to 100.

Submit the new definition to Istio.
    
```sh
$ istioctl replace -f app-gateway.yaml
```

![][13]

Immediately after updating the weights, v2 will get 100 percent of the traffic. This is visible from the output of the first terminal window.

![][14]

You can continue to adjust the weights and watch the traffic getting rerouted dynamically without incurring any downtime.

[1]: ./images/istio-001.png
[2]: ./images/istio-002.png
[3]: ./images/istio-003.png
[4]: ./images/istio-004.png
[5]: ./images/istio-005.png
[6]: ./images/istio-006.png
[7]: ./images/istio-007.png
[8]: ./images/istio-008.png
[9]: ./images/istio-009.png
[10]: ./images/istio-010.png
[11]: ./images/istio-011.png
[12]: ./images/istio-012.png
[13]: ./images/istio-013.png
[14]: ./images/istio-014.png