# BCM Strategies in Public Cloud

This repository contains sample implementations of the following Business Continuity Management (BCM) strategies for IT service continuity in the public cloud:

1. **Backup and Restore**
2. **Pilot Light**
3. **Warm Standby**

These strategies are described and discussed in the paper "Implementing IT Disaster Recovery Strategies in the Public Cloud" by Michael Wahlers and Christian Schäfer. The repository aims to provide practical examples and code samples to help the BCM community understand, validate, and implement these strategies.

## Overview

- [**Backup and Restore**](./backup-restore/README.md): This strategy involves creating backups of data and applications, which can be restored in the event of a disaster. The sample implementation demonstrates how to set up backup and restore processes in the cloud.

- [**Pilot Light**](./pilot-light/README.md): In this approach, a minimal version of the application environment is maintained in the cloud, ready to be scaled up when needed. The sample shows how to set up and manage a pilot light environment.

- [**Warm Standby**](./pilot-light/README.md): This strategy keeps a scaled-down but functional version of the application environment running in the cloud, allowing for faster recovery. The sample illustrates the implementation of a warm standby environment.

Each strategy's folder contains Infrastructure as Code (IaC) definitions, failover scripts, and demonstration videos to help you understand and reproduce the implementations.

## Walktrough Videos

We have recorded videos that walk you trough the deployment and restore process for the three strategies:

* [Backup and Restore (34MB, mp4 h.264)](https://d2lfgz1268un9v.cloudfront.net/20240307_AWS_BCM_Backup_Restore_2000kbits_h264.mp4)
* [Pilot Light (23MB, mp4 h.264)](https://d2lfgz1268un9v.cloudfront.net/20240314_AWS_BCM_PilotLight_2000kbits_h264.mp4)
* [Warm Standy (20MB, mp4 h.264)](https://d2lfgz1268un9v.cloudfront.net/20240314_AWS_BCM_Warm_Standby_2000kbits_h264.mp4)

## Getting Started

To get started with the samples, follow the instructions in the respective strategy folders. You'll need an AWS account to run the samples.

## Contributing

Contributions to this repository are welcome! If you have improvements, bug fixes, or additional examples, please submit a pull request. For major changes, it's recommended to open an issue first to discuss the proposed modifications. See [CONTRIBUTING](CONTRIBUTING.md) for more information.

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the [LICENSE](LICENSE) file.