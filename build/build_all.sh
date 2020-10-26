#!/bin/bash
set -e

COMMIT=$(git describe)
echo "COMMIT=${COMMIT}"

echo "building Windows"
echo "starting VM"
sudo virsh start win7
sleep 60
ssh win7 "cd dsubs\\dsubs_client && git fetch --force && git fetch --tags --force && git checkout ${COMMIT} && git submodule update --init && dub upgrade && dub build --arch=x86_64 -c prod -b debug"
scp win7:dsubs/dsubs_client/dsubs_client.exe ./dsubs_client.exe
mkdir dsubs
mv dsubs_client.exe dsubs/
rsync -ar ../dsubs_client/fonts dsubs/
rsync -ar ../dsubs_client/libs-win-x64/*.dll dsubs/
cp ../dsubs_client/alsoft.ini dsubs/
zip -r dsubs-${COMMIT}-win-x64.zip dsubs
rm -rf dsubs
echo "Windows build OK"
sudo virsh shutdown win7


echo "building Trusty"
echo "starting lxd"
sudo systemctl start lxd
sleep 10
sudo lxc start dsubstrusty
sleep 10
ssh dsubstrusty "
  set -e
  . dlang/dmd-2.093.1/activate
  cd dsubs/dsubs_client
  git fetch --force
  git fetch --tags --force
  git checkout ${COMMIT}
  git submodule update --init
  dub upgrade
  dub build -b debug -c prod
  cd ~
  bash bundle.sh
  sync
"
rsync -v dsubstrusty:~/dsubs-linux-trusty-amd64.tar.gz ./dsubs-${COMMIT}-linux-trusty-amd64.tar.gz
echo "Trusty build OK"
sudo lxc stop dsubstrusty
sudo systemctl stop lxd


echo "building Xenial"
echo "starting VM"
sudo virsh start ubuntu16.04
sleep 60
ssh dsubsxenial "
  set -e
  . dlang/dmd-2.093.1/activate
  cd dsubs/dsubs_client
  git fetch --force
  git fetch --tags --force
  git checkout ${COMMIT}
  git submodule update --init
  dub upgrade
  dub build -b debug -c prod
  cd ~
  bash bundle.sh
  sync
"
rsync -v dsubsxenial:~/dsubs-linux-xenial-amd64.tar.gz ./dsubs-${COMMIT}-linux-xenial-amd64.tar.gz
echo "Xenial build OK"
sudo virsh destroy ubuntu16.04


echo "building Bionic"
echo "starting VM"
sudo virsh start ubuntu18.04
sleep 60
ssh dsubsbionic "
  set -e
  . dlang/dmd-2.093.1/activate
  cd dsubs/dsubs_client
  git fetch --force
  git fetch --tags --force
  git checkout ${COMMIT}
  git submodule update --init
  dub upgrade
  dub build -b debug -c prod
  cd ~
  bash bundle.sh
  sync
"
rsync -v dsubsbionic:~/dsubs-linux-bionic-amd64.tar.gz ./dsubs-${COMMIT}-linux-bionic-amd64.tar.gz
echo "Bionic build OK"
sudo virsh destroy ubuntu18.04
