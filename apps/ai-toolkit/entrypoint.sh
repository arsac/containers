#! /bin/bash

unset UV_SYSTEM_PYTHON

mkdir -p "${VENV_FOLDER}"
uv venv --system-site-packages --link-mode=copy --allow-existing "${VENV_FOLDER}"
source "${VENV_FOLDER}/bin/activate"

# Check if the db file /config/aitk_db.db exists, if not, create it from default
if [ ! -f "/config/aitk_db.db" ]; then
    echo "Creating database file from default..."
    cp /app/aitk_db.db.default /config/aitk_db.db
fi

# Verify we can access the database through the symlink before running update
if [ -e "/app/aitk_db.db" ]; then
    echo "Running db update..."
    cd /app/ui
    npm run update_db
else
    echo "Warning: Cannot access database symlink, skipping update_db"
fi

# If running npm commands, ensure we're in the right directory
if [[ "$1" == "npm" ]]; then
    cd /app/ui
fi

"$@"
