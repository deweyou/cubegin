import {defineConfig} from '@playwright/test';
export default defineConfig({
 testDir:'tests/e2e',fullyParallel:true,
 reporter:process.env.CI ? [['list'],['html',{open:'never'}]] : 'list',
 use:{baseURL:'http://127.0.0.1:4488',viewport:{width:960,height:760},deviceScaleFactor:1,trace:'retain-on-failure',screenshot:'only-on-failure'},
 projects:[{name:'chromium',use:{browserName:'chromium'}}],
 webServer:{command:'pnpm dev',url:'http://127.0.0.1:4488',reuseExistingServer:!process.env.CI},
 expect:{toHaveScreenshot:{maxDiffPixelRatio:0.001}},
});
