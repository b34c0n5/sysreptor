#!/bin/bash
set -e  # exit on error
error_cleanup() {
    if
        [ "$created_backup" == "1" ]
    then
        set +e
        echo cd "$script_location"
        echo "Trying to restore your old version..."
        cd `dirname "$script_location"`
        mv "$sysreptor_directory" "$sysreptor_directory"-failed-update-$(date -Iseconds)
        mv "$backup_copy" "$sysreptor_directory"
        cd "$sysreptor_directory"/deploy
        docker compose up -d
        echo "Error failed during installation."
        exit -3
    fi
    exit -4
}
trap 'error_cleanup' ERR INT
echo "Easy update of SysReptor"
echo ""
error=1
for cmd in curl tar docker date
do
    if
        ! command -v "$cmd" >/dev/null
    then
        echo "Error: $cmd is not installed."
        error=0
    fi
done
if 
    ! docker compose version >/dev/null 2>&1
then
    echo "docker compose v2 is not installed."
    error=0
fi
if
    test 0 -eq "$error"
then
    exit -1
fi
# cd to script location
script_location="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
cd "$script_location"
# check if parent directory writable
if
    ! test -w ..
then
    echo "\"`readlink -e ..`\" not writeable. Exiting..."
    exit -2
fi
download_url=https://github.com/syslifters/sysreptor/releases/latest/download/source-prebuilt.tar.gz
source deploy/.env
echo "Your current version is $SYSREPTOR_VERSION"
if [ "$1" != "--force" ]
then
    echo "Checking if update is available..."
    redirect_location=`curl -I -s "$download_url" | grep -i ^location | tr -d '\n\r'`
    download=`echo "$redirect_location" | rev | cut -d/ -f 3 | rev`
    version=`echo "$redirect_location" | rev | cut -d/ -f 2 | rev`
    filename=`echo "$redirect_location" | rev | cut -d/ -f 1 | rev`
    if [ "$download" != "download" ] || [ "$filename" != "source-prebuilt.tar.gz" ]
    then
        echo "Checking for new version failed."
        exit -6
    fi
    if [ "$version" != "$SYSREPTOR_VERSION" ]
    then
        echo "Found newer version $version"
    else
        echo "The latest SysReptor version is already installed."
        echo ""
        echo "Checking when last docker image build was..."
        if [[ `docker inspect -f '{{ .Created }}' sysreptor-app` > `date +%F -d '7 days ago'` ]]
        then
            echo "Last build was less then seven days ago. Use '--force' to force update."
            exit 0
        else
            echo "Last build was more then seven days ago. Updating to get the latest dependencies installed..."
        fi
    fi
fi

echo "Downloading SysReptor from $download_url ..."
curl -s -L --output ../sysreptor.tar.gz "$download_url"
echo "Checking download..."
if ! tar -tzf ../sysreptor.tar.gz >/dev/null 2>&1
then
    echo "Download did not succeed..."
    exit -5
fi
echo "Creating backup copy of your current installation..."
sysreptor_directory=${PWD##*/}
backup_copy="$sysreptor_directory"-backup-$(date -Iseconds)
cd ..
mv "$sysreptor_directory" "$backup_copy"
created_backup=1
echo "Backup copy located at $backup_copy"
echo "Unpacking sysreptor.tar.gz..."
mkdir "$sysreptor_directory"
tar xzf sysreptor.tar.gz -C "$sysreptor_directory" --strip-components=1
echo "Copy your app.env..."
cp "${backup_copy}/deploy/app.env" "${sysreptor_directory}/deploy/app.env"
if grep "sysreptor/docker-compose.yml" "${backup_copy}/deploy/docker-compose.yml"
then
    # Copy docker-compose.yml if it is not the old version (2024.58 and earlier)
    echo "Copy your docker-compose.yml..."
    cp "${backup_copy}/deploy/docker-compose.yml" "${sysreptor_directory}/deploy/docker-compose.yml"
fi
if [ -f "${backup_copy}/deploy/caddy/Caddyfile" ]; then
    echo "Copying Caddyfile..."
    cp "${backup_copy}/deploy/caddy/Caddyfile" "${sysreptor_directory}/deploy/caddy/Caddyfile"
fi
echo "Build and launch SysReptor via docker compose..."
echo "We are downloading and installing all dependencies."
echo "This may take a few minutes."

# Remove deprecated docker-compose.override.yml which is there for legacy reasons
rm "${sysreptor_directory}/deploy/docker-compose.override.yml" 2>/dev/null || true
if grep "^LICENSE=" "${sysreptor_directory}/deploy/app.env"
then
    # This if-statement will be removed July 2025
    include_languagetool="  - languagetool/docker-compose.yml"
    if ! grep -q "^$include_languagetool" "${sysreptor_directory}/deploy/docker-compose.yml"
    then
        # Include languagetool in docker-compose.yml
        sed -i "s#include:#include:\n$include_languagetool#" "${sysreptor_directory}/deploy/docker-compose.yml"
    fi
fi
if
    cd "$sysreptor_directory"/deploy
    ! docker compose build --no-cache --pull || ! docker compose up -d
then
    echo "Ups. Something did not work while building and launching your containers."
    error_cleanup
fi
echo "Nice. Successfully updated."
echo "Easy peasy lemon squeezy."
