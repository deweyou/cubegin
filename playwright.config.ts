import {defineConfig} from '@playwright/test';
const staticPreview=Boolean(process.env.CUBEGIN_TEST_STATIC);
const baseURL=staticPreview?'http://127.0.0.1:4492':'http://127.0.0.1:4489';
export default defineConfig({
 testDir:'tests/e2e',fullyParallel:true,
 reporter:process.env.CI ? [['list'],['html',{open:'never'}]] : 'list',
 use:{baseURL,viewport:{width:960,height:760},deviceScaleFactor:1,trace:'retain-on-failure',screenshot:'only-on-failure'},
 projects:[{name:'chromium',use:{browserName:'chromium'}}],
 webServer:{command:staticPreview?'pnpm exec wrangler dev --ip 127.0.0.1 --port 4492':'pnpm dev',url:baseURL,reuseExistingServer:!process.env.CI},
 expect:{toHaveScreenshot:{maxDiffPixelRatio:0.001}},
});
