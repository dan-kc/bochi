FROM mcr.microsoft.com/playwright:v1.48.0-focal

WORKDIR /tests

COPY package.json package-lock.json ./

RUN npm install

COPY . .

ENTRYPOINT ["npx", "playwright", "test", "--reporter=list"]
