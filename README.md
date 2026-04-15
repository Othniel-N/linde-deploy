apiVersion: v1
kind: ServiceAccount
metadata:
  name: titan-aws-sa
  namespace: titan
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::3942401:role/n-rds-eks-s-role
