import * as cdk from "aws-cdk-lib";
import { Construct } from "constructs";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import * as fs from "fs";
import * as iam from "aws-cdk-lib/aws-iam";

export class PilotLightStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Get default VPC
    const vpc = ec2.Vpc.fromLookup(this, "VPC", { isDefault: true });

    // Import managed policy to enable SSM on the EC2 Instances
    const ssmPolicy = iam.ManagedPolicy.fromManagedPolicyArn(
      this,
      "SSMPolicy",
      "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    );

    // Create EC2 Instance with latest Amazon Linux 2023
    const ec2Instance = new ec2.Instance(this, "EC2Instance", {
      instanceType: new ec2.InstanceType("m6i.xlarge"),
      machineImage: ec2.MachineImage.latestAmazonLinux2023({
        cpuType: ec2.AmazonLinuxCpuType.X86_64,
      }),
      vpc,
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

    // Add UserData to install Wordpress
    const userDataScript = fs.readFileSync("./resources/init.sh", "utf8");
    ec2Instance.addUserData(userDataScript);

    // Add Policy for AWS Elastic Disaster Recovery
    ec2Instance.role.addManagedPolicy(
      iam.ManagedPolicy.fromManagedPolicyArn(
        this,
        "ElasticDRPolicy",
        "arn:aws:iam::aws:policy/service-role/AWSElasticDisasterRecoveryEc2InstancePolicy"
      )
    );
  }
}
