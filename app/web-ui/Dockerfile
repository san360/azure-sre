FROM --platform=$BUILDPLATFORM node:22-alpine AS build
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .
RUN npm run build

FROM --platform=linux/amd64 nginx:alpine AS runtime

COPY nginx.conf /etc/nginx/templates/default.conf.template
COPY --from=build /app/dist /usr/share/nginx/html

ENV MENU_API_URL=http://menu-api:8080
ENV ORDER_API_URL=http://order-api:8080
ENV PAYMENT_API_URL=http://payment-service:8080

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]
