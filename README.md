# Terraform template for AWS EKS with Fargate template

This terraform setup can be used to setup the AWS infrastructure
for a dockerized application running on EKS with  a Fargate template.

## Prerequisites
This template requires `aws-iam-authenticator` to be installed

## Known limitations
Although the namespace `default` is set in the fargate template (meaning
pods will be executed on managed nodes), CoreDNS can currently only run
on a fargate profile if the CoreDNS deployment is patched after the
cluster is created (see https://github.com/terraform-providers/terraform-provider-aws/issues/11327).

By default the `config` file for `kubectl` is created in `~/.kube` directory. If any
configuration already exists there, it will be overwritten! To preserve any pre-existing
configuration, change the `kubeconfig_path` variable.