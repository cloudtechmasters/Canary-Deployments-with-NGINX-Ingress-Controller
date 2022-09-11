# Canary Deployments with NGINX Ingress Controller
## Overview
This repository contains all resources that are required to test the canary feature of NGINX Ingress Controller. 


**What are canary releases?**

Canary release is a technique to reduce the risk of introducing a new software version in production by slowly rolling out the change to a small subset of users, before rolling it out to the entire infrastructure and making it available to everybody.

There are two different kind of canary releases.

1. A weight-based canary release that routes a certain percentage of the traffic to the new release
2. Let’s call it — user-based routing where a certain Request Header or value in the Cookies decides which version is being addressed

![image](https://user-images.githubusercontent.com/74225291/189477913-36139cde-e2cc-42be-be06-fca0c018290a.png)

Getting Started with canary rollouts on K8s

Will use option 1 to test the canary implemnetaion in this example.The app used for the scenario is a simple go http server with three handlers.

- **/version** returning the the version of the app that actually processed the request to differentiate between both releases, production and canary.
- **/metrics** to show the amount of calls that have been processed by the container on path /version.
- **/reset**, as the name suggests, resets the request counter to zero.

**Requirements**
 - Kubernetes cluster 
 - helm

**Deploy nginx-ingress controller**

```
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install my-ingress-nginx ingress-nginx/ingress-nginx --version 4.2.5
```

Check the status of ingress controller.

```
$ kubectl get pods
NAME                                           READY   STATUS    RESTARTS   AGE
my-ingress-nginx-controller-86b9f55565-4vznt   1/1     Running   0          32s

$ kubectl get svc
NAME                                    TYPE           CLUSTER-IP       EXTERNAL-IP                                                              PORT(S)                      AGE
my-ingress-nginx-controller             LoadBalancer   10.100.167.211   a67e9bd5912c74b22be1f9b92f11ca88-896411557.us-east-1.elb.amazonaws.com 80:30827/TCP,443:32508/TCP   110s
my-ingress-nginx-controller-admission   ClusterIP      10.100.65.251    <none>                                                                   443/TCP                      111s
```

Create cname record with the ingress load balancer.

<img width="1148" alt="image" src="https://user-images.githubusercontent.com/74225291/189476274-8b7b5522-d58b-4436-bb09-c1314d7a2ef4.png">

## Getting Started

### Canary Test Scenario
##### Prepare Manifests  
First of all, change the host definition in the ingress manifests ***deploy/prod-ingress.yaml*** and ***deploy/canary-ingress.yaml*** from canary-demo.example.com to your URL
  
##### Deploy production release  


**1. Create the status quo**

Everything starts with a stable version running in production. The example follows the semantic versioning approach with current stable version 1.0.0 running in the namespace “demo-prod”. As there is no canary release deployed to the cluster, X equals “0” resulting in 100% of the traffic being served by the production release. This can be simulated with the following ingress manifest:

First of all, deploy the namespace “demo-prod” as it is required for the rest of the resources. Continue with creating the deployment, service, and ingress for the production environment. At this point, there is nothing special about the ingress resource.

```
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    kubernetes.io/ingress.class: "nginx"
  labels:
    app: app
    version: 1.0.0
  name: demo-ingress
  namespace: demo-prod
spec:
  rules:
  - host: test.tushar10pute.click
    http:
      paths:
      - backend:
          service:
             name: demo-prod
             port: 
               number: 80
        path: /
        pathType: Prefix
```

Roll-out the stable version 1.0.0 to the cluster
```bash
  kubectl apply -f ./deploy/prod-namespace.yaml
  kubectl apply -f ./deploy/prod-deployment.yaml,./deploy/prod-service.yaml,./deploy/prod-ingress.yaml  
  sleep 10
  kubectl get deploy,svc,ing -n demo-prod
  
```
  
```
#   kubectl get deploy,svc,ing -n demo-prod
NAME                        READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/demo-prod   1/1     1            1           16s

NAME                TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
service/demo-prod   ClusterIP   10.100.83.121   <none>        80/TCP    16s

NAME                                     CLASS    HOSTS                     ADDRESS   PORTS   AGE
ingress.networking.k8s.io/demo-ingress   <none>   test.tushar10pute.click             80      16s

```

  
##### Run tests  

Execute the following commands to send n=1000 requests to the endpoint

```bash
#!/bin/bash
for i in {1..1000}
do
   curl http://<your_url>/version -s -o /dev/null
done

$ curl -s "http://<your_URL>/metrics" | jq '.calls'
```
If everything is working as expected, the curl command should return "1000".

```
sh test.sh

curl test.tushar10pute.click/metrics
{"calls":1000}
```

<img width="557" alt="image" src="https://user-images.githubusercontent.com/74225291/189476692-8e4141e1-9334-4024-93d3-880075ad97f4.png">


##### Reset request counter  

Send GET requests to /reset endpoint to set the request counter to zero
```bash
$ curl "http://<your_URL>/reset"
```
  
##### Canary deployment  

**2. Rollout the canary release**

Now it is time to do the actual canary deployment. Therefore a second namespace called “demo-canary” is mandatory. Why is that? Eventually, we will create a second ingress resource with the exact same name but including the canary annotations. If we deployed it to one and the same namespace it would change the existing resource which is not desired. Once the namespace has been created, we can push the deployment with the new software version 1.0.1, service, and ingress to the cluster. In the below sample ingress we define X=”20" and thus, route 80% of the workload to the production release which is considered to be stable and the remaining 20% to our freshly deployed canary release.

Therefore, we have to add two annotations. The first one, nginx.ingress.kubernetes.io/canary: “true”, enables the canary functionality for the ingress. Secondly, we define the share that we want to be served by the canary deployment by adding nginx.ingress.kubernetes.io/canary-weight: “20”.

```
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    kubernetes.io/ingress.class: "nginx"
    nginx.ingress.kubernetes.io/canary: "true"
    nginx.ingress.kubernetes.io/canary-weight: "20"
  labels:
    app: demo
  name: demo-ingress
  namespace: demo-canary
spec:
  rules:
  - host: test.tushar10pute.click
    http:
      paths:
      - backend:
          service:
             name: demo-canary
             port:
               number: 80
        path: /
        pathType: Prefix
---
```

Push the new software version 1.0.1 as a canary deployment to the cluster
```bash
  kubectl apply -f ./deploy/canary-namespace.yaml
  kubectl apply -f ./deploy/canary-deployment.yaml,./deploy/canary-service.yaml,./deploy/canary-ingress.yaml
  sleep 15
  kubectl get deploy,svc,ing -n demo-canary
```

```
#   kubectl get deploy,svc,ing -n demo-canary
NAME                          READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/demo-canary   1/1     1            1           18s

NAME                  TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
service/demo-canary   ClusterIP   10.100.11.252   <none>        80/TCP    18s

NAME                                     CLASS    HOSTS                     ADDRESS                                                                  PORTS   AGE
ingress.networking.k8s.io/demo-ingress   <none>   test.tushar10pute.click   a67e9bd5912c74b22be1f9b92f11ca88-896411557.us-east-1.elb.amazonaws.com   80      18s
```

##### Perform tests  
Again, start sending traffic to the endpoint
```bash
#!/bin/bash
for i in {1..1000}
do
   curl http://<your_url>/version
done
```


 
##### Verify the weight split  
Do a port forward to each of the pods to check the request count
```bash
$ kubectl -n demo-prod port-forward <pod-name> 8080:8080
$ curl -s http://localhost:8080/metrics | jq '.calls'
$ kubectl -n demo-prod port-forward <pod-name> 8081:8080
$ curl -s http://localhost:8081/metrics | jq '.calls'
```
Unless the weight has been changed to a different value, you should see approximately 800 requests being served by the production deployment and the remainig 200 by the canary. 

<img width="1274" alt="image" src="https://user-images.githubusercontent.com/74225291/189477595-17fe0fa8-98d6-421e-b8ae-72bc7ddf8e99.png">

<img width="1272" alt="image" src="https://user-images.githubusercontent.com/74225291/189477624-6259b300-3c43-4a05-84b5-77fae982a2c9.png">


Looking at these figures, the weight split involves a slight deviation of roughly 1% compared to the initial 80/20 split. For me, tiny enough to call it a success!

### Delete
Remove all resource from the cluster 
```bash
$ kubectl delete -f ./deploy/.
$ helm uninstall my-ingress-nginx
```
