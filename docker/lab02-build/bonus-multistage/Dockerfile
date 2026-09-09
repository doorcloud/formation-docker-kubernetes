# Bonus (hors check.sh) : build Node 22 puis image Nginx minimale.
FROM node:22-alpine AS build
WORKDIR /src
COPY package.json index.html ./
# En production : npm ci && npm run build. Ici un "build" offline.
RUN mkdir -p dist && cp index.html dist/index.html

FROM nginx:1.27-alpine
COPY --from=build /src/dist /usr/share/nginx/html
EXPOSE 80
