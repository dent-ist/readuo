const fs = require('fs');
const path = require('path');
const { pathToFileURL } = require('url');
const { spawnSync } = require('child_process');

const workspace = path.resolve(__dirname, '..');
const sourcePath = path.join(workspace, 'design', 'readuo-first-release.html');
const outputDir = path.join(
  workspace,
  'app',
  'test',
  'artifacts',
  'p1-04-review2',
  'canonical',
);
const chromePath = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const wrapperPath = path.join(__dirname, '.p1-04-canonical-capture.html');
const profilePath = path.join(__dirname, '.p1-04-capture-profile');
const fragment = fs.readFileSync(sourcePath, 'utf8');

fs.mkdirSync(outputDir, { recursive: true });

function capture(screen, width, height, filename) {
  const document = `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>html,body{margin:0}#readuo-modern-complete i[data-lucide]{display:inline-block;width:18px;height:18px;flex:none}</style>${fragment}<style>html,body{width:${width}px;height:${height}px;overflow:hidden}#readuo-modern-complete{width:${width}px!important;max-width:none!important;margin:0!important}#readuo-modern-complete .rd-review,#readuo-modern-complete .rd-browser,#readuo-modern-complete .rd-paging,#readuo-modern-complete .rd-caption{display:none!important}#readuo-modern-complete .rd-phone{width:${width}px!important;max-width:none!important;height:${height}px!important;min-height:${height}px!important;margin:0!important;border:0!important;border-radius:0!important;box-shadow:none!important}</style><script>document.getElementById('readuo-modern-complete').__readuo.navigate(${JSON.stringify(screen)});</script>`;
  fs.writeFileSync(wrapperPath, document);
  fs.rmSync(profilePath, { recursive: true, force: true });
  const outputPath = path.join(outputDir, filename);
  const result = spawnSync(
    chromePath,
    [
      '--headless=new',
      '--disable-gpu',
      '--hide-scrollbars',
      '--no-first-run',
      '--force-device-scale-factor=1',
      '--run-all-compositor-stages-before-draw',
      '--virtual-time-budget=1000',
      `--window-size=${width},${height}`,
      `--user-data-dir=${profilePath}`,
      `--screenshot=${outputPath}`,
      pathToFileURL(wrapperPath).href,
    ],
    { encoding: 'utf8' },
  );
  if (result.status !== 0) {
    throw new Error(
      result.stderr || result.stdout || `Chrome exited ${result.status}`,
    );
  }
}

try {
  capture('catalogue-search', 390, 844, 'catalogue-search-390x844.png');
  capture('catalogue-results', 390, 844, 'catalogue-results-390x844.png');
  capture(
    'catalogue-no-results',
    390,
    844,
    'catalogue-no-results-390x844.png',
  );
  capture('manual-confirm', 390, 844, 'manual-confirm-390x844.png');
  capture('catalogue-search', 360, 640, 'catalogue-search-360x640.png');
  capture('catalogue-results', 360, 640, 'catalogue-results-360x640.png');
  capture(
    'catalogue-no-results',
    360,
    640,
    'catalogue-no-results-360x640.png',
  );
  capture('manual-confirm', 360, 640, 'manual-confirm-360x640.png');
} finally {
  fs.rmSync(wrapperPath, { force: true });
  fs.rmSync(profilePath, { recursive: true, force: true });
}
