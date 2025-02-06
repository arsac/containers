# Use an official Node.js runtime as a parent image
FROM node:23-alpine

# Set the working directory in the container
WORKDIR /usr/src/app

# Install git
RUN apk add --no-cache git

# Clone the repository
RUN git clone https://github.com/arsac/nvidia-notifier.git .

# Install the dependencies
RUN npm install

# Define the command to run the app
CMD ["node", "index.js"]