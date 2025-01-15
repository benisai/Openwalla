#!/bin/bash
set -e

# Start backend
cd /app/Openwalla/backend && node server.js &

# Wait for backend to start
sleep 7

# Start frontend
cd /app/Openwalla/src
exec npm run dev