'use strict';

const os = require('node:os');
const express = require('express');
const { version } = require('./package.json');

const PORT = Number(process.env.PORT) || 3000;
const APP_NAME = process.env.APP_NAME || 'vps-demo';

const log = (msg) => console.log(`${new Date().toISOString()} ${msg}`);

const app = express();

// nginx runs on the same machine: trust its X-Forwarded-For so req.ip is the real client IP.
app.set('trust proxy', 'loopback');

// One line per request; stdout ends up in journald (journalctl -u vps-demo).
app.use((req, res, next) => {
  const started = Date.now();
  res.on('finish', () => {
    log(`${req.ip} ${req.method} ${req.originalUrl} ${res.statusCode} ${Date.now() - started}ms`);
  });
  next();
});

app.get('/', (req, res) => {
  res.json({
    app: APP_NAME,
    version,
    hostname: os.hostname(),
    uptimeSeconds: Math.round(process.uptime()),
  });
});

app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok' });
});

// Loopback only: the public entry point is nginx on port 80, never port 3000.
const server = app.listen(PORT, '127.0.0.1', () => {
  log(`${APP_NAME} v${version} listening on http://127.0.0.1:${PORT}`);
});

// systemd sends SIGTERM on stop/restart: finish in-flight requests, then exit.
function shutdown(signal) {
  log(`${signal} received, closing server`);
  server.close(() => {
    log('server closed, bye');
    process.exit(0);
  });
  // Safety net if a connection hangs; systemd would SIGKILL after 90s anyway.
  setTimeout(() => process.exit(1), 10_000).unref();
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
