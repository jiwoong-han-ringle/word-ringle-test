#!/bin/bash
set -e

# Wait for MySQL to be ready
while ! mysqladmin ping -h mysql --silent; do
    echo 'Waiting for MySQL...'
    sleep 1
done

echo 'MySQL is ready!'

# Run database migrations
bundle exec rails db:migrate

# Start the Rails server
exec "$@"