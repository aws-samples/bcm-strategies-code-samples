import * as cdk from "aws-cdk-lib";
import { Construct, Dependable } from "constructs";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import * as efs from "aws-cdk-lib/aws-efs";
import * as datasync from "aws-cdk-lib/aws-datasync";
import * as rds from "aws-cdk-lib/aws-rds";
import * as iam from "aws-cdk-lib/aws-iam";
import * as fs from "fs";

export class SecondaryRegionStandby extends cdk.Stack {
  public fileSystem: efs.FileSystem;
  public database: rds.DatabaseInstance;
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);


  // Create a new VPC
  const vpc = new ec2.Vpc(this, "VPC");

  // Import managed policy to enable SSM on the EC2 Instances
  const ssmPolicy = iam.ManagedPolicy.fromManagedPolicyArn(
    this,
    "SSMPolicy",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  );

  // Target EFS FileSystem
  this.fileSystem = new efs.FileSystem(this, 'EfsFileSystem', {
    vpc,
    allowAnonymousAccess: true,
    removalPolicy: cdk.RemovalPolicy.DESTROY
  });

  // Security Group for DataSync
  const securityGroup = new ec2.SecurityGroup(this, 'DataSyncSecurityGroup', {
    vpc,
    description: 'Security Group for DataSync',
    allowAllOutbound: true,
  });
  this.fileSystem.connections.allowFrom(securityGroup, ec2.Port.tcp(2049), 'Allows tcp access to EFS from DataSync');
  this.fileSystem.connections.allowFrom(securityGroup, ec2.Port.udp(2049), 'Allows udp access to EFS from DataSync');

  // DataSync EFS Location
  const cfnLocationEFS = new datasync.CfnLocationEFS(this, 'CfnLocationEFS', {
    ec2Config: {
      securityGroupArns: [`arn:aws:ec2:${cdk.Stack.of(this).region}:${cdk.Stack.of(this).account}:security-group/${securityGroup.securityGroupId}`],
      subnetArn: `arn:aws:ec2:${cdk.Stack.of(this).region}:${cdk.Stack.of(this).account}:subnet/${vpc.privateSubnets[0].subnetId}`,
    },
    efsFilesystemArn: this.fileSystem.fileSystemArn,
  });
  cfnLocationEFS.node.addDependency(this.fileSystem.mountTargetsAvailable);

  // RDS Database MariaDB
  const databaseSecurityGroup = new ec2.SecurityGroup(this, 'DatabaseSecurityGroup', {vpc});
  cdk.Tags.of(databaseSecurityGroup).add('STANDBY_RDS_SECURITYGROUP', 'true');
  this.database = new rds.DatabaseInstance(this, 'Database', {
    vpc,
    engine: rds.DatabaseInstanceEngine.MARIADB,
    instanceType: ec2.InstanceType.of(ec2.InstanceClass.BURSTABLE3, ec2.InstanceSize.MEDIUM),
    publiclyAccessible: true,
    subnetGroup: new rds.SubnetGroup(this, 'DatabaseSubnetGroup', {
      vpc,
      description: 'Database Subnet Group',
      vpcSubnets: {
        subnetType: ec2.SubnetType.PUBLIC
      }
    }),
    securityGroups: [databaseSecurityGroup],
    removalPolicy: cdk.RemovalPolicy.DESTROY
  });

  // Stanbdy EC2 Instance
  const ec2Instance = new ec2.Instance(this, "EC2Instance", {
    instanceType: new ec2.InstanceType("m6g.xlarge"),
    machineImage: ec2.MachineImage.latestAmazonLinux2023({
      cpuType: ec2.AmazonLinuxCpuType.ARM_64,
    }),
    vpc,
    vpcSubnets: { subnetType: ec2.SubnetType.PUBLIC },
  });
  ec2Instance.node.addDependency(this.database); // wait for the database, because we read the secret in the userData script
  ec2Instance.role.addManagedPolicy(ssmPolicy);
  ec2Instance.connections.allowFromAnyIpv4(ec2.Port.tcp(22)); // allow SSH from any IP
  ec2Instance.connections.allowFromAnyIpv4(ec2.Port.tcp(80)); // allow HTTP from any IP
  this.fileSystem.connections.allowFrom(ec2Instance, ec2.Port.tcp(2049), 'Allows tcp access to EFS from Stanbdy Instance');
  this.fileSystem.connections.allowFrom(ec2Instance, ec2.Port.udp(2049), 'Allows udp access to EFS from Standby Instance');
  databaseSecurityGroup.connections.allowFrom(ec2Instance, ec2.Port.tcp(3306), 'Allows access to RDS from Standby Instance')
  this.database.secret?.grantRead(ec2Instance);
  ec2Instance.addToRolePolicy(
    new iam.PolicyStatement({
      actions: ["ec2:describe*"],
      resources: ["*"],
      effect: iam.Effect.ALLOW,
    })
  );


  // Set Tags that can be read from the UserData script
  cdk.Tags.of(ec2Instance).add("STANDBY_DATABASE_SECRET", this.database.secret?.secretName!);
  cdk.Tags.of(ec2Instance).add("STANDBY_EFS_ID", this.fileSystem.fileSystemId);

  // Add UserData to configure standby wordpress
  const userDataScript = fs.readFileSync("./resources/init_secondary.sh", "utf8");
  ec2Instance.addUserData(userDataScript);

  }
}
