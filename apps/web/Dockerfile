FROM node:22-alpine AS deps

WORKDIR /app

COPY package.json package-lock.json* ./

RUN npm ci

FROM node:22-alpine AS builder

WORKDIR /app

ARG MINIO_PUBLIC_ENDPOINT
ARG NEXT_PUBLIC_MEDIA_ORIGIN
ENV MINIO_PUBLIC_ENDPOINT=${MINIO_PUBLIC_ENDPOINT}
ENV NEXT_PUBLIC_MEDIA_ORIGIN=${NEXT_PUBLIC_MEDIA_ORIGIN}

COPY --from=deps /app/node_modules ./node_modules
COPY . .

RUN npm run build

FROM node:22-alpine AS runner

WORKDIR /app

ENV NODE_ENV=production
ENV PORT=3000
ARG MINIO_PUBLIC_ENDPOINT
ARG NEXT_PUBLIC_MEDIA_ORIGIN
ENV MINIO_PUBLIC_ENDPOINT=${MINIO_PUBLIC_ENDPOINT}
ENV NEXT_PUBLIC_MEDIA_ORIGIN=${NEXT_PUBLIC_MEDIA_ORIGIN}

COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/public ./public

CMD ["node", "server.js"]
