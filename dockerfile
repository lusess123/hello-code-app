# 基础镜像
FROM  node:20-bullseye-slim AS base
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN apt-get update && apt-get install -y ca-certificates

# 创建一个目录用于存放pnpm store并设置缓存挂载点
RUN mkdir -p /usr/local/pnpm-store
VOLUME /usr/local/pnpm-store


ENV PM_STORE_DIR=/usr/local/pnpm-store
ENV PM_STORE_DIR=/usr/local/pnpm-store

ARG USE_MIRROR=false

RUN if [ "$USE_MIRROR" = "true" ]; then \
      npm config set registry https://registry.npmmirror.com/ && \
      npm install -g pnpm && \
      pnpm config set registry https://registry.npmmirror.com/ && \
      echo "disturl=https://npmmirror.com/mirrors/node" >> /etc/environment && \
      echo "PRISMA_ENGINES_MIRROR=https://registry.npmmirror.com/-/binary/prisma" >> /etc/environment && \
      echo "bcrypt_lib_binary_host_mirror=https://registry.npmmirror.com/" >> /etc/environment && \
      echo "node_bcrypt_binary_host_mirror=https://ghproxy.com/https://github.com/kelektiv/node.bcrypt.js/releases/download/" >> /etc/environment && \
      echo "NODE_PRE_GYP_MIRROR=https://registry.npmmirror.com/binary.html?path=node-pre-gyp/" >> /etc/environment; \
    else \
      npm install -g pnpm; \
    fi

RUN npm install -g pnpm

WORKDIR /usr/src/app
COPY package.json package.json
# 明确地移除node_modules，再安装依赖
RUN rm -rf node_modules && pnpm store prune && pnpm install 
# RUN --mount=type=cache,target=/usr/local/pnpm-store pnpm install 

# 依赖安装阶段
FROM base AS dep
VOLUME /usr/src/app/node_modules
COPY packages/{{projectName}}-fe/package.json packages/{{projectName}}-fe/package.json
COPY packages/{{projectName}}-server/package.json packages/{{projectName}}-server/package.json
COPY packages/{{projectName}}-db/package.json packages/{{projectName}}-db/package.json
COPY packages/{{projectName}}-manage/package.json packages/{{projectName}}-manage/package.json


COPY pnpm-lock.yaml   pnpm-lock.yaml
COPY package.json package.json
COPY pnpm-workspace.yaml pnpm-workspace.yaml
COPY tsconfig.json tsconfig.json
RUN rm -rf node_modules
RUN --mount=type=cache,target=/usr/local/pnpm-store pnpm install 

# 设置环境变量
ENV SERVER_HOST=http://host.docker.internal:3020
ENV jwt_secret=secretjwt{{year}}prod1
ENV NODE_ENV=production

FROM dep AS db_build
COPY packages/{{projectName}}-db packages/{{projectName}}-db
RUN pnpm run db-build

# 构建阶段
FROM db_build AS server_build
COPY packages/{{projectName}}-server packages/{{projectName}}-server
RUN pnpm run server-build


FROM server_build AS fe_build
ARG GIT_COMMIT_TIME=true
ARG GIT_COMMIT_MESSAGE=true
ENV REACT_APP_GIT_COMMIT_TIME=$GIT_COMMIT_TIME
ENV REACT_APP_GIT_COMMIT_MESSAGE=$GIT_COMMIT_MESSAGE



COPY packages/{{projectName}}-fe packages/{{projectName}}-fe
RUN pnpm run fe-build

FROM server_build AS manage_build
ARG GIT_COMMIT_TIME=true
ARG GIT_COMMIT_MESSAGE=true
ENV REACT_APP_GIT_COMMIT_TIME=$GIT_COMMIT_TIME
ENV REACT_APP_GIT_COMMIT_MESSAGE=$GIT_COMMIT_MESSAGE



COPY packages/{{projectName}}-manage packages/{{projectName}}-manage
RUN pnpm run manage-build




# 服务端镜像
FROM server_build AS {{projectName}}-server
WORKDIR /usr/src/app/packages/{{projectName}}-server

# Set proxy environment variables conditionally
ARG USE_MIRROR=true
RUN if [ "$USE_MIRROR" = "true" ]; then \
    echo "export https_proxy=http://host.docker.internal:7890" >> /etc/profile.d/proxy.sh && \
    echo "export http_proxy=http://host.docker.internal:7890" >> /etc/profile.d/proxy.sh && \
    echo "export all_proxy=socks5://host.docker.internal:7890" >> /etc/profile.d/proxy.sh; \
    fi

EXPOSE 3000
CMD [ "pnpm", "start:pm2"]


# 代理镜像
# FROM agent_build AS vvvo-agent
# WORKDIR /usr/src/app/packages/vvvo-agent
# EXPOSE 8001
# CMD [ "pnpm", "start:pm2"]

# 前端镜像和 Nginx 集成
FROM nginx:alpine AS {{projectName}}-fe
COPY --from=fe_build /usr/src/app/packages/{{projectName}}-fe/dist /usr/share/nginx/html
COPY --from=fe_build /usr/src/app/packages/{{projectName}}-fe/nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]


FROM nginx:alpine AS {{projectName}}-manage
COPY --from=manage_build /usr/src/app/packages/{{projectName}}-manage/dist /usr/share/nginx/html
COPY --from=manage_build /usr/src/app/packages/{{projectName}}-manage/nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
