FROM node:22-alpine

WORKDIR /app

COPY package.json package-lock.json ./

RUN npm ci --omit=dev

COPY src/ ./src/

RUN chown -R node:node /app

USER node

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD node -e "require('net').createConnection(${PORT:-8080}, '127.0.0.1').on('connect', () => process.exit(0)).on('error', () => process.exit(1))"

EXPOSE 8080

CMD ["node", "src/index.js"]