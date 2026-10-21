import { defineConfig, devices } from "@playwright/test";

const port = Number(process.env.PLAYWRIGHT_PORT ?? 18301);
// Server-side reads (the public box page) go to a stub API the specs start on this port.
export const stubApiPort = Number(process.env.PLAYWRIGHT_STUB_API_PORT ?? 18302);
const executablePath = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH;
// Software WebGL (SwiftShader through ANGLE) so the maps and the 3D body
// figure render the same on a GPU-less CI runner as on a laptop. The CI image's
// own Chrome failed to create a WebGL context, so CI runs Playwright's Chromium.
const args = [
  "--use-angle=swiftshader",
  "--enable-unsafe-swiftshader",
  "--ignore-gpu-blocklist",
  // Docker gives /dev/shm 64 MB, which crashes Chrome's GPU process.
  "--disable-dev-shm-usage",
];
const launchOptions = executablePath ? { executablePath, args } : { args };

export default defineConfig({
  testDir: "./e2e",
  workers: 1,
  timeout: 60_000,
  expect: {
    timeout: 10_000,
  },
  use: {
    baseURL: `http://127.0.0.1:${port}`,
    serviceWorkers: "block",
    trace: "retain-on-failure",
  },
  webServer: {
    command: `NEXT_DIST_DIR=.next-playwright npm run dev -- -H 127.0.0.1 -p ${port}`,
    url: `http://127.0.0.1:${port}`,
    env: { API_PROXY_TARGET: `http://127.0.0.1:${stubApiPort}` },
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
  },
  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"], launchOptions },
    },
    {
      name: "mobile-chrome",
      use: { ...devices["Pixel 7"], launchOptions },
    },
  ],
});
