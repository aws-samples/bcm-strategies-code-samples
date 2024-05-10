# Pilot Light Reference Architecture

This project provides a practical implementation of the disaster recovery (DR) strategy "Pilot Light" outlined in the [AWS Disaster Recovery Whitepaper](https://aws.amazon.com/whitepapers/aws-disaster-recovery/). It demonstrates this using an installation of the open-source web content management system "WordPress" on an Amazon EC2 instance, and by using the AWS Elastic Disaster Recovery service.

![Architecture Diagram](./images/diagram.svg)

## Overview

This repository contains a CDK project designed to help you set up a single EC2 instance running WordPress and configure AWS Elastic Disaster Recovery for a cotinuos block level repilication.

## Prerequisites

Before deploying this solution, ensure you have the following prerequisites:

- AWS CLI installed and configured with necessary IAM permissions.
- AWS CDK installed.
- An AWS account and AWS CLI configured with your access and secret keys.

## Deployment

To deploy this project, make sure all dependencies are installed by running `npm install` and then run `cdk deploy --all`
After deploying the CDK stack, you can access your WordPress site and ensure that AWS Elastic Didaster Recovery starts replicating your instance to a secondary region. 

The restore process can be iniated using AWS Backup in the AWS Console as explained in the [AWS Elastic Disaster Recovery documentation](https://docs.aws.amazon.com/drs/). 

In the `examples` folder you can find a script that automates the restore process and measures the RTA.

## Cleanup

To avoid incurring additional charges, you can remove the resources created by this CDK stack by running `cdk destroy --all`. Make sure you have stopped the replication manually before the deleting the stackt, und removed all recovery instances and configurations referencing the stacks security groups.

## Additional Information

For a deeper understanding of disaster recovery best practices, refer to the [AWS Disaster Recovery Whitepaper](https://docs.aws.amazon.com/whitepapers/latest/disaster-recovery-workloads-on-aws/disaster-recovery-workloads-on-aws.html). Specifically, focus on the "Backup and Restore" section of the whitepaper for comprehensive guidance on creating a robust backup and recovery strategy.

For more information on AWS CDK and AWS Backup, consult the following resources:

- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/latest/guide/home.html)
- [AWS Elastic Disaster Recovery documentation](https://docs.aws.amazon.com/drs/)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
