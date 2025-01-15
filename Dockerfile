FROM node:18

WORKDIR /app

COPY package*.json ./
COPY backend/package*.json ./backend/

RUN npm install
RUN cd backend && npm install

COPY . .

EXPOSE 3000

CMD ["npm", "start"]