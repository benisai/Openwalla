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