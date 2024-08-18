#! /bin/sh

# The argument is private key path

sudo cp $1.pub /etc/apk/keys/
sudo echo PACKAGER_PRIVKEY="$1" > /home/packaging/.abuild/abuild.conf