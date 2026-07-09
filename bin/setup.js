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
const VOLUME = process.env.PI_SECURE_VOLUME || 'secure-pi-agent';
const MARKER_START = '# >>> pi alias setup >>>';
const MARKER_END = '# <<< pi alias setup <<<';

function detectShell() {
  const shell = process.env.SHELL || '';
  if (shell.includes('zsh')) return 'zsh';
  if (shell.includes('bash')) return 'bash';
  if (shell.includes('fish')) return 'fish';
  return null;
}

function getRcFile(shellName) {
  if (shellName === 'zsh') return path.join(HOME, '.zshrc');
  if (shellName === 'bash') return path.join(HOME, '.bashrc');
  if (shellName === 'fish') return path.join(HOME, '.config', 'fish', 'config.fish');
  return null;
}

function getKnownRcFiles() {
  return ['bash', 'zsh', 'fish'].map(getRcFile);
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

function removePath(targetPath) {
  if (!fs.existsSync(targetPath)) {
    return false;
  }

  fs.rmSync(targetPath, { recursive: true, force: true });
  return true;
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
    console.error('Unsupported shell. This setup currently supports bash, zsh and fish only.');
    process.exit(1);
  }

  const rcFile = getRcFile(shellName);
  ensureFileExists(rcFile);

  const pathLine = 'export PATH="$HOME/.local/bin:$PATH"';
  const aliasLine = `alias pi=${shellQuote(SHIM_PATH)}`;
  const block = `\n${MARKER_START}\n${pathLine}\n${aliasLine}\n${MARKER_END}\n`;

  const current = fs.readFileSync(rcFile, 'utf8');

  if (current.includes(MARKER_START) && current.includes(MARKER_END)) {
    const updated = current.replace(
      new RegExp(`${MARKER_START}[\\s\\S]*?${MARKER_END}`, 'm'),
      `${MARKER_START}\n${pathLine}\n${aliasLine}\n${MARKER_END}`
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

function removeShellSetup() {
  let changed = false;

  for (const rcFile of getKnownRcFiles()) {
    if (!rcFile || !fs.existsSync(rcFile)) {
      continue;
    }

    const current = fs.readFileSync(rcFile, 'utf8');
    if (!current.includes(MARKER_START) || !current.includes(MARKER_END)) {
      continue;
    }

    const updated = current
      .replace(new RegExp(`\\n?${MARKER_START}[\\s\\S]*?${MARKER_END}\\n?`, 'm'), '\n')
      .replace(/^\n+/, '');
    fs.writeFileSync(rcFile, updated, 'utf8');
    console.log(`Removed pi shell setup from ${rcFile}`);
    changed = true;
  }

  if (!changed) {
    console.log('No shell alias block found in rc files.');
  }
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

function runDocker(args) {
  return spawnSync('docker', args, { stdio: 'inherit' });
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

function printHelp() {
  console.log(`Usage:
  npx zero-trust-pi-agent-harness
  npx zero-trust-pi-agent-harness install
  npx zero-trust-pi-agent-harness clean [--yes] [--keep-docker]

Commands:
  install        Install/update the local secure-pi bundle (default)
  clean          Remove local bundle, launcher, shell alias, and Docker artifacts

Options:
  --yes          Skip confirmation prompt for destructive cleanup
  --keep-docker  Keep Docker image/volume and only remove local files
`);
}

function confirmCleanup() {
  if (process.env.PI_SECURE_CLEAN_FORCE === '1' || process.argv.includes('--yes')) {
    return true;
  }

  process.stdout.write(
    `This will remove:\n` +
    `- ${INSTALL_DIR}\n` +
    `- ${SHIM_PATH}\n` +
    `- pi shell alias block from bash/zsh/fish rc files\n` +
    `- Docker image ${IMAGE} and volume ${VOLUME} (unless --keep-docker)\n\n` +
    `Continue? [y/N] `
  );

  try {
    const answer = fs.readFileSync(0, 'utf8').trim().toLowerCase();
    return answer === 'y' || answer === 'yes';
  } catch {
    return false;
  }
}

function cleanInstall() {
  const keepDocker = process.argv.includes('--keep-docker');

  if (!confirmCleanup()) {
    console.log('Cleanup cancelled.');
    process.exit(1);
  }

  const removedBundle = removePath(INSTALL_DIR);
  console.log(removedBundle ? `Removed ${INSTALL_DIR}` : `Not found: ${INSTALL_DIR}`);

  const removedShim = removePath(SHIM_PATH);
  console.log(removedShim ? `Removed ${SHIM_PATH}` : `Not found: ${SHIM_PATH}`);

  removeShellSetup();

  if (keepDocker) {
    console.log('Keeping Docker image and volume (--keep-docker).');
    return;
  }

  if (!canRunDocker()) {
    console.log('Docker not available; skipped Docker image/volume cleanup.');
    return;
  }

  console.log(`Removing Docker volume ${VOLUME}...`);
  runDocker(['volume', 'rm', '-f', VOLUME]);

  console.log(`Removing Docker image ${IMAGE}...`);
  runDocker(['image', 'rm', '-f', IMAGE]);
}

function install() {
  installBundle();
  writeShim();
  const rcFile = updateShellRc();
  buildImageIfNeeded();

  console.log(`Installed secure-pi bundle to ${INSTALL_DIR}`);
  console.log(`Installed launcher to ${SHIM_PATH}`);
  console.log('----------------------------------------------');
  console.log(`Restart shell or run: source ${rcFile}`);
  console.log('Then run: pi');
}

function main() {
  const [command] = process.argv.slice(2).filter((arg) => !arg.startsWith('--'));

  if (command === 'help' || command === '--help' || process.argv.includes('--help')) {
    printHelp();
    return;
  }

  if (!command || command === 'install') {
    install();
    return;
  }

  if (command === 'clean') {
    cleanInstall();
    return;
  }

  console.error(`Unknown command: ${command}`);
  printHelp();
  process.exit(1);
}

main();
