#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { PrimaryRegionWorkload } from '../lib/primary-region-workload';
import { SecondaryRegionStandby } from '../lib/secondary-region-standby';
const app = new cdk.App();

const primaryRegion = process.env.PRIMARY_REGION || "eu-central-1"; // AWS Region Frankfurt
const secondaryRegion = process.env.SECONDARY_REGION || "eu-west-1"; // AWS Region Dublin


const secondaryRegionStack = new SecondaryRegionStandby(app, 'WSSecondaryRegionStack', {
  env: { account: process.env.CDK_DEFAULT_ACCOUNT, region: secondaryRegion },
  crossRegionReferences: true
});

new PrimaryRegionWorkload(app, 'WSPrimaryRegionStack', {
  env: { account: process.env.CDK_DEFAULT_ACCOUNT, region: primaryRegion  },
  secondaryRegion,
  fileSystem: secondaryRegionStack.fileSystem,
  standbyDatabase: secondaryRegionStack.database,
  crossRegionReferences: true
});
