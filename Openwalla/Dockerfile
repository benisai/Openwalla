# FROM node:18

# WORKDIR /app

# COPY package*.json ./
# COPY backend/package*.json ./backend/

# RUN npm install
# RUN cd backend && npm install

# COPY . .

# #EXPOSE 3000
# #CMD ["npm", "start"]

# EXPOSE 8080 3000

# CMD ["npm", "run", "dev"]


#FROM nikolaik/python-nodejs:latest
FROM node:16

# Set working directory
WORKDIR /app

# Copy the entire project directory into the container
COPY . .

# Install Node.js dependencies
RUN cd Openwalla/backend && npm install

RUN cd Openwalla/src && npm install

# Expose any necessary ports
#EXPOSE 3000
EXPOSE 8080

RUN chmod +x ./entrypoint.sh

# Command to run your application
ENTRYPOINT ["./entrypoint.sh"]
