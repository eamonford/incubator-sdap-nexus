# ELB and ingress controller setup (for system admins)

## 0. Prerequisites
1. `aws-login-pub.py` script is installed, and you are authenticated in a master role
2. SSL cert created
3. ELB security group created

## 1. Make sure Helm 2 is installed
Check if whether Helm is installed by running `helm version`. The response should look something like this:
```
Client: &version.Version{SemVer:"v2.16.1", GitCommit:"bbdfe5e7803a12bbdf97e94cd847859890cf4050", GitTreeState:"clean"}
Server: &version.Version{SemVer:"v2.16.1", GitCommit:"bbdfe5e7803a12bbdf97e94cd847859890cf4050", GitTreeState:"clean"}
```
If this is not the case, follow the guide for installing Helm 2 on EKS: https://eksworkshop.com/beginner/060_helm/helm_intro/install. Note: this guide assumes you have root access. If you are not root, run this before following the guide in order to do a user-local install:
```
export USE_SUDO=false && export HELM_INSTALL_DIR=/home/$USER/bin
```

## 2. Create the ingress namespace and the Nexus namespace
You will need to create two namespaces: one for the ELB and ingress controller, and one for Nexus. The ingress namespace should follow the format `ingress-<environment>`, e.g. `ingress-sit` for the SIT environment. Similarly, the Nexus namespace should follow `nexus-<environment>`, e.g. `nexus-sit`. 
Run the following to create the two namespaces, substituting `<environment>` for the appropriate value:

```
export ENV=<environment>
kubectl create namespace ingress-$ENV
kubectl create namespace nexus-$ENV
```
## 3. Create the configuration file for the nginx-ingress Helm chart

Before installing the `nginx-ingress` Helm chart, you will need to create a yaml file with the desired configuration values for the ELB and the ingress controller. Find the ARN of the desired SSL certificate to use for the ELB, and the ID of the load balancer security group you want to use, and run the following: 
```
export ARN=<arn>
export SG=<security group ID
```
`<arn>` and `<security group ID>` should be replaced by the appropriate values, e.g. `arn:aws:acm:us-west-2:012345678912:certificate/2a67b6b9-eb8d-48e8-a88b-297b1a32f343` and `sg-037d227ba1e23eb43`, respectively.

Now, create the yaml config file by running:
```
cat <<EOF > ingress-$ENV.yaml
defaultBackend:
  enabled: false
controller:
  scope:
    enabled: true
    namespace: nexus-$ENV 
  kind: DaemonSet
  service:
    # Include this if you want to restrict access to the load balancer
    loadBalancerSourceRanges:
      - 137.78.0.0/16
      - 137.79.0.0/16
      - 128.149.0.0/16
    targetPorts:
      http: http
      https: http
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-ssl-cert: "$ARN"
      service.beta.kubernetes.io/aws-load-balancer-ssl-negotiation-policy: "ELBSecurityPolicy-TLS-1-2-2017-01"
      service.beta.kubernetes.io/aws-load-balancer-backend-protocol: "http"
      service.beta.kubernetes.io/aws-load-balancer-ssl-ports: "https"
      service.beta.kubernetes.io/aws-load-balancer-connection-idle-timeout: "60"
      service.beta.kubernetes.io/aws-load-balancer-extra-security-groups: "$SG"
  config:
    hsts: "true"
    ssl-redirect: "true"
    use-proxy-protocol: "false"
    use-forwarded-headers: "true"
    enable-access-log-for-default-backend: "true"
    enable-owasp-modsecurity-crs: "true"
    proxy-real-ip-cidr: "10.0.0.0/24,10.0.1.0/24" # restrict this to the IP addresses of ELB
    http-snippet: |
      server {
        server_name _ ;
        listen 8080 default_server reuseport backlog=511;

        set \$proxy_upstream_name "-";
        set \$pass_access_scheme \$scheme;
        set \$pass_server_port \$server_port;
        set \$best_http_host \$http_host;
        set \$pass_port \$pass_server_port;

        server_tokens off;
        location / {
          rewrite_by_lua_block {
              lua_ingress.rewrite({
                  force_ssl_redirect = true,
                  use_port_in_redirects = false,
              })
              balancer.rewrite()
              plugins.run()
          }
        }
        location /healthz {
          access_log off;
          return 200;
        }
      }
    server-snippet: |
      more_set_headers "Strict-Transport-Security: max-age=31536000; includeSubDomains; preload";
      add_header X-Frame-Options sameorigin always;
      add_header X-Content-Type-Options nosniff always;
      add_header X-XSS-Protection 1 always;
EOF
```

## 4. Install the nginx-ingress official Helm chart

Run the following to create the ELB and ingress controller by installing the nginx-ingress Helm chart, using the configuration file you just created:

```
helm repo update
helm install stable/nginx-ingress --namespace=ingress-$ENV -f ingress-$ENV.yaml
```

This will create a new ELB and ingress controller in the ingress namespace you created in Step 2.

## 5. Finish

You should save the `ingress-<environment>.yaml` file that was created, either locally on the box or elsewhere, so that it can be reused later if any configuration values need to be updated on the ELB or ingress controller.

Finally, inform the developer who will be installing Nexus what name you used to create the Nexus namespace. They will need to install Nexus into this namespace.