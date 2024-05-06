import * as cdk from "aws-cdk-lib";
import { Construct } from "constructs";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import * as s3 from "aws-cdk-lib/aws-s3";
import * as fs from "fs";
import * as iam from "aws-cdk-lib/aws-iam";
import * as efs from "aws-cdk-lib/aws-efs";
import * as rds from "aws-cdk-lib/aws-rds";

interface PrimaryRegionWorkloadProps extends cdk.StackProps {
  secondaryRegion: string;
  fileSystem: efs.FileSystem;
  standbyDatabase: rds.DatabaseInstance;
}

export class PrimaryRegionWorkload extends cdk.Stack {
  constructor(scope: Construct, id: string, props: PrimaryRegionWorkloadProps) {
    super(scope, id, props);

    // Create a new VPC
    const vpc = new ec2.Vpc(this, "VPC", {ipAddresses: ec2.IpAddresses.cidr("10.10.0.0/16")});

    // Import managed policy to enable SSM on the EC2 Instances
    const ssmPolicy = iam.ManagedPolicy.fromManagedPolicyArn(
      this,
      "SSMPolicy",
      "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    );

    // Create EC2 Instance with DataSync AMI
    const dataSyncInstance = new ec2.Instance(this, "DataSyncInstance", {
      instanceType: new ec2.InstanceType("t3.large"),
      machineImage: ec2.MachineImage.fromSsmParameter(
        "/aws/service/datasync/ami"
      ),
      vpc,
      vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
    });
    dataSyncInstance.role.addManagedPolicy(ssmPolicy);

    // Create EC2 Instance with latest Amazon Linux 2023 running WordPress
    const ec2Instance = new ec2.Instance(this, "EC2Instance", {
      instanceType: new ec2.InstanceType("m6g.xlarge"),
      machineImage: ec2.MachineImage.latestAmazonLinux2023({
        cpuType: ec2.AmazonLinuxCpuType.ARM_64,
      }),
      vpc,
      vpcSubnets: { subnetType: ec2.SubnetType.PUBLIC },
      blockDevices: [
        {
          deviceName: "/dev/xvda",
          volume: ec2.BlockDeviceVolume.ebs(120),
        },
      ],
    });
    ec2Instance.role.addManagedPolicy(ssmPolicy);
    ec2Instance.connections.allowFromAnyIpv4(ec2.Port.tcp(22)); // allow SSH from any IP
    ec2Instance.connections.allowFromAnyIpv4(ec2.Port.tcp(80)); // allow HTTP from any IP
    ec2Instance.connections.allowFrom(dataSyncInstance, ec2.Port.tcp(2049)); // allow NFS TCP from DataSync Instance
    ec2Instance.connections.allowFrom(dataSyncInstance, ec2.Port.udp(2049)); // allow NFS UDP from DataSync Instance

    // Set Tags that can be read from the UserData script
    cdk.Tags.of(ec2Instance).add("STANDBY_REGION", props.secondaryRegion);
    cdk.Tags.of(ec2Instance).add("STANDBY_FILESYSTEM", props.fileSystem.fileSystemId);
    cdk.Tags.of(ec2Instance).add("STANDBY_DATABASE", props.standbyDatabase.instanceEndpoint.hostname);
    cdk.Tags.of(ec2Instance).add("STANDBY_DATABASE_SECRET", props.standbyDatabase.secret?.secretName!);

    // Add UserData to install Wordpress
    const userDataScript = fs.readFileSync("./resources/init.sh", "utf8");
    ec2Instance.addUserData(userDataScript);

    // Allow connection from the WordPress Instance to the DataSync Instance to retrieve the activation key
    dataSyncInstance.connections.allowFrom(ec2Instance, ec2.Port.tcp(80));

    // Add permissions to WordPres instance
    ec2Instance.addToRolePolicy(
      new iam.PolicyStatement({
        actions: ["ec2:describe*", "datasync:Create*", "datasync:List*", "ec2:CreateNetworkInterface",
        "ec2:CreateNetworkInterfacePermission","ec2:AuthorizeSecurityGroupIngress"],
        resources: ["*"],
        effect: iam.Effect.ALLOW,
      })
    );
    props.standbyDatabase.secret?.grantRead(ec2Instance);

  }
}
