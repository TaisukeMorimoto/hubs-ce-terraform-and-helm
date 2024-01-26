# Build hubs community edition on AWS using helm and terraform

This repository manages the AWS resources needed to build the community version as code in terraform and deploys them using helm.

This repository depends on [mozilla-hubs-ce-chart](https://github.com/hubs-community/mozilla-hubs-ce-chart).

# My Local Environment

- MacBook Pro
- CPU: Apple M3 Pro
- macOS: Sonoma 14.2.1

This is only my confirmed environment, so other environments can be deployed.

# Prerequirements

- [Kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Awscli](https://aws.amazon.com/cli/)
- [Helm](https://helm.sh/docs/intro/install/)
- [Terraform](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)

# **Getting Started**

## 1. Configure DNS on Route53

Configure your DNS according to **[Step 1: Configuring your DNS on AWS's Route53](https://hubs.mozilla.com/labs/community-edition-case-study-quick-start-on-gcp-w-aws-services/#:~:text=Step%201%3A%20Configuring%20your%20DNS%20on%20AWS%27s%20Route53)**

## 2. Setup AWS Infrastructure

1. Create S3 bucket for infrastructure state management files (tfstate)
    1. Execute the following commands in a terminal
    {environment}: AWS Environment Name （ex. develop）
        
        ```bash
        aws s3api create-bucket --bucket ov-hubs-ce-tfstate-{environment} --region ap-northeast-1 --create-bucket-configuration LocationConstraint=ap-northeast-1
        ```
        
        <aside>
        💡 Only when region is us-east-1, LocationConstraint is not specified because it is unnecessary.
        
        </aside>
        
2. Create tfbackend file
    1. Create `{env_name}.tfbackend`
        
        ```bash
        touch {env_name}.tfbackend
        ```
        
    2. Enter and update values in the `{env_name}.tfbackend` file, referring to the sample configuration file
    3. Create`{env_name}.tfvars`
        
        ```bash
        touch {env_name}.tfvars
        ```
        
    4. Enter and update values in the `{env_name}.tfvars` file, referring to the sample configuration file.
    The `ENV_NAME_TAG` should match the `{env_name}`.
        
        <aside>
        💡 When adding environment variables, in addition to editing the `{env_name}.tfvars` file, it is necessary to define the variables in `variables.tf`
        
        </aside>
        

## 3. Build environment on AWS

1. Terraform Initialize
    
    ```bash
    sh terraform.sh {env_name} init
    ```
    
2. Format
    
    ```bash
    sh terraform.sh {env_name} fmt
    ```
    
3. Validation
    
    ```bash
    sh terraform.sh {env_name} validate
    ```
    
4. Build Environment
    
    ```bash
    sh terraform.sh {env_name} apply
    ```
    
    A list of resources to be created will be output. If there are no problems, enter "yes".
    
    When the process is completed, resources such as VPCs and EKSs whose definitions are created in the AWS environment.
    

## 4. Configure SMTP on SES

Configure your SMTP according to **[Step 2: Configuring your SMTP on AWS's Simple Email Service (SES)](https://hubs.mozilla.com/labs/community-edition-case-study-quick-start-on-gcp-w-aws-services/#:~:text=Step%202%3A%20Configuring%20your%20SMTP%20on%20AWS%27s%20Simple%20Email%20Service%20(SES))**

## 5. Setup Helm Chart

<aside>
💡 The helm chart configuration basically follows the document below.
**[Deploying Mozilla Hubs CE on AWS with Ease: A Guide to the Scale Edition Helm Chart](https://hubs.mozilla.com/labs/deploying-mozilla-hubs-ce-on-aws-with-ease-a-guide-to-the-scale-edition-helm-chart/)**

</aside>

- Setup Helm
    1. Create a namespace named hcce in the EKS cluster
        
        ```bash
        kubectl create ns hcce
        ```
        
    2. Create a namespace named security in the EKS cluster
        
        ```json
        kubectl create ns security
        ```
        
    3. Add the jetstack repository to helm and install cert-manager in the namespace security.
        
        ```json
        helm repo add jetstack https://charts.jetstack.io
        helm repo update
        helm install cert-manager jetstack/cert-manager \
        --namespace security \
        --set ingressShim.defaultIssuerName=letsencrypt-issuer \
        --set ingressShim.defaultIssuerKind=ClusterIssuer \
        --set installCRDs=true
        ```
        
    4. Create `{env_name}-cluster-issuer.yaml`
        
        ```bash
        touch {env_name}-cluster-issuer.yaml
        ```
        
    5. Update the email to the administrator's email address in  `{env_name}-cluster-issuer.yaml`
        - 入力例
            
            ```bash
            apiVersion: cert-manager.io/v1
            kind: ClusterIssuer
            metadata:
              name: letsencrypt-issuer
            spec:
              acme:
                # You must replace this email address with your own.
                # Let's Encrypt will use this to contact you about expiring
                # certificates, and issues related to your account.
                email: **'xxxxxxxxx@gmail.com'**
                server: https://acme-v02.api.letsencrypt.org/directory
                privateKeySecretRef:
                  # Secret resource that will be used to store the account's private key.
                  name: letsencrypt-issuer
                # Add a single challenge solver, HTTP01 using nginx
                solvers:
                  - http01:
                      ingress:
                        class: haproxy
            ```
            
    6. Apply Issuer to EKS
        
        ```json
        kubectl apply -f '{env_name}-cluster-issuer.yaml'
        ```
        
    7. Get the helm chart resources for hubs ce by git clone from the repository for Mozilla Hubs CE Chart
        
        ```json
        git clone https://github.com/hubs-community/mozilla-hubs-ce-chart.git
        ```
        
    8. Copy the event file with the following command
        
        ```json
        cp mozilla-hubs-ce-chart/values.scale.yaml {env_name}-values-event.yaml
        ```
        
    9. update `render_helm.sh` in `mozilla-hubs-ce-chart` folder
        1. put random strings in the following three variables in the `render_helm.sh` file.
            
            ```json
            NODE_COOKIE="node-{YOUR_NODE_COOKIE_ID}"
            GUARDIAN_KEY="{YOUR_GUARDIAN_KEY}"
            PHX_KEY="{YOUR_PHX_KEY}"
            ```
            
        2. Update DB authentication information in `render_helm.sh` file
            
            ```json
            DB_USER="postgres"
            DB_PASS="123456"
            EXT_DB_HOST="pgsql"
            ```
            
            - `DB_USER`: Identical to `DB_MASTER_USERNAME` specified in the `{env_name}.tfvars` file
            - `DB_PASS`: Identical to `DB_MASTER_PASSWORD` specified in the `{env_name}.tfvars` `{env_name}.tfvars`
            - `EXT_DB_HOST`: Value output when the following command is executed
                
                ```
                sh terraform.sh {env_name} output -raw rds_writer_endpoint
                ```
                
                <aside>
                💡 The value of EXT_DB_HOST can also be checked from the RDS console.
                
                > Endpoint name of the created database endpoint whose type is Writer
                > 
                </aside>
                
        3. Update SMTP information in `render_helm.sh` file
        Update the settings based on the information configured in "4. Configure SMTP on SES”
            
            ```
            SMTP_SERVER="{YOUR_SMTP_SERVER}"
            SMTP_PORT="587"
            SMTP_USER="{YOUR_SMTP_USER}"
            SMTP_PASS="{YOUR_SMTP_PASS}"
            ```
            
            `SMTP_SERVER`: SMTP endpoint
            
            `SMTP_USER`: SMTP username as listed in the csv you downloaded your credentials (note that this is not an IAM user)
            
            `SMTP_PASS`: SMTP password from the csv downloaded with the SMTP credentials
            
    10. Run the edited `render_helm.sh`
        
        ```json
        ./mozilla-hubs-ce-chart/render_helm.sh {domain} {mail_address}
        ```
        
    11. Check the contents of the generated . Check the contents of the `/config.yaml` file.
    12. `{env_name}-values-event.yaml`ファイル内の`configs > data`を更新する
        1. Update `configs > data` in the `{env_name}-values-event.yaml` file
        2. In the `{env_name}-values-event.yaml` file, near line 118# Replace the part below where it says `# Get the following from render_helm.sh`
            
            <aside>
            💡 If you have difficulty understanding the changes, check out the hands on Youtube video below published by the hubs community.
            17 minutes:around 35 seconds
            
            [https://www.youtube.com/watch?v=0VtKQYXTrn4&t=107s](https://www.youtube.com/watch?v=0VtKQYXTrn4&t=107s)
            
            </aside>
            
    13.  Update `defaultCert > data` in the `{env_name}-values-event.yaml` file
        1. . Copy `tls.crt`, `tls.key` in the `/config.yaml` file.
        2. Replace `tls.crt`, `tls.key` in `defaultCert > data` near line 165 in file `{env_name}-values-event.yaml`
        3. Also, change enabled under defaultCert from `false` to `true`
        
        <aside>
        💡 If you have difficulty understanding the changes, check out the hands on Youtube video below published by the hubs community.
        17 minutes:around 35 seconds
        
        [https://www.youtube.com/watch?v=0VtKQYXTrn4&t=107s](https://www.youtube.com/watch?v=0VtKQYXTrn4&t=107s)
        
        </aside>
        
    14. In the file `{env_name}-values-event.yaml`, replace the following value near line 6
        1. `{YOUR_HUBS_DOMAIN}`: domai
        2. `{ADMIN_EMAIL_ADDRESS}`: administrator's email address
        
        ```
        global:
          domain: &HUBS_DOMAIN "{YOUR_HUBS_DOMAIN}"
          adminEmail: &ADMINEMAIL "{ADMIN_EMAIL_ADDRESS}"
        ```
        
    15. Change certificate settings
        1. `mozilla-hubs-ce-chart/charts/haproxy/templates/deployment.yaml`を開く。
        2. Change line 39.
            1. before
                
                ```json
                - --default-ssl-certificate={{ .Release.Namespace }}/cert-**hcce**
                ```
                
            2. after
                
                ```json
                - --default-ssl-certificate={{ .Release.Namespace }}/cert-**{{ .Values.global.domain }}**
                ```
                
            
            <aside>
            💡 Failure to follow this procedure will result in a warning to the user that the communication is not protected.
            
            </aside>
            
- EFS mount settings
    
    <aside>
    💡 If you do not use efs, you can run the application without following the steps below, leaving enabled: false. However, in that case, assets such as scenes and logos will be deleted when the node (EC2 instance) of the EKS cluster is deleted.
    
    </aside>
    
    1. Update the efs setting near line 17 in the file `{env_name}-values-event.yaml`
        
        enabled: `true`
        
        fileSystemId: Value output when executing `sh ./terraform.sh {env_name} output -raw efs_id`
        
        ```yaml
        aws:
            efs:
              enabled: false
              isDynamicProvisioning: false
              fileSystemId: fs-000000000000
        ```
        
    2. Changed to not use pgsql
        1. Add the following to the last line in the file `{env_name}-values-event.yaml`
            
            ```yaml
            # Add
            **pgsql:
              enabled: false**
            ```
            

## 6. Deploy Hubs CE

1. helm install
    
    ```yaml
    helm install moz -f {env_name}-values-event.yaml ./mozilla-hubs-ce-chart --namespace=hcce
    ```
    
2. Check the external IP of the resource to be created in EKS
    
    ```bash
    kubectl get --namespace hcce svc -w haproxy-lb
    ```
    
3. Update A record for the Hubs application in Route53
    1. open the Route53 console
    2. select "Host Zone" on the left side and select the domain you specified when deploying
    3. update the values of the 4 A records created in "1. Configure DNS on Route53" as follows:
        1. select the target A record and click "Edit Record" displayed in the upper right corner
        2. update as follows and save
            1. record type: A
            2. alias: on
            3. traffic routing destination: alias to Application Load Balancer and Classic Load Balancer
            4. region: us-east-1
            5. load balancer: dualstack.{external IP of EKS}
        
        Perform the above steps for all four A records ({domain}, assets.{domain}, cors.{domain}, stream.{domain})
        

## 7. Check Hubs Application

- Check the status of EKS Pod
    
    ```bash
    kubectl get pods -n hcce
    ```
    
    <aside>
    💡 If some pods do not become Running after 10 minutes or more, there may be a problem. Please check the information of each pod and debug it by referring to the following.
    
    </aside>
    
    - Check logs for each pod
        
        <aside>
        💡 `{pod_name}` can be found in the output of `kubectl get pods -n hcce`
        
        </aside>
        
        ```bash
        kubectl logs pod {pod_name} -n hcce
        ```
        
    - Check the information for each pod (e.g., if the pod is Pending, check this)
        
        ```bash
        kubectl describe pod {pod_name} -n hcce
        ```
        

## 10. Confirmation of operation

Confirm the following operations

- Access to the domain
    
    After accessing the domain, the sign-in screen appears. Can sign in by entering the administrator's e-mail address
    
- Can create a room
- Can listen to other users' voices in the room

# Troubleshooting

- Certificate verification does not complete successfully and domain cannot be accessed
    - → Temporarily turn off http → https redirects
        
        `/mozilla-hubs-ce-chart/charts/haproxy/values.yaml`ファイル内
        
        204行目のssl-redirectをtrueからfalseに変更する
        
        ```yaml
        ssl-redirect: "false"  # true -> false
        ```