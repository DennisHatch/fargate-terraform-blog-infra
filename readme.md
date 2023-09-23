# Terraform project used for the Fargate Terraform blog

In this project you will see the prefix 'ftb' which is Fargate Terraform Blog.
## Prerequisits
This project assumes you have valid AWS credentials in your environment variabels or /.aws/credentials file.
## Config
The project relies on a few external parameters such as an AWS VPC ID.\
This project contains a .sh file to quickle set there parameters in your environment. Simple complete the file with the correct parameters and run
```source ./export-tf-vars.ts```
## Running terraform
You can run the current terraform config with 
```terraform apply```

## Destroying terraform
You can undo the terraform apply with
```terraform destroy```
