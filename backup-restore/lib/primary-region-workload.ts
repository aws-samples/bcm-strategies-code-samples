import * as cdk from "aws-cdk-lib";
import { Construct } from "constructs";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import * as iam from "aws-cdk-lib/aws-iam";
import * as fs from "fs";
import * as backup from "aws-cdk-lib/aws-backup";
import * as events from "aws-cdk-lib/aws-events";

export class PrimaryRegionWorkload extends cdk.Stack {
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
      instanceType: new ec2.InstanceType("m6g.xlarge"),
      machineImage: ec2.MachineImage.latestAmazonLinux2023({
        cpuType: ec2.AmazonLinuxCpuType.ARM_64,
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

    // Import backup vault from secondary region
    const secondaryRegionVault = backup.BackupVault.fromBackupVaultArn(
      this,
      "SecondaryRegionVault",
      `arn:aws:backup:${process.env.SECONDARY_REGION || "eu-west-1"}:${
        this.account
      }:backup-vault:SecondaryRegionVault`
    );

    // Create a backup plan
    // Daily with 35 Day retention. Adjust if needed.
    const vault = new backup.BackupVault(this, "PrimaryRegionVault", {
      backupVaultName: "PrimaryRegionVault",
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });
    const plan = new backup.BackupPlan(this, "BackupPlan", {
      backupVault: vault,
    });
    plan.addRule(
      new backup.BackupPlanRule({
        ruleName: "default",
        deleteAfter: cdk.Duration.days(35),
        scheduleExpression: events.Schedule.cron({ hour: "0", minute: "0" }),
        copyActions: [
          {
            destinationBackupVault: secondaryRegionVault,
            deleteAfter: cdk.Duration.days(1),
          },
        ],
      })
    );
    plan.addSelection("Selection", {
      resources: [backup.BackupResource.fromEc2Instance(ec2Instance)],
    });
  }
}
