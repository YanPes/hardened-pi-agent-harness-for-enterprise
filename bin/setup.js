#!/usr/bin/env node

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const PACKAGE_ROOT = path.resolve(__dirname, '..');
const HOME = os.homedir();
const INSTALL_DIR = process.env.PI_SECURE_INSTALL_DIR || path.join(HOME, '.local', 'share', 'secure-pi');
const BIN_DIR = path.join(HOME, '.local', 'bin');
const SHIM_PATH = path.join(BIN_DIR, 'secure-pi');
const TARGET_SCRIPT = path.join(INSTALL_DIR, 'run-secure-pi.sh');
const IMAGE = process.env.PI_SECURE_IMAGE || 'secure-pi:latest';

function detectShell() {
  const shell = process.env.SHELL || '';
  if (shell.includes('zsh')) return 'zsh';
  if (shell.includes('bash')) return 'bash';
  return null;
}

function getRcFile(shellName) {
  if (shellName === 'zsh') return path.join(HOME, '.zshrc');
  if (shellName === 'bash') return path.join(HOME, '.bashrc');
  return null;
}

function ensureDirExists(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function ensureFileExists(filePath) {
  if (!fs.existsSync(filePath)) {
    ensureDirExists(path.dirname(filePath));
    fs.writeFileSync(filePath, '', 'utf8');
  }
}

function copyRecursive(src, dest) {
  const stat = fs.statSync(src);

  if (stat.isDirectory()) {
    ensureDirExists(dest);
    for (const entry of fs.readdirSync(src)) {
      copyRecursive(path.join(src, entry), path.join(dest, entry));
    }
    return;
  }

  ensureDirExists(path.dirname(dest));
  fs.copyFileSync(src, dest);
}

function ensureExecutable(filePath) {
  fs.chmodSync(filePath, 0o755);
}

function shellQuote(value) {
  return `'${String(value).replace(/'/g, `'\\''`)}'`;
}

function installBundle() {
  const assets = ['Dockerfile', 'run-secure-pi.sh', 'config', 'docker'];

  ensureDirExists(INSTALL_DIR);

  for (const asset of assets) {
    copyRecursive(path.join(PACKAGE_ROOT, asset), path.join(INSTALL_DIR, asset));
  }

  ensureExecutable(path.join(INSTALL_DIR, 'run-secure-pi.sh'));
  ensureExecutable(path.join(INSTALL_DIR, 'docker', 'entrypoint.sh'));
}

function writeShim() {
  ensureDirExists(BIN_DIR);

  const shim = `#!/usr/bin/env bash
set -euo pipefail
exec ${shellQuote(TARGET_SCRIPT)} "$@"
`;

  fs.writeFileSync(SHIM_PATH, shim, 'utf8');
  ensureExecutable(SHIM_PATH);
}

function updateShellRc() {
  const shellName = detectShell();

  if (!shellName) {
    console.error('Unsupported shell. This setup currently supports bash and zsh only.');
    process.exit(1);
  }

  const rcFile = getRcFile(shellName);
  ensureFileExists(rcFile);

  const markerStart = '# >>> pi alias setup >>>';
  const markerEnd = '# <<< pi alias setup <<<';
  const pathLine = 'export PATH="$HOME/.local/bin:$PATH"';
  const aliasLine = `alias pi=${shellQuote(SHIM_PATH)}`;
  const block = `\n${markerStart}\n${pathLine}\n${aliasLine}\n${markerEnd}\n`;

  const current = fs.readFileSync(rcFile, 'utf8');

  if (current.includes(markerStart) && current.includes(markerEnd)) {
    const updated = current.replace(
      new RegExp(`${markerStart}[\\s\\S]*?${markerEnd}`, 'm'),
      `${markerStart}\n${pathLine}\n${aliasLine}\n${markerEnd}`
    );
    fs.writeFileSync(rcFile, updated, 'utf8');
    console.log(`Updated pi shell setup in ${rcFile}`);
  } else if (current.includes(aliasLine)) {
    console.log(`pi shell setup already present in ${rcFile}`);
  } else {
    fs.appendFileSync(rcFile, block, 'utf8');
    console.log(`Added pi shell setup to ${rcFile}`);
  }

  return rcFile;
}

function detectTargetArch() {
  const arch = os.arch();
  if (arch === 'x64') return 'amd64';
  if (arch === 'arm64') return 'arm64';
  return '';
}

function canRunDocker() {
  const result = spawnSync('docker', ['version'], { stdio: 'ignore' });
  return result.status === 0;
}

function dockerImageExists() {
  const result = spawnSync('docker', ['image', 'inspect', IMAGE], { stdio: 'ignore' });
  return result.status === 0;
}

function buildImageIfNeeded() {
  if (process.env.PI_SETUP_SKIP_BUILD === '1') {
    console.log('Skipping Docker image build (PI_SETUP_SKIP_BUILD=1)');
    return;
  }

  if (!canRunDocker()) {
    console.log('Docker not ready. First `pi` run will build image after Docker works.');
    return;
  }

  if (dockerImageExists()) {
    console.log(`Docker image already present: ${IMAGE}`);
    return;
  }

  const buildArgs = ['build'];
  const targetArch = process.env.PI_TARGETARCH || detectTargetArch();
  const buildPlatform = process.env.PI_BUILD_PLATFORM || '';
  const piVersion = process.env.PI_VERSION || '';
  const arm64Base = process.env.PI_NODE_BASE_IMAGE_ARM64 || '';

  if (piVersion) {
    buildArgs.push('--build-arg', `PI_VERSION=${piVersion}`);
  }

  if (targetArch) {
    buildArgs.push('--build-arg', `TARGETARCH=${targetArch}`);
  }

  if (arm64Base) {
    buildArgs.push('--build-arg', `NODE_BASE_IMAGE_ARM64=${arm64Base}`);
  }

  if (buildPlatform) {
    buildArgs.push('--platform', buildPlatform);
  }

  buildArgs.push('-t', IMAGE, INSTALL_DIR);

  console.log(`Building Docker image ${IMAGE}...`);
  const result = spawnSync('docker', buildArgs, { stdio: 'inherit' });

  if (result.status !== 0) {
    console.log('Docker build failed. Setup kept installed files. First `pi` run can retry build.');
  }
}

function run() {
  installBundle();
  writeShim();
  const rcFile = updateShellRc();
  buildImageIfNeeded();

  console.log(`Installed secure-pi bundle to ${INSTALL_DIR}`);
  console.log(`Installed launcher to ${SHIM_PATH}`);
  console.log(`Restart shell or run: source ${rcFile}`);
  console.log('Then run: pi');
}

run();
