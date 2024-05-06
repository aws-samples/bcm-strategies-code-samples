#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { PrimaryRegionWorkload } from '../lib/primary-region-workload';
import { SecondaryRegionVault } from '../lib/secondary-region-vault';

const app = new cdk.App();
new SecondaryRegionVault(app, 'SecondaryRegionVaultStack', {
  env: { account: process.env.CDK_DEFAULT_ACCOUNT, region: process.env.SECONDARY_REGION || "eu-west-1" },
});
new PrimaryRegionWorkload(app, 'PrimaryRegionWorkloadStack', {
  env: { account: process.env.CDK_DEFAULT_ACCOUNT, region: process.env.PRIMARY_REGION || "eu-central-1" },
});