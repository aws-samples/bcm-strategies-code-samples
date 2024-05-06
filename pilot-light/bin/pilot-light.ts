#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { PilotLightStack } from '../lib/pilot-light-stack';

const app = new cdk.App();
new PilotLightStack(app, 'PilotLightStack', {
  env: { account: process.env.CDK_DEFAULT_ACCOUNT, region: process.env.PRIMARY_REGION || "eu-central-1" },
});