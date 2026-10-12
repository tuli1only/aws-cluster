# EKS reference cluster - Unit A / Black and Unit B / Red

This project builds the same EKS cluster in two separate AWS accounts using Terraform.
No Terraform knowledge needed to follow it. Just do the steps in order.

**What Terraform is:** you describe the cluster in a text file (`main.tf`), and
Terraform creates it in AWS for you. `plan` shows what it WOULD do. `apply` actually does it.

## What's in this folder

| File | What it is |
|---|---|
| `main.tf` | The whole cluster definition (the only file with real logic) |
| `lbc_iam_policy.json` | Permissions for the Load Balancer Controller (must stay next to main.tf) |
| `environments/unit-a-black.tfvars` | Settings for Unit A (account, region, network IDs) |
| `environments/unit-b-red.tfvars` | Settings for Unit B |
| `scripts/tf.sh` | Helper that runs Terraform safely for one unit |
| `docs/` | Your two diagrams and the scope text |
| `state/` | Created on first run. Terraform's memory of what it built. **Back it up, never delete it.** |

## What gets built (per unit)

- EKS cluster with a private API endpoint, encrypted secrets, control plane logs in CloudWatch
- General / Platform node group: 3 x m7i.2xlarge
- Add-ons: VPC CNI, CoreDNS, kube-proxy, EBS CSI driver, Pod Identity Agent, AWS Load Balancer Controller
- Governance: namespaces (starting with `ex-platform-ci`), Pod Security labels, ResourceQuotas,
  default-deny NetworkPolicy (DNS allowed), RBAC for teams

## Step 1 - Install the tools (once, on the machine that will run this)

- Terraform (version 1.5 or newer): https://developer.hashicorp.com/terraform/install
- AWS CLI v2: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
- kubectl: https://kubernetes.io/docs/tasks/tools/

Then check:

    ./scripts/tf.sh a check

## Step 2 - Log in to the right AWS account

Unit A and Unit B are different AWS accounts. You must be logged in to the matching one.
The script shows which account you are in and asks you to confirm before it plans or applies.

    aws configure --profile unit-a       # or use your SSO login
    export AWS_PROFILE=unit-a            # use unit-b when working on Unit B

The identity needs permission to create EKS, IAM, KMS, EC2 and CloudWatch resources.
An administrator-level role in a fresh account is simplest.

## Step 3 - Fill in the settings

Open `environments/unit-a-black.tfvars` and replace every `CHANGE-ME`:
region, VPC ID, at least two private subnet IDs in different Availability Zones,
and (optionally) admin role ARNs. Do the same for Unit B when you get to it.

Subnets need plenty of free IPs because every pod gets a VPC address (your T09 note).

## Step 4 - Where to run this (important)

The cluster's API is **private** by default. Terraform creates the cluster from anywhere,
but the parts that configure inside it (storage class, load balancer controller, namespaces,
quotas, network policies) need to reach that private API. So run Terraform from a machine
**inside the VPC or connected to it** (your jump host, a VM, or a CI runner).

If you run it from a laptop outside the VPC, the apply will fail at the Kubernetes/Helm
resources. Either move to an in-VPC machine, or as a temporary workaround set in the tfvars:

    endpoint_public_access = true
    public_access_cidrs    = ["YOUR.PUBLIC.IP/32"]

and set it back to `false` afterwards. Your security team should approve that.

## Step 5 - Pick a Kubernetes version

    aws eks describe-cluster-versions --region <your-region> \
      --query 'clusterVersions[].[clusterVersion,status,endOfStandardSupportDate]' --output table

Choose a version in standard support and put it in `kubernetes_version`.
The default is 1.35, which I could not confirm for your region. 1.34 leaves EKS
standard support on 2 December 2026, so do not start on it.

## Step 6 - Build it

    ./scripts/tf.sh a init        # downloads providers, first time only
    ./scripts/tf.sh a validate    # checks the file for mistakes
    ./scripts/tf.sh a plan        # shows what will be created. Read it, change nothing yet
    ./scripts/tf.sh a apply       # creates it. Type 'yes' when asked. Takes about 15-25 minutes

Replace `a` with `b` for Unit B. Always run `plan` first and look for anything unexpected.

## Step 7 - Check that it works

    aws eks update-kubeconfig --name ex-a-eks --region <your-region> --profile unit-a
    kubectl get nodes                        # expect 3 nodes, all Ready
    kubectl get pods -n kube-system          # aws-node, coredns, kube-proxy, ebs-csi, pod-identity, LBC all Running
    kubectl get ns                           # includes ex-platform-ci
    kubectl describe quota -n ex-platform-ci # shows the ResourceQuota
    kubectl get networkpolicy -n ex-platform-ci
    kubectl get storageclass                 # ebs-gp3 (default)

Quick NetworkPolicy test (T06 "verify enforcement"): start a pod in `ex-platform-ci`
and try to reach another service. It should be blocked until you add an allow rule.

## Changing things later

Edit `main.tf` or the tfvars, then run `plan` and `apply` again. Terraform only changes the difference.

## Tearing it down

    ./scripts/tf.sh a destroy

This deletes the cluster and everything in it. The EBS StorageClass uses `Retain`,
so volumes created by pods survive a destroy and keep costing money until you delete them by hand.

## Cost warning

3 x m7i.2xlarge nodes plus the EKS control plane run 24/7 and cost real money, in each account.
Check current prices at https://aws.amazon.com/eks/pricing/ and https://aws.amazon.com/ec2/pricing/on-demand/
and destroy test clusters you don't need.

## Safety rules

- Never delete the `state/` folder. Back it up, or later move it to an S3 bucket (`backend "s3"` in main.tf).
- Never commit `state/` to Git (the `.gitignore` already blocks it, because it can contain secrets).
- Always `plan` before `apply`, and always check the account the script prints.
- Unit A and Unit B stay separate: different account, different tfvars, different state file.

## Not included yet

- Data / AI node group (0-4 nodes, label + taint)
- GitLab Runner install (only the `ex-platform-ci` namespace, quota and network rules exist)
- Pod Identity for the runners, ex-app-<team> namespaces, EFS
- Splunk / SIEM log forwarding

## Open questions

See `docs/SCOPE-T06.md`. The main one: the second diagram says "OpenShift A" while everything else says EKS.
