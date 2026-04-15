apiVersion: v1
kind: ServiceAccount
metadata:
  name: titan-aws-sa
  namespace: titan
  annotations:
    eks.amazonaws.com/role-arn: 
