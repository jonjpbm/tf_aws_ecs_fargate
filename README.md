# tf_aws_ecs_fargate
An example of creating the AWS infrastructure for a container app using AWS ECS on Fargate

# Credit
This showed me that I needed a security group for the ALB **AND** a seperate security group for the container task ifself. Otherwise, the health checks kept failing.

https://engineering.finleap.com/posts/2020-02-20-ecs-fargate-terraform/

This was the bones of the over code. This uses EC2s as the underlying infrastructure but I changed it to use Fargate

https://aws.amazon.com/blogs/opensource/deploying-python-flask-microservices-to-aws-using-open-source-tools/

This code showed me how to authenticate to a private Docker Hub repository

https://aws.amazon.com/blogs/containers/authenticating-with-docker-hub-for-aws-container-services/
