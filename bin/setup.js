#!/usr/bin/env node

const fs = require('fs');
const os = require('os');
const path = require('path');

function detectShell() {
  const shell = process.env.SHELL || '';
  if (shell.includes('zsh')) return 'zsh';
  if (shell.includes('bash')) return 'bash';
  return null;
}

function getRcFile(shellName) {
  const home = os.homedir();
  if (shellName === 'zsh') return path.join(home, '.zshrc');
  if (shellName === 'bash') return path.join(home, '.bashrc');
  return null;
}

function ensureFileExists(filePath) {
  if (!fs.existsSync(filePath)) {
    fs.writeFileSync(filePath, '', 'utf8');
  }
}

function run() {
  const shellName = detectShell();

  if (!shellName) {
    console.error('Unsupported shell. This setup currently supports bash and zsh only.');
    process.exit(1);
  }

  const rcFile = getRcFile(shellName);
  const scriptPath = path.resolve(__dirname, '..', 'run-secure-pi.sh');

  if (!fs.existsSync(scriptPath)) {
    console.error(`Could not find run-secure-pi.sh at: ${scriptPath}`);
    process.exit(1);
  }

  ensureFileExists(rcFile);

  const markerStart = '# >>> pi alias setup >>>';
  const markerEnd = '# <<< pi alias setup <<<';
  const aliasLine = `alias pi=\"${scriptPath}\"`;
  const block = `\n${markerStart}\n${aliasLine}\n${markerEnd}\n`;

  const current = fs.readFileSync(rcFile, 'utf8');

  if (current.includes(markerStart) && current.includes(markerEnd)) {
    const updated = current.replace(
      new RegExp(`${markerStart}[\\s\\S]*?${markerEnd}`, 'm'),
      `${markerStart}\n${aliasLine}\n${markerEnd}`
    );
    fs.writeFileSync(rcFile, updated, 'utf8');
    console.log(`Updated pi alias in ${rcFile}`);
  } else if (current.includes(aliasLine)) {
    console.log(`Alias already present in ${rcFile}`);
  } else {
    fs.appendFileSync(rcFile, block, 'utf8');
    console.log(`Added pi alias to ${rcFile}`);
  }

  console.log(`\nRestart your shell or run: source ${rcFile}`);
}

run();
