FROM node:22-alpine
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
COPY relay ./relay
COPY example-deck ./example-deck
ENV HOST=0.0.0.0 PORT=8080
USER node
EXPOSE 8080
CMD ["node", "relay/server.cjs"]
