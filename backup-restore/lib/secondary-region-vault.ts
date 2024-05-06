import * as cdk from "aws-cdk-lib";
import { Construct } from "constructs";
import * as backup from "aws-cdk-lib/aws-backup";

export class SecondaryRegionVault extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // AWS Backup Vault
    const vault = new backup.BackupVault(this, "SecondaryRegionVault", {
      backupVaultName: "SecondaryRegionVault",
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });
  }
}
