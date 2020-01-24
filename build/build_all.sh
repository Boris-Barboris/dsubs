#!/bin/bash
set -e

COMMIT=$(git describe)
echo "COMMIT=${COMMIT}"

echo "building Windows"
echo "starting VM"
sudo virsh start win7
sleep 30
ssh win7 "cd dsubs\\dsubs_client && git fetch && git checkout ${COMMIT} && dub upgrade && dub build --arch=x86 -c prod -b plain"
scp win7:dsubs/dsubs_client/dsubs_client.exe ./dsubs_client.exe
mkdir dsubs
mv dsubs_client.exe dsubs/
rsync -ar ../dsubs_client/fonts dsubs/
rsync -ar ../dsubs_client/libs-win-x86/*.dll dsubs/
cp ../dsubs_client/alsoft.ini dsubs/
zip -r dsubs-${COMMIT}-win-x86.zip dsubs
rm -rf dsubs
echo "Windows build OK"
sudo virsh shutdown win7


echo "building Trusty"
echo "starting lxd"
sudo systemctl start lxd
sleep 5
lxc start dsubstrusty
sleep 5
ssh dsubstrusty "
  set -e
  . dlang/dmd-2.090.0/activate
  cd dsubs/dsubs_client
  git fetch
  git checkout ${COMMIT}
  dub upgrade
  dub build -b plain -c prod
  cd ~
  bash bundle.sh
"
rsync -v dsubstrusty:~/dsubs-linux-trusty-amd64.tar.gz ./dsubs-${COMMIT}-linux-trusty-amd64.tar.gz
echo "Trusty build OK"
lxc stop dsubstrusty
sudo systemctl stop lxd


echo "building Xenial"
echo "starting VM"
sudo virsh start ubuntu16.04
sleep 30
ssh dsubsxenial "
  set -e
  . dlang/dmd-2.090.0/activate
  cd dsubs/dsubs_client
  git fetch
  git checkout ${COMMIT}
  dub upgrade
  dub build -b plain -c prod
  cd ~
  bash bundle.sh
"
rsync -v dsubsxenial:~/dsubs-linux-xenial-amd64.tar.gz ./dsubs-${COMMIT}-linux-xenial-amd64.tar.gz
echo "Xenial build OK"
sudo virsh destroy ubuntu16.04


echo "building Bionic"
echo "starting VM"
sudo virsh start ubuntu18.04
sleep 30
ssh dsubsbionic "
  set -e
  . dlang/dmd-2.090.0/activate
  cd dsubs/dsubs_client
  git fetch
  git checkout ${COMMIT}
  dub upgrade
  dub build -b plain -c prod
  cd ~
  bash bundle.sh
"
rsync -v dsubsbionic:~/dsubs-linux-bionic-amd64.tar.gz ./dsubs-${COMMIT}-linux-bionic-amd64.tar.gz
echo "Bionic build OK"
sudo virsh shutdown ubuntu18.04
